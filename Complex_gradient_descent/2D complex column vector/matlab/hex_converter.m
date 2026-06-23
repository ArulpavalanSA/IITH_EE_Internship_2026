% MATLAB Script: Convert Workspace Arrays to Hardware-Ready Verilog Hex
% Ensures y_vec is 16-bit Real, and Matrix A columns are split into 
% separate 16-bit Real and Imag arrays for Column 1 and Column 2.

%% 1. Fixed-Point Configuration (Q4.12)
FractionalBits = 12;
TotalBits = 16;

% Saturation boundaries for 16-bit signed integers
MaxInt = (2^(TotalBits - 1)) - 1;  %  32767
MinInt = -(2^(TotalBits - 1));     % -32768

%% 2. Core Scalar Conversion Logic
% Converts a floating-point scalar into a 16-bit unsigned integer equivalent
toQ412Int = @(v) mod(round(min(max(v * (2^FractionalBits), MinInt), MaxInt)), 2^TotalBits);

%% 3. Process Workspace Variable 'A' (Column 1 & Column 2 Separated)
if exist('A', 'var')
    % --- COLUMN 1 PROCESSING ---
    A_col1 = A(:, 8); 
    A1_real = real(A_col1);
    A1_imag = imag(A_col1);

    A1_real_hex = arrayfun(@(v) sprintf("16'h%04X", toQ412Int(v)), A1_real);
    A1_imag_hex = arrayfun(@(v) sprintf("16'h%04X", toQ412Int(v)), A1_imag);

    % --- COLUMN 2 PROCESSING ---
    if size(A, 2) >= 2
        A_col2 = A(:, 9);
        A2_real = real(A_col2);
        A2_imag = imag(A_col2);

        A2_real_hex = arrayfun(@(v) sprintf("16'h%04X", toQ412Int(v)), A2_real);
        A2_imag_hex = arrayfun(@(v) sprintf("16'h%04X", toQ412Int(v)), A2_imag);
    else
        error('Matrix "A" does not have a second column.');
    end

    % --- PRINT GENERATED LITERALS ---
    fprintf('// ===================================================\n');
    fprintf('//  VARIABLE: A (COLUMN 1) -> 16-bit REAL Part Only\n');
    fprintf('// ===================================================\n');
    disp(strjoin(A1_real_hex, ', '));

    fprintf('\n// ===================================================\n');
    fprintf('//  VARIABLE: A (COLUMN 1) -> 16-bit IMAGINARY Part Only\n');
    fprintf('// ===================================================\n');
    disp(strjoin(A1_imag_hex, ', '));

    fprintf('\n// ===================================================\n');
    fprintf('//  VARIABLE: A (COLUMN 2) -> 16-bit REAL Part Only\n');
    fprintf('// ===================================================\n');
    disp(strjoin(A2_real_hex, ', '));

    fprintf('\n// ===================================================\n');
    fprintf('//  VARIABLE: A (COLUMN 2) -> 16-bit IMAGINARY Part Only\n');
    fprintf('// ===================================================\n');
    disp(strjoin(A2_imag_hex, ', '));
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