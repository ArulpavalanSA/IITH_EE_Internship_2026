/*
====================================================================================
# Author List      : Arulpavalan S A
# Filename         : Gradient_descent.v
# Target Hardware  : AMD Xilinx Zynq UltraScale+ RFSoC ZCU216
====================================================================================
# File Description :
# 
# * PURPOSE:
#   Hardware accelerator that uses an iterative Complex Gradient Descent algorithm 
#   to solve the overdetermined system [y = A * x] for a 1D complex column vector. 
#   It finds the optimal 1x1 complex scalar solution 'x' that minimizes system error.
#
# * CORE MATHEMATICS & STABILITY:
#   - Error Residual : r = y - A*x
#   - Step Direction : Gradient = A^H * r (Complex conjugate transpose of A multiplied by r)
#   - Step Size (alp): Dynamically calculated as [1 / ||A||^2] to guarantee mathematically 
#                      optimal, single-iteration convergence for a 1D column problem.
#   - Loop Update    : x(k+1) = x(k) + alpha * Gradient
#
# * HARDWARE IMPLEMENTATION FEATURES:
#   - Fully Parameterized: Customizable word length (bits=16) and fractional precision (FRAC=12).
#   - Memory Scalability : Block-based sequential processing (BLOCK_SIZE) balances hardware 
#                          resource usage against throughput performance for large sample sets.
#
====================================================================================
*/

