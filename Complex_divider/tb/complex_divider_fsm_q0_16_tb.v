`timescale 1ns / 1ps

module complex_divider_fsm_q0_16_tb;

    parameter BIT_WIDTH  = 16;
    parameter FRAC_WIDTH = 16;
    reg clk;
    reg rst_n;
    reg in_valid;
    reg signed [BIT_WIDTH-1:0] num_real;
    reg signed [BIT_WIDTH-1:0] num_imag;
    reg signed [BIT_WIDTH-1:0] den_real;
    reg signed [BIT_WIDTH-1:0] den_imag;

    wire out_valid;
    wire signed [31:0] out_real; 
    wire signed [31:0] out_imag; 

    // Instantiate UUT
    complex_divider_fsm #(
        .BIT_WIDTH(BIT_WIDTH),
        .FRAC_WIDTH(FRAC_WIDTH)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .num_real(num_real),
        .num_imag(num_imag),
        .den_real(den_real),
        .den_imag(den_imag),
        .out_valid(out_valid),
        .out_real(out_real),
        .out_imag(out_imag)
    );

    always #5 clk = ~clk;

    task drive_vector(
        input signed [BIT_WIDTH-1:0] nr,
        input signed [BIT_WIDTH-1:0] ni,
        input signed [BIT_WIDTH-1:0] dr,
        input signed [BIT_WIDTH-1:0] di
    );
        begin
            @(posedge clk);
            num_real = nr;
            num_imag = ni;
            den_real = dr;
            den_imag = di;
            in_valid = 1'b1;
            @(posedge clk);
            in_valid = 1'b0;
        end
    endtask

    initial begin
        clk = 0;
        rst_n = 0;
        in_valid = 0;
        num_real = 0; num_imag = 0; den_real = 0; den_imag = 0;

        #20;
        rst_n = 1;
        #20;

        // =====================================================================
        // WORST CASE 1: Full Negative Fractional Boundaries (-1.0 / -1.0)
        // Inputs: A, B, C, D = -1.0 (Hex: 16'sh8000)
        // Mathematically:
        //   (-1.0 - 1.0j) / (-1.0 - 1.0j) = 1.0 + 0.0j
        //
        // DESIRED WAVEFORM OUTPUTS (In Q16.16 Format):
        //   out_real = +1.000000  (Raw Signed Decimal: 65536, Hex: 32'h00010000)
        //   out_imag =  0.000000  (Raw Signed Decimal: 0,     Hex: 32'h00000000)
        // =====================================================================
        drive_vector(16'sh8000, 16'sh8000, 16'sh8000, 16'sh8000);
        @(posedge out_valid);
        #10;

        // =====================================================================
        // WORST CASE 2: Full Positive Fractional Boundaries (~0.99998)
        // Inputs: A, B, C, D = +0.99998 (Hex: 16'sh7FFF)
        // Mathematically: Should yield exactly unity division.
        //
        // DESIRED WAVEFORM OUTPUTS (In Q16.16 Format):
        //   out_real = +1.000000  (Raw Signed Decimal: 65536, Hex: 32'h00010000)
        //   out_imag =  0.000000  (Raw Signed Decimal: 0,     Hex: 32'h00000000)
        // =====================================================================
        drive_vector(16'sh7FFF, 16'sh7FFF, 16'sh7FFF, 16'sh7FFF);
        @(posedge out_valid);
        #10;

        // =====================================================================
        // WORST CASE 3: Smallest Possible Denominator (Forcing Max Gain/Output Scaling)
        // Inputs: A = -1.0 (16'sh8000), B = +0.99998 (16'sh7FFF)
        //         C = +1 LSB (16'sh0001), D = +1 LSB (16'sh0001) -> Tiny denominator close to 0
        // Mathematically: 
        //   den_sum = 1^2 + 1^2 = 2 (in raw integers)
        //   Splitting this by the denominator causes the quotient to scale up heavily.
        //
        // DESIRED WAVEFORM OUTPUTS (In Q16.16 Format):
        //   out_real = -0.500000  (Raw Signed Decimal: -32768, Hex: 32'hFFFF8000)
        //   out_imag = -32767.5   (Raw Signed Decimal: -2147450880, Hex: 32'h80008000)
        // =====================================================================
        drive_vector(16'sh8000, 16'sh7FFF, 16'sh0001, 16'sh0001);
        @(posedge out_valid);
        
        #50;
        $finish;
    end

endmodule