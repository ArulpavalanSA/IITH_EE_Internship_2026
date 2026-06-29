%% MWC Offline Calibration & Filter Coefficient Generator Script
clear; clc; close all;

%% 1. System Parameters Configuration
DATA_WIDTH        = 16;  % Verilog DATA_WIDTH
COEFF_WIDTH       = 16;  % Verilog COEFF_WIDTH
DATA_FRAC_WIDTH   = 8;   % Q8.8 Format for Data
COEFF_FRAC_WIDTH  = 8;   % Q8.8 Format for Coefficients

HS_NUM_TAPS       = 16;  % Number of taps for Sharp LPF (Hs)
HC_NUM_TAPS       = 16;  % Number of taps for Compensation Filter (Hc)

% MWC Frequency parameters (normalized or scalable)
G = 7;                   % Number of test tones (Must be an odd number)
N_fft = 512;             % FFT resolution points for continuous spectrum estimation
fs = 100e6;              % Sampling frequency (100 MHz master pipeline)

%% 2. Generate Newman-Phase Training Signal & Ideal Spectrum (Z_k)
% Equation 14: Compute Newman Phases to prevent ADC clipping
zeta = 0:G-1;
phi_newman = (pi * (zeta - 1).^2) / G;

% Construct the frequency grid
f_grid = linspace(-fs/2, fs/2, N_fft);
Z_ideal = zeros(1, N_fft);

% Populate the ideal spectrum with the low crest factor multi-tones
for i = 1:G
    % Find closest bin on frequency grid for each test tone
    tone_freq = (i - (G+1)/2) * (fs / (G+2)); 
    [~, bin_idx] = min(abs(f_grid - tone_freq));
    % Apply complex representation incorporating Newman Phase
    Z_ideal(bin_idx) = exp(1j * phi_newman(i));
end

%% 3. Model Hardware Imperfections (Simulated Corrupted Observation Y_tilde)
% Let's create an arbitrary frequency distortion curve representing physical board traces
% Real boards typically introduce low-pass rolling attenuation and phase shifts
H_eq_true = 0.8 * exp(-1j * 2 * pi * f_grid * 2e-9) ./ (1 + 1j * (f_grid / (fs/3)));

% Equation 15: Generate the distorted ADC spectrum output observed by the system
% (Assuming ideal code sequence weights for isolated tone extraction simplification)
Y_corrupted = Z_ideal .* H_eq_true;

%% 4. Execute Equation 16: Distortion Estimation (H_eq_hat)
H_eq_hat = zeros(size(Y_corrupted));
active_bins = (Z_ideal ~= 0); % Pinpoint the exact bins containing active test tones

% Perform direct division at active multi-tone nodes
H_eq_hat(active_bins) = Y_corrupted(active_bins) ./ Z_ideal(active_bins);

% Use Linear Interpolation to map the continuous distortion curve across the band
H_eq_continuous = interp1(f_grid(active_bins), H_eq_hat(active_bins), f_grid, 'linear', 'extrap');

%% 5. Construct Target Frequency Response Filters
% Target A: Sharp LPF (Hs) Brick-Wall Target Shape
cutoff_freq = fs / 8;
Hs_target = double(abs(f_grid) <= cutoff_freq);

% Equation 17: Compensation Filter (Hc) Pointwise Matrix Inversion
% Safety Guard: Avoid dividing by zero outside the passband
Hc_target = zeros(size(f_grid));
passband_mask = (Hs_target > 0) & (abs(H_eq_continuous) > 1e-4);
Hc_target(passband_mask) = 1 ./ (H_eq_continuous(passband_mask) .* Hs_target(passband_mask));

%% 6. Convert Frequency Responses to Time-Domain Coefficients via IFFT
% Shift spectra back to standard standard formatting before running IFFT
hs_time = real(ifft(ifftshift(Hs_target)));
hc_time = real(ifft(ifftshift(Hc_target)));

% Truncate/Window vectors to match targeted hardware register tap dimensions
hs_taps = hs_time(1:HS_NUM_TAPS);
hc_taps = hc_time(1:HC_NUM_TAPS);

% Normalize coefficients window to protect against integer overflows
hs_taps = hs_taps / max(abs(hs_taps)) * 0.9;
hc_taps = hc_taps / max(abs(hc_taps)) * 0.9;

%% 7. Quantize to Fixed-Point Layout & Generate Verilog Hex Vectors
fprintf('\n===========================================================\n');
fprintf('     GENERATED FIR COEFFICIENT HEX STRINGS FOR VERILOG     \n');
fprintf('===========================================================\n\n');

% Generate Sharp LPF Vector Hex String
fprintf('// Copy-paste this parameter for hs_coeff_vector:\n');
fprintf('hs_coeff_vector = %d''h', HS_NUM_TAPS * COEFF_WIDTH);
for idx = HS_NUM_TAPS:-1:1
    q_val = round(hs_taps(idx) * (2^COEFF_FRAC_WIDTH));
    hex_val = dec2hex(mod(q_val, 16^ (COEFF_WIDTH/4)), COEFF_WIDTH/4);
    fprintf('%s', hex_val);
end
fprintf(';\n\n');

% Generate Compensation Filter Vector Hex String
fprintf('// Copy-paste this parameter for hc_coeff_vector:\n');
fprintf('hc_coeff_vector = %d''h', HC_NUM_TAPS * COEFF_WIDTH);
for idx = HC_NUM_TAPS:-1:1
    q_val = round(hc_taps(idx) * (2^COEFF_FRAC_WIDTH));
    hex_val = dec2hex(mod(q_val, 16^ (COEFF_WIDTH/4)), COEFF_WIDTH/4);
    fprintf('%s', hex_val);
end
fprintf(';\n\n');

%% 8. Plot Diagnostics for Verification
figure;
subplot(2,1,1);
plot(f_grid/1e6, abs(H_eq_true), 'r--', 'LineWidth', 1.5); hold on;
plot(f_grid/1e6, abs(H_eq_continuous), 'b', 'LineWidth', 1.2);
title('Magnitude Response Tracking'); xlabel('Frequency (MHz)'); ylabel('Gain');
legend('True Physical Board Error', 'Interpolated Estimation (\\hat{H}_{eq})'); grid on;

subplot(2,1,2);
plot(f_grid/1e6, abs(Hc_target), 'g', 'LineWidth', 1.5);
title('Calculated Compensation Filter Target (H_C)'); xlabel('Frequency (MHz)'); ylabel('Gain');
grid on;

%% Append to your MATLAB script: Generate Input Data File
% Perform IFFT on the distorted spectrum to get time-domain samples
y_time_corrupted = real(ifft(ifftshift(Y_corrupted)));

% Scale and quantize the waveform to Q8.8 fixed-point format
y_quantized = round(y_time_corrupted / max(abs(y_time_corrupted)) * 0.7 * (2^DATA_FRAC_WIDTH));

% Open a file and write the data as signed integers or hex strings
fid = fopen('adc_din.txt', 'w');
for i = 1:length(y_quantized)
    % Convert to 16-bit 2's complement hex string
    val = y_quantized(i);
    if val < 0
        val = val + 65536;
    end
    fprintf(fid, '%s\n', dec2hex(val, 4));
end
fclose(fid);
fprintf('Successfully generated adc_din.txt with %d samples.\n', length(y_quantized));