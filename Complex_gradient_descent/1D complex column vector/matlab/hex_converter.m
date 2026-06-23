% MATLAB Script: Convert Workspace Arrays to Hardware-Ready Verilog Hex
% Ensures y_vec is 16-bit Real, and A is split into separate 16-bit Real and Imag arrays

%% 1. Fixed-Point Configuration (Q4.12)
FractionalBits = 12;
TotalBits = 16;

% Saturation boundaries for 16-bit signed integers
MaxInt = (2^(TotalBits - 1)) - 1;  %  32767
MinInt = -(2^(TotalBits - 1));     % -32768

%% 2. Core Scalar Conversion Logic
% Converts a floating-point scalar into a 16-bit unsigned integer equivalent
toQ412Int = @(v) mod(round(min(max(v * (2^FractionalBits), MinInt), MaxInt)), 2^TotalBits);

%% 3. Process Workspace Variable 'A' (Separate 16-bit Real and Imaginary Arrays)
if exist('A', 'var')
    A_target = A(:, 1); % Extracting the first column

    % Separate the complex vector into individual real and imaginary vectors
    A_real = real(A_target);
    A_imag = imag(A_target);

    % Convert both arrays to 16-bit Q4.12 hex representations
    A_real_hex = arrayfun(@(v) sprintf("16'h%04X", toQ412Int(v)), A_real);
    A_imag_hex = arrayfun(@(v) sprintf("16'h%04X", toQ412Int(v)), A_imag);

    fprintf('// ===================================================\n');
    fprintf('//  VARIABLE: A (First Column) -> 16-bit REAL Part Only\n');
    fprintf('// ===================================================\n');
    disp(strjoin(A_real_hex, ', '));

    fprintf('\n// ===================================================\n');
    fprintf('//  VARIABLE: A (First Column) -> 16-bit IMAGINARY Part Only\n');
    fprintf('// ===================================================\n');
    disp(strjoin(A_imag_hex, ', '));
else
    warning('Variable "A" was not found in the workspace.');
end

fprintf('\n\n');

%% 4. Process Workspace Variable 'y_vec' (16-bit Real Only)
if exist('y_vec', 'var')
    % y_vec only contains real parts as per your specification
    y_real = real(y_vec); 

    y_hex = arrayfun(@(v) sprintf("16'h%04X", toQ412Int(v)), y_real);

    fprintf('// ===================================================\n');
    fprintf('//  VARIABLE: y_vec -> 16-bit Real Only\n');
    fprintf('// ===================================================\n');
    disp(strjoin(y_hex, ', '));
else
    warning('Variable "y_vec" was not found in the workspace.');
end