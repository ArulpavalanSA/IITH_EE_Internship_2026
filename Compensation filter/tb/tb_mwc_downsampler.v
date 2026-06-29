`timescale 1ns / 1ps

module tb_mwc_downsampler;

    parameter DATA_WIDTH = 16;
    parameter D_FACTOR   = 4;
    parameter CLK_PERIOD = 10;

    reg                         clk;
    reg                         rst_n;
    reg  signed [DATA_WIDTH-1:0] din;
    reg                         din_valid;

    wire signed [DATA_WIDTH-1:0] dout;
    wire                        dout_valid;

    downsampler #(
        .DATA_WIDTH(DATA_WIDTH),
        .D_FACTOR(D_FACTOR)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .din(din),
        .din_valid(din_valid),
        .dout(dout),
        .dout_valid(dout_valid)
    );

    always begin
        clk = 1'b0; #(CLK_PERIOD/2);
        clk = 1'b1; #(CLK_PERIOD/2);
    end

    initial begin
        rst_n     = 1'b0;
        din       = 0;
        din_valid = 1'b0;
        
        #(CLK_PERIOD * 4);
        @(posedge clk);
        rst_n = 1'b1;
        #(CLK_PERIOD * 2);

        $display("[TB] Reset complete. Simulating stream from FIR filters...");

        // Stream 8 consecutive valid elements: 10, 20, 30, 40, 50, 60, 70, 80
        // Expected outputs for D=4: 10 (at counter=0), then 50 (at counter=4)
        send_data(16'd10);
        send_data(16'd20);
        send_data(16'd30);
        send_data(16'd40);
        send_data(16'd50);
        send_data(16'd60);
        send_data(16'd70);
        send_data(16'd80);

        // Simulate a pipeline gap/stall where valid is dropped
        @(posedge clk);
        din_valid = 1'b0;
        din       = 16'd0;
        #(CLK_PERIOD * 3);

        // Send two more packets
        send_data(16'd90);
        send_data(16'd100);

        #(CLK_PERIOD * 10);
        $display("[TB] Downsampler verification complete.");
        $finish;
    end

    task send_data(input signed [DATA_WIDTH-1:0] value);
        begin
            @ (posedge clk);
            din       = value;
            din_valid = 1'b1;
        end
    endtask

endmodule