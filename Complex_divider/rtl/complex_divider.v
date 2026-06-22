/*
# Author          : Arulpavalan S A
# Filename        : complex_divider_fsm.v
# File Description: 
#   - Implements a parameterized, sequential Complex Number Divider FSM.
#   - Computation: (num_real + j*num_imag) / (den_real + j*den_imag)
#   - Inputs: Dynamically handles any 16-bit signed format (e.g., Q16.0, Q8.8, Q0.16) via 'FRAC_WIDTH'.
#   - Outputs: Hardcoded to a fixed, 32-bit Q16.16 signed format.
#
# Features:
#   Fixed-Point Scaling: Arithmetically shifts numerators left by 16 bits before division, 
#      forcing the output quotient to cleanly land on a Q16.16 alignment.
#   Safety & Constraints:
#      - Output limits are bounded by the Q16.16 format (-32768.0 to +32767.9999).
#      - Div by Zero Protection: Safely clamps both output channels to 0 if the denominator is 0.
#      - Handshake & Latency: Employs standard 'in_valid'/'out_valid' flags; execution takes 4 cycles.
*/

module complex_divider_fsm #(
    parameter BIT_WIDTH  = 16, 
    parameter FRAC_WIDTH = 8   
)(
    input wire clk,
    input wire rst_n,
    input wire in_valid,
    
    input wire signed [BIT_WIDTH-1:0] num_real, // A
    input wire signed [BIT_WIDTH-1:0] num_imag, // B
    input wire signed [BIT_WIDTH-1:0] den_real, // C
    input wire signed [BIT_WIDTH-1:0] den_imag, // D
    
    output reg out_valid,
    output reg signed [2*BIT_WIDTH-1:0] out_real, // X
    output reg signed [2*BIT_WIDTH-1:0] out_imag  // Y

);

    localparam [2:0] IDLE       = 3'd0,
                     MULTIPLY   = 3'd1,
                     CALC_SUM   = 3'd2,
                     DIVIDE     = 3'd3;

    reg [2:0] state;

    reg signed [BIT_WIDTH-1:0] a, b, c, d;                                  //Q8.8
    reg signed [(2*BIT_WIDTH)-1:0] prod_ac, prod_bd, prod_bc, prod_ad;      //16.16  
    reg signed [(2*BIT_WIDTH)-1:0] prod_cc, prod_dd;                        //Q8.8

    reg signed [63:0] num_sum_real;
    reg signed [63:0] num_sum_imag;
    reg signed [63:0] den_sum;

    reg signed [63:0] num_shifted_real;
    reg signed [63:0] num_shifted_imag;
    
    reg signed [63:0] div_res_real;
    reg signed [63:0] div_res_imag;

    localparam SHIFT_VAL = 16;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            a            <= 0;
            b            <= 0;
            c            <= 0;
            d            <= 0;
            prod_ac      <= 0;
            prod_bd      <= 0;
            prod_bc      <= 0;
            prod_ad      <= 0;
            prod_cc      <= 0;
            prod_dd      <= 0;
            num_sum_real <= 0;
            num_sum_imag <= 0;
            den_sum      <= 0;
            out_real     <= 0;
            out_imag     <= 0;
            out_valid    <= 0;
        end 
        else begin
            case(state)
                IDLE: begin
                    out_valid <= 0;
                    if (in_valid) begin
                        a     <= num_real;      //q8.8
                        b     <= num_imag;
                        c     <= den_real;
                        d     <= den_imag;
                        state <= MULTIPLY; 
                    end
                end
                
                MULTIPLY: begin
                    prod_ac <= a * c;           // q8.8 * q8.8 = q16.16
                    prod_bd <= b * d;
                    prod_bc <= b * c;
                    prod_ad <= a * d;
                    prod_cc <= c * c;
                    prod_dd <= d * d;
                    state   <= CALC_SUM;
                end
                
                CALC_SUM: begin
                    num_sum_real <= $signed({{32{prod_ac[(2*BIT_WIDTH)-1]}}, prod_ac}) + $signed({{32{prod_bd[(2*BIT_WIDTH)-1]}}, prod_bd});
                    num_sum_imag <= $signed({{32{prod_bc[(2*BIT_WIDTH)-1]}}, prod_bc}) - $signed({{32{prod_ad[(2*BIT_WIDTH)-1]}}, prod_ad});
                    den_sum      <= $signed({{32{prod_cc[(2*BIT_WIDTH)-1]}}, prod_cc}) + $signed({{32{prod_dd[(2*BIT_WIDTH)-1]}}, prod_dd});
                    state        <= DIVIDE;
                end
                
                DIVIDE: begin
                    if (den_sum != 0) begin

                        num_shifted_real = num_sum_real <<< SHIFT_VAL;
                        num_shifted_imag = num_sum_imag <<< SHIFT_VAL;

                        div_res_real = num_shifted_real / den_sum;
                        div_res_imag = num_shifted_imag / den_sum;

                        out_real <= div_res_real[31:0];
                        out_imag <= div_res_imag[31:0];
                    end 
                    else begin
                        out_real <= 0;
                        out_imag <= 0;
                    end
                    state <= IDLE;
                    out_valid <= 1'b1;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule