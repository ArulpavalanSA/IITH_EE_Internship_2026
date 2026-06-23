/*
====================================================================================
# Author List      : Arulpavalan S A
# Filename         : Gradient_descent_2.v
# Target Hardware  : AMD Xilinx Zynq UltraScale+ RFSoC ZCU216
====================================================================================
# File Description :
# 
# * PURPOSE:
#   Hardware accelerator extending the 1D solver to handle a 2-element complex weight 
#   vector [x1, x2]. It iteratively solves the overdetermined system [y = A1*x1 + A2*x2] 
#   by minimizing the Mean Squared Error (MSE) across parallel complex data paths.
#
# * CORE MATHEMATICS & MULTI-CHANNEL CHANGES:
#   - Combined Estimate : ax_combined = (A1 * x1) + (A2 * x2)
#   - Error Residual    : r = y - ax_combined
#   - Dual Gradients    : Grad1 = A1^H * r  |  Grad2 = A2^H * r
#   - Combined Power    : power = ||A1||^2 + ||A2||^2 (Used for global stability scaling)
#   - Parallel Updates  : x1(k+1) = x1(k) + alp * Grad1
#                         x2(k+1) = x2(k) + alp * Grad2
#
# * HARDWARE IMPLEMENTATION FEATURES:
#   - Fully Parameterized: Customizable word length (bits=16) and fractional precision (FRAC=12).
#   - Memory Scalability : Block-based sequential processing (BLOCK_SIZE) balances hardware 
#                          resource usage against throughput performance for large sample sets.
#
====================================================================================
*/

