`timescale 1ns / 1ps

module tb_dac;

    reg          clk;
    reg          rst;
    reg          valid =1;
    reg [2047:0] samples;
    wire [255:0] dac_data_out;

    dac_packetizer uut (
        .clk(clk),
        .rst(rst),
        .valid(valid),
        .samples(samples),
        .dac_data_out(dac_data_out)
    );

    always begin
        #10 clk = ~clk;
    end

    initial begin
        clk     = 0;
        rst     = 1;  

       
        samples[255:0]    = {64{4'ha}};  
        samples[511:256]  = {64{4'hb}};  
        samples[767:512]  = {64{4'hc}}; 
        samples[1023:768] = {64{4'hd}};
        samples[1279:1024]= {64{4'he}};
        samples[1535:1280]= {64{4'hf}};
        samples[1791:1536]= {64{4'h1}};
        samples[2047:1792]= {64{4'h2}};
                
        
        @(negedge clk);
        rst = 0;
        
        repeat (24) @(posedge clk);
        
        valid = 0;
        samples[255:0]    = {32{8'ha0}};  
        samples[511:256]  = {32{8'hb1}};  
        samples[767:512]  = {32{8'hc2}}; 
        samples[1023:768] = {32{8'hd3}};
        samples[1279:1024]= {32{8'he4}};
        samples[1535:1280]= {32{8'hf5}};
        samples[1791:1536]= {32{8'h16}};
        samples[2047:1792]= {32{8'h27}};
       
        repeat (50) @(posedge clk);

        $display("[TB] Simulation complete.");
        $finish;
    end

    initial begin
        $monitor("Time = %0t | rst = %b | Count = %d | DAC Out = 0x%h", 
                 $time, rst, uut.count, dac_data_out[31:0]);
    end

endmodule