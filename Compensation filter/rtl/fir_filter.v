`timescale 1ns / 1ps

module fir_filter #(
    parameter DATA_WIDTH        = 16,
    parameter COEFF_WIDTH       = 16,
    parameter NUM_TAPS          = 4,
    parameter DATA_FRAC_WIDTH   = 8,
    parameter COEFF_FRAC_WIDTH  = 8
)(
    input clk,
    input rst_n,
    input signed [DATA_WIDTH-1:0] din,              //Q8.8   ;Q(DATA_WIDTH - DATA_FRAC_WIDTH).DATA_FRAC_WIDTH
    input din_valid,      
    input [NUM_TAPS*COEFF_WIDTH-1:0] coeff_vector,  //Q8.8   ;Q(COEFF_WIDTH - COEFF_FRAC_WIDTH).COEFF_FRAC_WIDTH
    
    output reg signed [DATA_WIDTH-1:0] dout,        //Q8.8  ;;Q(DATA_WIDTH - DATA_FRAC_WIDTH).DATA_FRAC_WIDTH
    output reg dout_valid  
);

    wire signed [COEFF_WIDTH-1:0] h [0:NUM_TAPS-1];     
    genvar i;
    generate
        for (i = 0; i < NUM_TAPS; i = i + 1) begin : unpack_coeffs
            assign h[i] = coeff_vector[(i+1)*COEFF_WIDTH-1 -: COEFF_WIDTH];
        end
    endgenerate

    reg signed [DATA_WIDTH-1:0] delay_pipeline [0:NUM_TAPS-1];
    integer j;
    
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (j = 0; j < NUM_TAPS; j = j + 1) begin
                delay_pipeline[j] <= {DATA_WIDTH{1'b0}};
            end
        end 
        else if (din_valid) begin
            delay_pipeline[0] <= din;
            for (j = 1; j < NUM_TAPS; j = j + 1) begin
                delay_pipeline[j] <= delay_pipeline[j-1];
            end
        end
    end

    localparam PROD_WIDTH = DATA_WIDTH + COEFF_WIDTH;
    reg signed [PROD_WIDTH-1:0] products [0:NUM_TAPS-1];     
    integer k;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (k = 0; k < NUM_TAPS; k = k + 1) begin
                products[k] <= {PROD_WIDTH{1'b0}};
            end
        end 
        else if (din_valid) begin
            products[0] <= din * h[0];        
            for (k = 1; k < NUM_TAPS; k = k + 1) begin
                products[k] <= delay_pipeline[k-1] * h[k];        //Q(DATA_WIDTH - DATA_FRAC_WIDTH + COEFF_WIDTH - COEFF_FRAC_WIDTH).(DATA_FRAC_WIDTH + COEFF_FRAC_WIDTH)
            end
        end
    end

    localparam ACC_WIDTH = PROD_WIDTH + $clog2(NUM_TAPS);
    reg signed [ACC_WIDTH-1:0] accumulator;                 //Q24.16  ;Q(ACC_WIDTH - (DATA_FRAC_WIDTH + COEFF_FRAC_WIDTH)).(DATA_FRAC_WIDTH + COEFF_FRAC_WIDTH)
    reg                        pipe_valid_1;
    reg                        pipe_valid_2;
    integer m;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accumulator  <= {ACC_WIDTH{1'b0}};
            pipe_valid_1 <= 1'b0;
            pipe_valid_2 <= 1'b0;
            dout         <= {DATA_WIDTH{1'b0}};
            dout_valid   <= 1'b0;
        end 
        else begin
            pipe_valid_1 <= din_valid;
            pipe_valid_2 <= pipe_valid_1;
            
            if (pipe_valid_1) begin
                accumulator = products[0];
                for (m = 1; m < NUM_TAPS; m = m + 1) begin
                    accumulator = accumulator + products[m];       
                end
            end
            
            if (pipe_valid_2) begin
                dout       <= accumulator >>> (COEFF_FRAC_WIDTH);
                dout_valid <= 1'b1;
            end 
            else begin
                dout_valid <= 1'b0;
            end
        end
    end

endmodule