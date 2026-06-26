`timescale 1ns / 1ps

module complex_multiplier #(
    parameter FRAC = 12
)(
    input  signed [15:0] a_re, a_im,
    input  signed [15:0] b_re, b_im,
    output signed [16:0] p_re, p_im
);
    wire signed [31:0] re_mult1 = a_re * b_re;
    wire signed [31:0] re_mult2 = a_im * b_im;
    wire signed [31:0] im_mult1 = a_re * b_im;
    wire signed [31:0] im_mult2 = a_im * b_re;

    assign p_re = (re_mult1 - re_mult2) >>> FRAC;
    assign p_im = (im_mult1 + im_mult2) >>> FRAC;         //Q5.12
endmodule