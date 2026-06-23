`timescale 1ns / 1ps

module tb;

    reg          clk;
    reg          rst;
    reg  [191:0] packet_in;
    wire [15:0]  sample_out;
    reg          valid=1;
    //wire         ready;
    reg         clk_1;
    wire         valid_out;
    adc_decimation uut (
        .clk(clk),
        .rst(rst),
        .packet_in(packet_in),
        .valid(valid),
        .clk_1(clk_1),
        .sample_out(sample_out),
        .valid_out(valid_out)
        //.ready(ready)
    );
    always begin
        #6.1035 clk = ~clk;
    end
    
    always begin
        #1.01725 clk_1 = ~clk_1;
    end


/*    
    reg clk_fast_sim;
    always begin
        #1.01725 clk_fast_sim = ~clk_fast_sim;
    end

    assign uut.clk_1 = clk_fast_sim;
*/
    initial begin
        clk = 1'b0;
        clk_1 = 1'b0;
        //clk_fast_sim = 1'b0;
        rst = 1'b1;
        packet_in = 192'b0;
        //ready = 1'b1;
        #5;
        @(posedge clk);
        rst = 1'b0;
        
        //@(posedge ready);
                
        @(posedge clk);
        packet_in = {
            16'hAAAA, 16'hBBBB, 16'hCCCC, 16'hDDDD,
            16'hEEEE, 16'hFFFF, 16'h9999, 16'h8888,
            16'h7777, 16'h5555, 16'h1111, 16'h2222
        };

        //@(posedge clk);
        //packet_in = 192'h0; 
        //#100;

        @(posedge clk);
        packet_in = {
            16'h1234, 16'h5678, 16'h9ABC, 16'hDEF0,
            16'h1111, 16'h2222, 16'h3333, 16'h4444,
            16'h5555, 16'h6666, 16'h7777, 16'h8888
        };
        
        @(posedge clk);
        packet_in = 192'h0;
        
        @(posedge clk);
        packet_in = {
            16'hAAAA, 16'hBBBB, 16'hCCCC, 16'hDDDD,
            16'hEEEE, 16'hFFFF, 16'h9999, 16'h8888,
            16'h7777, 16'h5555, 16'h1111, 16'h2222
        };

        #30;

        @(posedge clk);
        valid = 1'b0;
        #30;

        @(posedge clk);
        packet_in = {
            16'hAAAA, 16'hBBBB, 16'hCCCC, 16'hDDDD,
            16'hEEEE, 16'hFFFF, 16'h9999, 16'h8888,
            16'h7777, 16'h5555, 16'h1111, 16'h2222
        };
        valid = 1'b1;

        #30

        $display("Simulation Finished Successfully.");
        $finish;
    end

endmodule