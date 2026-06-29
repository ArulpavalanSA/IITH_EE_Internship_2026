`timescale 1ns / 1ps

module tb_mwc_upsampler;

    parameter DATA_WIDTH = 16;
    parameter U_FACTOR   = 4;
    parameter CLK_PERIOD = 10; // Fast master clock period = 10ns (100 MHz)

    reg                      clk;
    reg                      rst_n;
    reg  signed [DATA_WIDTH-1:0] adc_data;
    reg                      adc_valid;

    wire signed [DATA_WIDTH-1:0] up_data;
    wire                     up_valid;

    mwc_upsampler #(
        .DATA_WIDTH(DATA_WIDTH),
        .U_FACTOR(U_FACTOR)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .adc_data(adc_data),
        .adc_valid(adc_valid),
        .up_data(up_data),
        .up_valid(up_valid)
    );

    always begin
        clk = 1'b0;
        #(CLK_PERIOD/2);
        clk = 1'b1;
        #(CLK_PERIOD/2);
    end

    initial begin
        rst_n     = 1'b0;
        adc_data  = {DATA_WIDTH{1'b0}};
        adc_valid = 1'b0;

        #(CLK_PERIOD * 4);
        @(posedge clk);
        rst_n = 1'b1;
        #(CLK_PERIOD * 2);
        
        $display("[TB INFO] Reset released. Beginning Upsampler simulation sequence...");

        // --- TEST CASE 1: Feed Sample Value = 105 ---
        @(posedge clk);
        adc_data  = 16'd105;   // Present a valid data word
        adc_valid = 1'b1;      // Assert strobe line
        
        @(posedge clk);
        adc_valid = 1'b0;      // Immediately drop the strobe on the next edge
        adc_data  = 16'd0;     // Clear input bus data
        
        // Wait for U_FACTOR cycles to let the internal engine finish zero-stuffing
        #(CLK_PERIOD * U_FACTOR);

        // --- TEST CASE 2: Feed Sample Value = -250 ---
        @(posedge clk);
        adc_data  = -16'd250;  // Signed negative value test
        adc_valid = 1'b1;
        
        @(posedge clk);
        adc_valid = 1'b0;
        adc_data  = 16'd0;
        
        #(CLK_PERIOD * U_FACTOR);

        // --- TEST CASE 3: Consecutive/Back-to-Back Fast Arrival Handling ---
        // Simulates what happens if the ADC provides samples as fast as permitted by U
        @(posedge clk);
        adc_data  = 16'd77;
        adc_valid = 1'b1;
        @(posedge clk);
        adc_valid = 1'b0;
        
        #(CLK_PERIOD * (U_FACTOR - 1)); // Wait exactly up to the last stuffed zero edge

        @(posedge clk);
        adc_data  = 16'd88;
        adc_valid = 1'b1;
        @(posedge clk);
        adc_valid = 1'b0;

        #(CLK_PERIOD * U_FACTOR * 2);

        $display("[TB INFO] Simulation finished successfully.");
        $finish;
    end

    initial begin
        $timeformat(-9, 1, " ns", 9);
        // Wait for reset release
        @(posedge rst_n);
        forever begin
            @(posedge clk);
            if (up_valid) begin
                $display("Time: %0t | Out Data = %d | Out Valid = %b", $time, up_data, up_valid);
            end
        end
    end

endmodule