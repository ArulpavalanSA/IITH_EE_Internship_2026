`timescale 1ns / 1ps

module complex_divider_fsm_q16_tb;
    parameter BIT_WIDTH  = 16;
    parameter FRAC_WIDTH = 0; 

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
        // WORST CASE 1: Absolute Maximum Negative Limits (Sign-Flip & Expansion Check)
        // Inputs: A, B, C, D = -32768 (16'sh8000)
        // Mathematically:
        //   num_sum_real = (-32768 * -32768) + (-32768 * -32768) = 2,147,483,648
        //   num_sum_imag = (-32768 * -32768) - (-32768 * -32768) = 0
        //   den_sum      = (-32768 * -32768) + (-32768 * -32768) = 2,147,483,648 (Overflown in 32-bit!)
        //
        // DESIRED WAVEFORM OUTPUTS (In Q16.16 Format):
        //   out_real = +1.000000  (Raw Signed Decimal: 65536, Hex: 32'h00010000)
        //   out_imag =  0.000000  (Raw Signed Decimal: 0,     Hex: 32'h00000000)
        // =====================================================================
        drive_vector(16'sh8000, 16'sh8000, 16'sh8000, 16'sh8000);
        @(posedge out_valid);
        #10;

        // =====================================================================
        // WORST CASE 2: Absolute Maximum Positive Limits (Saturation Check)
        // Inputs: A, B, C, D = +32767 (16'sh7FFF)
        // Mathematically:
        //   num_sum_real = (32767 * 32767) + (32767 * 32767) = 2,147,352,578
        //   num_sum_imag = (32767 * 32767) - (32767 * 32767) = 0
        //   den_sum      = (32767 * 32767) + (32767 * 32767) = 2,147,352,578
        //
        // DESIRED WAVEFORM OUTPUTS (In Q16.16 Format):
        //   out_real = +1.000000  (Raw Signed Decimal: 65536, Hex: 32'h00010000)
        //   out_imag =  0.000000  (Raw Signed Decimal: 0,     Hex: 32'h00000000)
        // =====================================================================
        drive_vector(16'sh7FFF, 16'sh7FFF, 16'sh7FFF, 16'sh7FFF);
        @(posedge out_valid);
        #10;

        // =====================================================================
        // WORST CASE 3: Mixed Signs Maximum Magnitude 
        // Inputs: A = +32767, B = -32768, C = -32768, D = +32767
        // Mathematically:
        //   num_sum_real = (32767 * -32768) + (-32768 * 32767) = -2,147,450,880
        //   num_sum_imag = (-32768 * -32768) - (32767 * 32767) = 32,767
        //   den_sum      = (-32768 * -32768) + (32767 * 32767) = 2,147,450,873
        //
        // DESIRED WAVEFORM OUTPUTS (In Q16.16 Format):
        //   out_real = -1.000000  (Raw Signed Decimal: -65536, Hex: 32'hFFFF0000)
        //   out_imag = +0.000015  (Raw Signed Decimal: 1,      Hex: 32'h00000001)
        // =====================================================================
        drive_vector(16'sh7FFF, 16'sh8000, 16'sh8000, 16'sh7FFF);
        @(posedge out_valid);
        
        #50;
        $finish;
    end

endmodule