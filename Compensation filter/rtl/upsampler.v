module upsampler #(
    parameter DATA_WIDTH = 16,
    parameter U_FACTOR   = 4
)(
    input clk,         
    input rst_n,      
    input signed [DATA_WIDTH-1:0] adc_data,    
    input adc_valid,
    
    output reg signed [DATA_WIDTH-1:0] up_data,
    output reg up_valid 
);

    // $clog2(4) = 2, which allows counting from 0 to 3.
    localparam COUNTER_WIDTH = (U_FACTOR > 1) ? $clog2(U_FACTOR) : 1;
    
    reg [COUNTER_WIDTH-1:0] sample_counter;
    reg                     is_upsampling;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            up_data        <= {DATA_WIDTH{1'b0}};
            up_valid       <= 1'b0;
            sample_counter <= 0;
            is_upsampling  <= 1'b0;
        end else begin
            if (adc_valid) begin
                up_data        <= adc_data;
                up_valid       <= 1'b1;
                sample_counter <= 1;
                
                if (U_FACTOR > 1) begin
                    is_upsampling <= 1'b1;
                end 
                else begin
                    is_upsampling <= 1'b0;
                end
            end
            
            else if (is_upsampling) begin
                up_data  <= {DATA_WIDTH{1'b0}};
                up_valid <= 1'b1;
                
                if (sample_counter == U_FACTOR - 1) begin
                    sample_counter <= 0;
                    is_upsampling  <= 1'b0;
                end 
                else begin
                    sample_counter <= sample_counter + 1;
                end
            end
            
            else begin
                up_data  <= {DATA_WIDTH{1'b0}};
                up_valid <= 1'b0;
            end
        end
    end

endmodule