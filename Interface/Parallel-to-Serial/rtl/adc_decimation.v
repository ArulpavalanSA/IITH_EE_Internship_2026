module adc_decimation (
    input  wire          clk,         
    input  wire          rst,
    input  wire [191:0]  packet_in,
    input  wire          valid,
    input  wire          clk_1,
    output reg  [15:0]   sample_out,
    output reg           valid_out
    //output wire          ready
);

//wire clk_1; 

/*
clk_wiz_0 mul_six (
    .clk_in1  (clk),
    .reset    (rst),
    .clk_out1 (clk_1),
    .locked   (ready) 
);
*/
reg [191:0] packet_captured; 
reg         toggle = 1'b0; 
initial begin
    sample_out  <= 16'b0;
    valid_out   <= 1'b0;
end

always @(posedge clk) begin
    if (rst) begin
        packet_captured <= 192'b0;
        toggle          <= 1'b0;
    end
    else begin
        if(valid) begin
            packet_captured <= packet_in;
            toggle          <= ~toggle;
        end
        else begin
            packet_captured <= 0;
        end
    end
end

reg [1:0] toggle_sync = 0;

always @(posedge clk_1 or posedge rst) begin
    if (rst) begin
        toggle_sync <= 2'b0;
    end 
    else begin
        toggle_sync <= {toggle_sync[0], toggle};
    end
end

wire new_packet = (toggle_sync[0] != toggle_sync[1]);
reg update = 0;
reg [191:0] shift_store;
reg [2:0]   shift_count = 3'd6;

always @(posedge clk_1 or posedge rst) begin
    if (rst) begin
        shift_store <= 192'b0;
        sample_out  <= 16'b0;
        shift_count <= 3'd6;
    end
    else begin
        
        if (new_packet) begin
            update<=1;
        end
        else if (shift_count == 4'd7 && ~update) begin
            valid_out <= 0;
        end

        if (update && shift_count > 4'd5) begin
            sample_out  <= packet_captured[191:176];
            shift_store <= {packet_captured[164:0], 32'b0};
            shift_count <= 4'd1;
            update<=0;
            valid_out <= 1;
        end 
        else if (shift_count < 4'd7 && shift_count > 4'd0) begin
            sample_out  <= shift_store[191:176];
            shift_store <= {shift_store[164:0], 32'b0};
            shift_count <= shift_count + 1'b1;
        end    
    end
    
end

endmodule