module Gradient_descent_2 #(
    parameter FRAC = 12,
    parameter sample = 400,
    parameter BLOCK_SIZE = 400,
    parameter bits = 16
)(
    input  wire          clk,
    input  wire          rst, 
    input  wire          start, 
    input  wire [(sample*bits-1):0]  y_vector,                    // 32 real samples * 16-bits = 512 bits
    input  wire [(sample*bits-1):0] A_col1_rel, A_col1_iml,
    input  wire [(sample*bits-1):0] A_col2_rel, A_col2_iml,    
    output reg  [(4*bits-1):0]   x_out,         
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
    wire signed [bits-1:0] A1_re [0:(sample-1)];
    wire signed [bits-1:0] A1_im [0:(sample-1)];
    wire signed [bits-1:0] A2_re [0:(sample-1)];
    wire signed [bits-1:0] A2_im [0:(sample-1)];

    reg  signed [bits-1:0] x1_re, x1_im;
    reg  signed [bits-1:0] x2_re, x2_im;
    reg  signed [bits+1:0] r_re [0:(sample-1)];
    reg  signed [bits+1:0] r_im [0:(sample-1)];

    genvar i;
    generate
        for(i = 0; i < sample; i = i + 1) begin: unpack_logic
            assign y[i]    = y_vector[(i*bits)+bits-1 : (i*bits)];          //Q4.12     ; Q(16-FRAC).FRAC
            assign A1_re[i] = A_col1_rel[(i*bits)+bits-1 : (i*bits)];
            assign A1_im[i] = A_col1_iml[(i*bits)+bits-1 : (i*bits)];
            assign A2_re[i] = A_col2_rel[(i*bits)+bits-1 : (i*bits)];
            assign A2_im[i] = A_col2_iml[(i*bits)+bits-1 : (i*bits)];
        end
    endgenerate

    wire signed [bits:0] ax1_re [0:(sample-1)];
    wire signed [bits:0] ax1_im [0:(sample-1)];
    wire signed [bits:0] ax2_re [0:(sample-1)];
    wire signed [bits:0] ax2_im [0:(sample-1)];
    
    reg signed [bits:0] ax_combined_re [0:sample-1];
    reg signed [bits:0] ax_combined_im [0:sample-1];
    generate
        for(i = 0; i < sample; i = i + 1) begin: ax_multipliers
            complex_multiplier #(
                .FRAC(FRAC)
            ) mult (
                .a_re(A1_re[i]), .a_im(A1_im[i]),
                .b_re(x1_re),    .b_im(x1_im),
                .p_re(ax1_re[i]), .p_im(ax1_im[i])                    //Q5.12            //Q(16-FRAC+1).FRAC Q9.8
            );

            complex_multiplier #(
                .FRAC(FRAC)
            ) mult1 (
                .a_re(A2_re[i]), .a_im(A2_im[i]),
                .b_re(x2_re),    .b_im(x2_im),
                .p_re(ax2_re[i]), .p_im(ax2_im[i])                   
            );

            always @(*) begin
                ax_combined_re[i] = ax1_re[i] + ax2_re[i];
                ax_combined_im[i] = ax1_im[i] + ax2_im[i];
            end

        end
    endgenerate

    reg signed [LOG+2*bits+2:0] total_grad_re;                    // Gradient 16+16+5=37 bits 
    reg signed [LOG+2*bits+2:0] total_grad_im;
    reg signed [LOG+2*bits+4:0] total_mse;                        // sum of 32 squared sample of each 16 bit can come up to 37 bit and adding real + img so 38 bit
    reg signed [LOG+2*bits+4:0] avg_y;

    reg signed [LOG+2*bits+2:0] total_grad1_re, total_grad1_im;
    reg signed [LOG+2*bits+2:0] total_grad2_re, total_grad2_im;
    
    wire signed [2*bits+4:0] next_x1_re;
    wire signed [2*bits+4:0] next_x1_im;
    wire signed [2*bits+4:0] next_x2_re;
    wire signed [2*bits+4:0] next_x2_im;

    //assign next_x_re = $signed({{(SHIFT_PRODUCT+1){x_re[15]}}, x_re}) + (($signed({1'b0, alp}) * $signed({{SHIFT_GRAD_ALPH{total_grad_re[(LOG+2*bits+2)]}}, total_grad_re})) >>> SHIFT_GRAD_ALPH);     //Q16.12   g*alpha = 16+12
    //assign next_x_im = $signed({{(SHIFT_PRODUCT+1){x_im[15]}}, x_im}) + (($signed({1'b0, alp}) * $signed({{SHIFT_GRAD_ALPH{total_grad_im[(LOG+2*bits+2)]}}, total_grad_im})) >>> SHIFT_GRAD_ALPH);     //Q

    assign next_x1_re = $signed({{(SHIFT_PRODUCT+1){x1_re[bits-1]}}, x1_re}) + (($signed({1'b0, alp}) * $signed({{SHIFT_GRAD_ALPH{total_grad1_re[(LOG+2*bits+2)]}}, total_grad1_re})) >>> SHIFT_GRAD_ALPH);     //Q16.12   g*alpha = 16+12
    assign next_x1_im = $signed({{(SHIFT_PRODUCT+1){x1_im[bits-1]}}, x1_im}) + (($signed({1'b0, alp}) * $signed({{SHIFT_GRAD_ALPH{total_grad1_im[(LOG+2*bits+2)]}}, total_grad1_im})) >>> SHIFT_GRAD_ALPH);     //Q16.12   g*alpha = 16+12
    assign next_x2_re = $signed({{(SHIFT_PRODUCT+1){x2_re[bits-1]}}, x2_re}) + (($signed({1'b0, alp}) * $signed({{SHIFT_GRAD_ALPH{total_grad2_re[(LOG+2*bits+2)]}}, total_grad2_re})) >>> SHIFT_GRAD_ALPH);     //Q16.12   g*alpha = 16+12
    assign next_x2_im = $signed({{(SHIFT_PRODUCT+1){x2_im[bits-1]}}, x2_im}) + (($signed({1'b0, alp}) * $signed({{SHIFT_GRAD_ALPH{total_grad2_im[(LOG+2*bits+2)]}}, total_grad2_im})) >>> SHIFT_GRAD_ALPH);     //Q16.12   g*alpha = 16+12


    wire signed [2*bits+4:0] check_re, check_im;
    integer idx;
    reg signed [LOG+2*bits+4:0] power;

    reg [LOG:0] base;

    assign check_re = (($signed({1'b0, alp}) * $signed({{SHIFT_GRAD_ALPH{total_grad1_re[(LOG+2*bits+2)]}}, total_grad1_re})) >>> SHIFT_GRAD_ALPH);
    assign check_im = (($signed({1'b0, alp}) * $signed({{SHIFT_GRAD_ALPH{total_grad1_im[(LOG+2*bits+2)]}}, total_grad1_im})) >>> SHIFT_GRAD_ALPH);

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            x1_re          <= 16'sd0;
            x1_im          <= 16'sd0;
            x2_re          <= 16'sd0;
            x2_im          <= 16'sd0;
            x_out         <= 32'd0;
            done          <= 1'b0;
        end 
        else begin
            case (state)
                
                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        x1_re          <= 16'sd0;
                        x1_im          <= 16'sd0;
                        x2_re          <= 16'sd0;
                        x2_im          <= 16'sd0;
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
                                power = power + (A1_re[idx + base] * A1_re[idx + base] + A1_im[idx + base] * A1_im[idx + base]) + (A2_re[idx + base] * A2_re[idx + base] + A2_im[idx + base] * A2_im[idx + base]);    // Q4.12*Q4.12*5 +1 = Q14.24    :Q22.16
                            end
                        end
                        base <= base + BLOCK_SIZE;
                    end
                    else begin
                        threshold <= (avg_y) >>> 7;                                    //~2 orders ; 2^7=128 ; Q6.24    ;Q14.16
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
                                r_re[idx + base] <= $signed(y[idx + base]) - $signed(ax_combined_re[idx + base]);                   //Q4.12 - Q5.12 = Q6.12       //Q(16-FRAC).FRAC - Q(16-FRAC+1).FRAC = Q(18-FRAC).(FRAC) = Q10.8
                                r_im[idx + base] <= 17'sd0 - $signed(ax_combined_im[idx + base]);                                   // y is real
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
                        total_grad1_re = 0;
                        total_grad1_im = 0;
                        total_grad2_re = 0;
                        total_grad2_im = 0;
                    end
                end

                GRADIENT: begin
                    if(base < sample) begin
                        for (idx = 0; idx < BLOCK_SIZE; idx = idx + 1) begin
                            if (base + idx < sample) begin
                                total_grad1_re = total_grad1_re + (A1_re[idx + base] * r_re[idx + base] + A1_im[idx + base] * r_im[idx + base]);        // Q4.12*Q6.12 + Q4.12*Q6.12 *5 = Q16.24
                                total_grad1_im = total_grad1_im + (A1_re[idx + base] * r_im[idx + base] - A1_im[idx + base] * r_re[idx + base] );      // ##Q8.8*Q10.8 - Q8.8*Q10.8 *5 = Q24.16
                                total_grad2_re = total_grad2_re + (A2_re[idx + base] * r_re[idx + base] + A2_im[idx + base] * r_im[idx + base]);        // Q4.12*Q6.12 + Q4.12*Q6.12 *5 = Q16.24
                                total_grad2_im = total_grad2_im + (A2_re[idx + base] * r_im[idx + base] - A2_im[idx + base] * r_re[idx + base] );      // ##Q8.8*Q10.8 - Q8.8*Q10.8 *5 = Q24.16
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
                    
                    if ((next_x1_re[bits-1] == 1'b0) && (next_x1_re[2*bits+4:bits-1] != 22'b0))             x1_re <= 16'sh7FFF;
                    else if ((next_x1_re[bits-1] == 1'b1) && (next_x1_re[2*bits+4:bits-1] != {22{1'b1}}))   x1_re <= 16'sh8000; 
                    else                                                                    x1_re <= next_x1_re[bits-1:0]; 

                    if ((next_x1_im[bits-1] == 1'b0) && (next_x1_im[2*bits+4:bits-1] != 22'b0))             x1_im <= 16'sh7FFF;
                    else if ((next_x1_im[bits-1] == 1'b1) && (next_x1_im[2*bits+4:bits-1] != {22{1'b1}}))   x1_im <= 16'sh8000;
                    else                                                                    x1_im <= next_x1_im[bits-1:0];

                    if ((next_x2_re[bits-1] == 1'b0) && (next_x2_re[2*bits+4:bits-1] != 22'b0))             x2_re <= 16'sh7FFF;
                    else if ((next_x2_re[bits-1] == 1'b1) && (next_x2_re[2*bits+4:bits-1] != {22{1'b1}}))   x2_re <= 16'sh8000; 
                    else                                                                    x2_re <= next_x2_re[bits-1:0];
                    
                    if ((next_x2_im[bits-1] == 1'b0) && (next_x2_im[2*bits+4:bits-1] != 22'b0))             x2_im <= 16'sh7FFF;
                    else if ((next_x2_im[bits-1] == 1'b1) && (next_x2_im[2*bits+4:bits-1] != {22{1'b1}}))   x2_im <= 16'sh8000;
                    else                                                                    x2_im <= next_x2_im[bits-1:0];

                    if((x1_re == next_x1_re[bits-1:0]) && (x1_im == next_x1_im[bits-1:0]) && (x2_re == next_x2_re[bits-1:0]) && (x2_im == next_x2_im[bits-1:0]))
                        state <= DONE;     
                    else
                        state <= COMPUTE_AX;     

                end

                DONE: begin
                    x_out <= {x1_re, x1_im, x2_re, x2_im};
                    done  <= 1'b1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule