`timescale 1ns / 1ps

module mwc_pre_processing_top #(
    parameter DATA_WIDTH        = 16,
    parameter COEFF_WIDTH       = 16,
    parameter HS_NUM_TAPS       = 4,
    parameter HC_NUM_TAPS       = 4,
    parameter DATA_FRAC_WIDTH   = 8,
    parameter COEFF_FRAC_WIDTH  = 8,
    parameter U_FACTOR          = 4,
    parameter D_FACTOR          = 4
)(
    input clk,         
    input rst_n,  
    input signed [DATA_WIDTH-1:0] adc_din,
    input adc_din_valid,
    input [HS_NUM_TAPS*COEFF_WIDTH-1:0] hs_coeff_vector,
    input [HC_NUM_TAPS*COEFF_WIDTH-1:0] hc_coeff_vector,
    
    output signed [DATA_WIDTH-1:0] clean_dout,
    output clean_dout_valid 
);

    wire signed [DATA_WIDTH-1:0] up_to_hs_data;
    wire                         up_to_hs_valid;
    
    wire signed [DATA_WIDTH-1:0] hs_to_hc_data;
    wire                         hs_to_hc_valid;
    
    wire signed [DATA_WIDTH-1:0] hc_to_down_data;
    wire                         hc_to_down_valid;

    upsampler #(
        .DATA_WIDTH(DATA_WIDTH),
        .U_FACTOR(U_FACTOR)
    ) upsampler_inst (
        .clk(clk),
        .rst_n(rst_n),
        .adc_data(adc_din),
        .adc_valid(adc_din_valid),
        .up_data(up_to_hs_data),
        .up_valid(up_to_hs_valid)
    );

    fir_filter #(
        .DATA_WIDTH(DATA_WIDTH),
        .COEFF_WIDTH(COEFF_WIDTH),
        .NUM_TAPS(HS_NUM_TAPS),
        .DATA_FRAC_WIDTH(DATA_FRAC_WIDTH),
        .COEFF_FRAC_WIDTH(COEFF_FRAC_WIDTH)
    ) sharp_lpf_inst (
        .clk(clk),
        .rst_n(rst_n),
        .din(up_to_hs_data),
        .din_valid(up_to_hs_valid),
        .coeff_vector(hs_coeff_vector),
        .dout(hs_to_hc_data),
        .dout_valid(hs_to_hc_valid)
    );

    fir_filter #(
        .DATA_WIDTH(DATA_WIDTH),
        .COEFF_WIDTH(COEFF_WIDTH),
        .NUM_TAPS(HC_NUM_TAPS),
        .DATA_FRAC_WIDTH(DATA_FRAC_WIDTH),
        .COEFF_FRAC_WIDTH(COEFF_FRAC_WIDTH)
    ) compensation_filter_inst (
        .clk(clk),
        .rst_n(rst_n),
        .din(hs_to_hc_data),
        .din_valid(hs_to_hc_valid),
        .coeff_vector(hc_coeff_vector),
        .dout(hc_to_down_data),
        .dout_valid(hc_to_down_valid)
    );

    downsampler #(
        .DATA_WIDTH(DATA_WIDTH),
        .D_FACTOR(D_FACTOR)
    ) downsampler_inst (
        .clk(clk),
        .rst_n(rst_n),
        .din(hc_to_down_data),
        .din_valid(hc_to_down_valid),
        .dout(clean_dout),
        .dout_valid(clean_dout_valid)
    );

endmodule