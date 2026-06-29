`timescale 1ns / 1ps

module tb_fir_filter;

    parameter DATA_WIDTH       = 16;
    parameter COEFF_WIDTH      = 16;
    parameter NUM_TAPS         = 4;
    parameter DATA_FRAC_WIDTH  = 8;
    parameter COEFF_FRAC_WIDTH = 8;
    parameter CLK_PERIOD       = 10;

    reg                         clk;
    reg                         rst_n;
    reg  signed [DATA_WIDTH-1:0] din;
    reg                         din_valid;
    reg  [NUM_TAPS*COEFF_WIDTH-1:0] coeff_vector;

    wire signed [DATA_WIDTH-1:0] dout;
    wire                        dout_valid;

    // Instantiate UUT
    fir_filter #(
        .DATA_WIDTH(DATA_WIDTH),
        .COEFF_WIDTH(COEFF_WIDTH),
        .NUM_TAPS(NUM_TAPS),
        .DATA_FRAC_WIDTH(DATA_FRAC_WIDTH),
        .COEFF_FRAC_WIDTH(COEFF_FRAC_WIDTH)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .din(din),
        .din_valid(din_valid),
        .coeff_vector(coeff_vector),
        .dout(dout),
        .dout_valid(dout_valid)
    );

    // Clock Generator
    always begin
        clk = 1'b0; #(CLK_PERIOD/2);
        clk = 1'b1; #(CLK_PERIOD/2);
    end

    initial begin
        // Set up coefficients: 4 taps of 0.25 in Q8.8 format -> 0.25 * 256 = 64 = 16'h0040
        // Vector arrangement: [ h[3], h[2], h[1], h[0] ]
        coeff_vector = {16'h0040, 16'h0040, 16'h0040, 16'h0040};
        
        rst_n     = 1'b0;
        din       = 0;
        din_valid = 1'b0;
        
        #(CLK_PERIOD * 5);
        @(posedge clk);
        rst_n = 1'b1;
        #(CLK_PERIOD * 2);

        $display("[TB] Starting FIR Filter Verification...");

        // Send Step Input: Steady DC signal of 4.0. In Q8.8, 4.0 * 256 = 1024 (16'h0400)
        // With coefficients of [0.25, 0.25, 0.25, 0.25], the moving output should steady at 4.0
        send_sample(16'h0400);
        send_sample(16'h0400);
        send_sample(16'h0400);
        send_sample(16'h0400);
        
        // Return to 0
        send_sample(16'h0000);
        send_sample(16'h0000);
        send_sample(16'h0000);
        send_sample(16'h0000);

        #(CLK_PERIOD * 10);
        $display("[TB] Simulation Completed.");
        $finish;
    end

    // Task to pulse data cleanly
    task send_sample(input signed [DATA_WIDTH-1:0] sample_val);
        begin
            @(posedge clk);
            din       = sample_val;
            din_valid = 1'b1;
            @(posedge clk);
            din_valid = 1'b0;
            din       = 0;
            #(CLK_PERIOD); // Add space between steps to watch pipeline latency clearly
        end
    endtask


endmodule