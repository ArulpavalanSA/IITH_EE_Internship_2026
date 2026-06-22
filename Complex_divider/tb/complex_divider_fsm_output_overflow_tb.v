`timescale 1ns / 1ps

module complex_divider_fsm_output_overflow_tb;

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
    complex_divider_fsm #(.BIT_WIDTH(BIT_WIDTH), .FRAC_WIDTH(FRAC_WIDTH)) uut (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid),
        .num_real(num_real), .num_imag(num_imag), .den_real(den_real), .den_imag(den_imag),
        .out_valid(out_valid), .out_real(out_real), .out_imag(out_imag)
    );

    always #5 clk = ~clk;

    task drive_vector(
        input signed [BIT_WIDTH-1:0] nr, input signed [BIT_WIDTH-1:0] ni,
        input signed [BIT_WIDTH-1:0] dr, input signed [BIT_WIDTH-1:0] di
    );
        begin
            @(posedge clk);
            num_real = nr; num_imag = ni; den_real = dr; den_imag = di;
            in_valid = 1'b1;
            @(posedge clk);
            in_valid = 1'b0;
        end
    endtask

    initial begin
        clk = 0; rst_n = 0; in_valid = 0;
        num_real = 0; num_imag = 0; den_real = 0; den_imag = 0;
        #20; rst_n = 1; #20;

        // =====================================================================
        // CRITICAL OVERFLOW TEST CASE: Large Numerator / Extremely Small Denominator
        // Inputs in Q0.16:
        //   A = +0.99998 (16'sh7FFF), B = 0
        //   C = +0.000015 (16'sh0001) [Only 1 LSB!], D = 0
        //
        // Mathematically: 
        //   Real Quotient = 32767 / 1 = 32,767.0 
        //   This perfectly fits within a Q16.16 max range (+32767.9999).
        // =====================================================================
        drive_vector(16'sh7FFF, 16'sh0000, 16'sh0001, 16'sh0000);
        @(posedge out_valid);
        #10;

        // =====================================================================
        // CRITICAL OVERFLOW TEST CASE: Pushing beyond the Q16.16 boundary
        // Inputs in Q0.16:
        //   A = +0.99998 (16'sh7FFF), B = +0.99998 (16'sh7FFF)
        //   C = +0.000015 (16'sh0001), D = 0
        //
        // Mathematically:
        //   num_sum_real = (32767 * 1) + (32767 * 0) = 32,767
        //   den_sum      = (1 * 1) + (0 * 0) = 1
        //   But remember, we shift left by 16 bits!
        //   The true quotient value needed is around +65,534.0
        //
        // DESIRED WAVEFORM OUTPUTS:
        //   Since +65,534 requires a minimum of 17 integer bits, the 16-bit integer 
        //   portion of out_real will completely wrap around into a negative number 
        //   or truncate down to a garbage value on your waveform window.
        // =====================================================================
        drive_vector(16'sh7FFF, 16'sh7FFF, 16'sh0001, 16'sh0000);
        @(posedge out_valid);

        #50;
        $finish;
    end

endmodule