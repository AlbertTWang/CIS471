/* Albert Wang & Tahmid Ahamed
 * albertwa & ahamedt
 *
 * lc4_regfile.v
 * Implements an 8-register register file parameterized on word size.
 *
 */

`timescale 1ns / 1ps

// Prevent implicit wire declaration
`default_nettype none

module lc4_regfile #(parameter n = 16)
   (input  wire         clk,
    input  wire         gwe,
    input  wire         rst,
    input  wire [  2:0] i_rs,      // rs selector
    output wire [n-1:0] o_rs_data, // rs contents
    input  wire [  2:0] i_rt,      // rt selector
    output wire [n-1:0] o_rt_data, // rt contents
    input  wire [  2:0] i_rd,      // rd selector
    input  wire [n-1:0] i_wdata,   // data to write
    input  wire         i_rd_we    // write enable
    );
    
    wire [7:0] temp = i_rd == 3'd0 ? 8'b00000001 :
                      i_rd == 3'd1 ? 8'b00000010 :
                      i_rd == 3'd2 ? 8'b00000100 :
                      i_rd == 3'd3 ? 8'b00001000 :
                      i_rd == 3'd4 ? 8'b00010000 :
                      i_rd == 3'd5 ? 8'b00100000 :
                      i_rd == 3'd6 ? 8'b01000000 : 8'b10000000;
    wire [n-1:0] oReg[7:0];
    genvar i;
    for (i = 0; i < 8; i = i + 1) begin
        wire we = (i_rd_we & temp[i]);
        Nbit_reg #(n) register_lc4 (.in(i_wdata),
                                    .out(oReg[i]),
                                    .clk(clk),
                                    .we(we),
                                    .gwe(gwe),
                                    .rst(rst));
    end
    assign o_rs_data = i_rs == 3'b000 ? oReg[0] :
                       i_rs == 3'b001 ? oReg[1] :
                       i_rs == 3'b010 ? oReg[2] :
                       i_rs == 3'b011 ? oReg[3] :
                       i_rs == 3'b100 ? oReg[4] :
                       i_rs == 3'b101 ? oReg[5] :
                       i_rs == 3'b110 ? oReg[6] : oReg[7];

    assign o_rt_data = i_rt == 3'b000 ? oReg[0] :
                       i_rt == 3'b001 ? oReg[1] :
                       i_rt == 3'b010 ? oReg[2] :
                       i_rt == 3'b011 ? oReg[3] :
                       i_rt == 3'b100 ? oReg[4] :
                       i_rt == 3'b101 ? oReg[5] :
                       i_rt == 3'b110 ? oReg[6] : oReg[7];


endmodule
