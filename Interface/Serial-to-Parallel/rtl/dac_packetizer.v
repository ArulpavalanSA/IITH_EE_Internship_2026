module dac_packetizer (
    input  wire          clk,               //fs/16
    input  wire          rst,
    input  wire          valid,
    input  wire [2047:0] samples,           //128 *16
    output reg  [255:0]  dac_data_out       //16 * 16
);

reg [2:0] count = 0;

always @(posedge clk) begin
    if(rst|~valid) begin
        count <= 0;
        dac_data_out <= 0;
    end 
    else begin
        count <= count + 1;
        case (count)
            0: dac_data_out <= samples[255:0];
            1: dac_data_out <= samples[511:256];
            2: dac_data_out <= samples[767:512];
            3: dac_data_out <= samples[1023:768];
            4: dac_data_out <= samples[1279:1024];
            5: dac_data_out <= samples[1535:1280];
            6: dac_data_out <= samples[1791:1536];
            7: dac_data_out <= samples[2047:1792];
            default: dac_data_out <= 0;
        endcase
    end

end

endmodule