module Gradient_descent #(
    parameter FRAC = 12,
    parameter sample = 32,
    parameter BLOCK_SIZE = 32,
    parameter bits = 16
)(
    input  wire          clk,
    input  wire          rst, 
    input  wire          start, 
    input  wire [(sample*bits-1):0]  y_vector,                    // 32 real samples * 16-bits = 512 bits
    input  wire [(sample*bits-1):0] A_column_rel,                    // 32 complex samples * 32-bits(16Re,16Im)=1023 bits
    input  wire [(sample*bits-1):0] A_column_iml,                    // 32 complex samples * 32-bits(16Re,16Im)=1023 bits
    
    output reg  [(2*bits-1):0]   x_out,         
    output reg           done  
);

    localparam LOG       = $clog2(sample);

    localparam SHIFT_PRODUCT  = FRAC; 
    localparam SHIFT_GRAD_ALPH = FRAC + 14;

    localparam IDLE           = 3'd0,
               COMPUTE_AX     = 3'd1,
               RESIDUAL       = 3'd2,
               CHECK_ERROR    = 3'd3,
               GRADIENT       = 3'd4,
               UPDATE_X       = 3'd5,
               DONE           = 3'd6,
               ACCUMULATE_Y_A = 3'd7; 

    reg [bits-1:0] alp;
    reg signed [2*bits-1:0] threshold=0;
    reg [2:0] state;

    wire signed [bits-1:0] y [0:(sample-1)];
    wire signed [bits-1:0] A_re [0:(sample-1)];
    wire signed [bits-1:0] A_im [0:(sample-1)];

    reg  signed [bits-1:0] x_re, x_im;
    reg  signed [bits+1:0] r_re [0:(sample-1)];
    reg  signed [bits+1:0] r_im [0:(sample-1)];

    genvar i;
    generate
        for(i = 0; i < sample; i = i + 1) begin: unpack_logic
            assign y[i]    = y_vector[(i*bits)+bits-1 : (i*bits)];          //Q4.12     ; Q(16-FRAC).FRAC
            assign A_re[i] = A_column_rel[(i*bits)+bits-1 : (i*bits)];
            assign A_im[i] = A_column_iml[(i*bits)+bits-1 : (i*bits)];
        end
    endgenerate

    wire signed [bits:0] ax_re [0:(sample-1)];
    wire signed [bits:0] ax_im [0:(sample-1)];
    
    generate
        for(i = 0; i < sample; i = i + 1) begin: ax_multipliers
            complex_multiplier #(
                .FRAC(FRAC)
            ) mult (
                .a_re(A_re[i]), .a_im(A_im[i]),
                .b_re(x_re),    .b_im(x_im),
                .p_re(ax_re[i]), .p_im(ax_im[i])                    //Q5.12            //Q(16-FRAC+1).FRAC Q9.8
            );
        end
    endgenerate

    reg signed [LOG+2*bits+2:0] total_grad_re;                    // Gradient 16+16+5=37 bits 
    reg signed [LOG+2*bits+2:0] total_grad_im;
    reg signed [LOG+2*bits+4:0] total_mse;                        // sum of 32 squared sample of each 16 bit can come up to 37 bit and adding real + img so 38 bit
    reg signed [LOG+2*bits+4:0] avg_y;
    
    wire signed [2*bits+4:0] next_x_re;
    wire signed [2*bits+4:0] next_x_im;

    assign next_x_re = $signed({{(SHIFT_PRODUCT+1){x_re[15]}}, x_re}) + (($signed({1'b0, alp}) * $signed({{SHIFT_GRAD_ALPH{total_grad_re[(LOG+2*bits+2)]}}, total_grad_re})) >>> SHIFT_GRAD_ALPH);     //Q16.12   g*alpha = 16+12
    assign next_x_im = $signed({{(SHIFT_PRODUCT+1){x_im[15]}}, x_im}) + (($signed({1'b0, alp}) * $signed({{SHIFT_GRAD_ALPH{total_grad_im[(LOG+2*bits+2)]}}, total_grad_im})) >>> SHIFT_GRAD_ALPH);     //Q

    wire signed [2*bits+4:0] check_re, check_im;
    integer idx;
    reg signed [LOG+2*bits+4:0] power;

    reg [LOG:0] base;

    assign check_re = (($signed({1'b0, alp}) * $signed({{SHIFT_GRAD_ALPH{total_grad_re[(LOG+2*bits+2)]}}, total_grad_re})) >>> SHIFT_GRAD_ALPH);
    assign check_im = (($signed({1'b0, alp}) * $signed({{SHIFT_GRAD_ALPH{total_grad_im[(LOG+2*bits+2)]}}, total_grad_im})) >>> SHIFT_GRAD_ALPH);

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            x_re          <= 16'sd0;
            x_im          <= 16'sd0;
            x_out         <= 32'd0;
            done          <= 1'b0;
        end 
        else begin
            case (state)
                
                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        x_re          <= 16'sd0;
                        x_im          <= 16'sd0;
                        avg_y = 0;
                        power = 0;
                        state <= ACCUMULATE_Y_A;
                        base <= 0;
                    end
                end

                ACCUMULATE_Y_A: begin
                    if(base < sample) begin
                        for (idx = 0; idx < BLOCK_SIZE; idx = idx + 1) begin
                            if (base + idx < sample) begin
                                avg_y = avg_y + (y[idx + base] * y[idx + base]);                          // log2(sample)=5; (16+16)+5 = 37 (Q13.24)  ;Q21.16
                                power = power + (A_re[idx + base] * A_re[idx + base] + A_im[idx + base] * A_im[idx + base]);    // Q4.12*Q4.12*5 +1 = Q14.24    :Q22.16
                            end
                        end
                        base <= base + BLOCK_SIZE;
                    end
                    else begin
                        threshold <= (avg_y) >>> 7;                                    //~2 orders ; 2^7=128 ; Q6.24    ;Q14.16
                        //count <= 0;
                        state <= COMPUTE_AX;
                        base <= 0;
                    end
                end

                COMPUTE_AX: begin
                    if ((power) == 0) begin                   // Q14.24 - 2*Q0.12 =Q14.0  ;Q22.16-2*Q0.8 = Q22.0
                        alp <= 16'h4000;                                                // Safeguard against division by zero
                    end 
                    else begin
                        alp <=  ($signed({1'b0,(64'd1 << ((2*SHIFT_PRODUCT) + 14))}))/ ((power));       //###Q2.14             
                    end                                                               //2^27=134217728 ;27=12+16
                    state      <= RESIDUAL;
                    base       <= 0;
                end

                RESIDUAL: begin
                    if(base < sample) begin
                        for (idx = 0; idx < BLOCK_SIZE; idx = idx + 1) begin
                            if (base + idx < sample) begin
                                r_re[idx + base] <= $signed(y[idx + base]) - $signed(ax_re[idx + base]);                   //Q4.12 - Q5.12 = Q6.12       //Q(16-FRAC).FRAC - Q(16-FRAC+1).FRAC = Q(18-FRAC).(FRAC) = Q10.8
                                r_im[idx + base] <= 17'sd0 - $signed(ax_im[idx + base]);                                   // y is real
                            end
                        end
                        base <= base + BLOCK_SIZE;                                                                             // Q(18-FRAC).(FRAC) * Q(18-FRAC).(FRAC) * 5 *2 = Q(42-2*FRAC).(2*FRAC)
                    end  
                    else begin
                        state <= CHECK_ERROR;
                        total_mse = 0;
                        base <= 0;                                                                                             // Q26.16
                    end
                end

                CHECK_ERROR: begin
                    if(base < sample) begin
                        for (idx = 0; idx < BLOCK_SIZE; idx = idx + 1) begin
                            if (base + idx < sample) begin
                                total_mse = total_mse + (r_re[idx + base] * r_re[idx + base]) + (r_im[idx + base] * r_im[idx + base]);          // 5+(18+18)+1=42   (Q6.12 * Q6.12 *5 = Q18.24)
                            end
                        end
                        base <= base + BLOCK_SIZE;                                                                                        // Q(18-FRAC).(FRAC) * Q(18-FRAC).(FRAC) * 5 *2 = Q(42-2*FRAC).(2*FRAC)
                    end  
                    else begin  
                        base <= 0;                                                                                             // Q26.16
                        if ((total_mse) < threshold) begin
                            state <= DONE;
                        end 
                        else begin
                            state <= GRADIENT;
                        end
                        total_grad_re = 0;
                        total_grad_im = 0;
                    end
                end

                GRADIENT: begin
                    if(base < sample) begin
                        for (idx = 0; idx < BLOCK_SIZE; idx = idx + 1) begin
                            if (base + idx < sample) begin
                                total_grad_re = total_grad_re + (A_re[idx + base] * r_re[idx + base] + A_im[idx + base] * r_im[idx + base]);        // Q4.12*Q6.12 + Q4.12*Q6.12 *5 = Q16.24
                                total_grad_im = total_grad_im + ( A_re[idx + base] * r_im[idx + base] - A_im[idx + base] * r_re[idx + base] );      // ##Q8.8*Q10.8 - Q8.8*Q10.8 *5 = Q24.16
                            end
                        end
                        base <= base + BLOCK_SIZE;                                                                                        // Q(18-FRAC).(FRAC) * Q(18-FRAC).(FRAC) * 5 *2 = Q(42-2*FRAC).(2*FRAC)
                    end
                    else begin
                        state <= UPDATE_X;
                        base <= 0;                                                                                            
                    end 
                end


                UPDATE_X: begin
                    
                    if ((next_x_re[bits-1] == 1'b0) && (next_x_re[2*bits+4:bits-1] != 22'b0))             x_re <= 16'sh7FFF;
                    else if ((next_x_re[bits-1] == 1'b1) && (next_x_re[2*bits+4:bits-1] != {22{1'b1}}))   x_re <= 16'sh8000; 
                    else                                                                    x_re <= next_x_re[bits-1:0]; 

                    if ((next_x_im[bits-1] == 1'b0) && (next_x_im[2*bits+4:bits-1] != 22'b0))             x_im <= 16'sh7FFF;
                    else if ((next_x_im[bits-1] == 1'b1) && (next_x_im[2*bits+4:bits-1] != {22{1'b1}}))   x_im <= 16'sh8000;
                    else                                                                    x_im <= next_x_im[bits-1:0];

                    if((x_re == next_x_re[bits-1:0]) && (x_im == next_x_im[bits-1:0]))
                        state <= DONE;     
                    else
                        state <= COMPUTE_AX;     

                end

                DONE: begin
                    x_out <= {x_re, x_im};
                    done  <= 1'b1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule