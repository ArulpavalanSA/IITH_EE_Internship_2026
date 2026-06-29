module downsampler #(
    parameter DATA_WIDTH = 16, 
    parameter D_FACTOR   = 4
)(
    input clk,
    input rst_n, 
    input signed [DATA_WIDTH-1:0] din,
    input din_valid,  

    output reg signed [DATA_WIDTH-1:0] dout,
    output reg dout_valid  
);

    localparam COUNTER_WIDTH = (D_FACTOR > 1) ? $clog2(D_FACTOR) : 1;
    reg [COUNTER_WIDTH-1:0] sample_counter;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dout           <= {DATA_WIDTH{1'b0}};
            dout_valid     <= 1'b0;
            sample_counter <= 0;
        end 
        else begin
            if (din_valid) begin
                if (sample_counter == 0) begin
                    dout       <= din;
                    dout_valid <= 1'b1;
                    if (D_FACTOR > 1) begin
                        sample_counter <= sample_counter + 1;
                    end
                end 
                else begin
                    dout_valid <= 1'b0;

                    if (sample_counter == D_FACTOR - 1) begin
                        sample_counter <= 0; // Reset counter window
                    end 
                    else begin
                        sample_counter <= sample_counter + 1;
                    end
                end
            end 
            else begin
                dout_valid <= 1'b0;
            end
        end
    end

endmodule