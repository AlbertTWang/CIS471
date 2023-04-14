`timescale 1ns / 1ps

// Prevent implicit wire declaration
`default_nettype none

/* 8-register, n-bit register file with
 * four read ports and two write ports
 * to support two pipes.
 * 
 * If both pipes try to write to the
 * same register, pipe B wins.
 * 
 * Inputs should be bypassed to the outputs
 * as needed so the register file returns
 * data that is written immediately
 * rather than only on the next cycle.
 */
module lc4_regfile_ss #(parameter n = 16)
   (input  wire         clk,
    input  wire         gwe,
    input  wire         rst,

    input  wire[  2:0] i_rs_A,      // pipe A: rs selector
    output wire[n-1:0] o_rs_data_A, // pipe A: rs contents
    input  wire[  2:0] i_rt_A,      // pipe A: rt selector
    output wire[n-1:0] o_rt_data_A, // pipe A: rt contents

    input  wire[  2:0] i_rs_B,      // pipe B: rs selector
    output wire[n-1:0] o_rs_data_B, // pipe B: rs contents
    input  wire[  2:0] i_rt_B,      // pipe B: rt selector
    output wire[n-1:0] o_rt_data_B, // pipe B: rt contents

    input  wire[  2:0]  i_rd_A,     // pipe A: rd selector
    input  wire[n-1:0]  i_wdata_A,  // pipe A: data to write
    input  wire          i_rd_we_A,  // pipe A: write enable

    input  wire[  2:0]  i_rd_B,     // pipe B: rd selector
    input  wire[n-1:0]  i_wdata_B,  // pipe B: data to write
    input  wire          i_rd_we_B   // pipe B: write enable
    );
    
    wire[7:0] A_inp = i_rd_A == 3'd0 ? 8'b00000001 : i_rd_A == 3'd1 ? 8'b00000010 : i_rd_A == 3'd2 ? 8'b00000100 :
                      i_rd_A == 3'd3 ? 8'b00001000 : i_rd_A == 3'd4 ? 8'b00010000 : i_rd_A == 3'd5 ? 8'b00100000 :
                      i_rd_A == 3'd6 ? 8'b01000000 : 8'b10000000;  

    wire[7:0] B_inp = i_rd_B == 3'd0 ? 8'b00000001 : i_rd_B == 3'd1 ? 8'b00000010 : i_rd_B == 3'd2 ? 8'b00000100 :
                      i_rd_B == 3'd3 ? 8'b00001000 : i_rd_B == 3'd4 ? 8'b00010000 : i_rd_B == 3'd5 ? 8'b00100000 :
                      i_rd_B == 3'd6 ? 8'b01000000 : 8'b10000000;
        
    wire[n-1:0] out_reg[7:0];
    genvar i;
    for (i = 0; i < 8; i = i + 1) begin
        Nbit_reg #(n) out (.in(inp_wdata),.out(out_reg[i]),.clk(clk), .we(reg_we),.gwe(gwe), .rst(rst));
        wire[n-1:0] inp_wdata = i_rd_we_B & B_inp[i] ? i_wdata_B : i_wdata_A;
        wire reg_we = i_rd_we_A & A_inp[i] | i_rd_we_B & B_inp[i];
    end

    assign o_rs_data_A = i_rd_we_B & (i_rs_A == i_rd_B) ? i_wdata_B : i_rd_we_A & (i_rd_A == i_rs_A) ? i_wdata_A : A_rs;
    assign o_rs_data_B = i_rd_we_B & (i_rd_B == i_rs_B) ? i_wdata_B : i_rd_we_A & (i_rd_A == i_rs_B) ? i_wdata_A : B_rs;
    assign o_rt_data_A = i_rd_we_B & (i_rt_A == i_rd_B) ? i_wdata_B : i_rd_we_A & (i_rd_A == i_rt_A) ? i_wdata_A : A_rt;
    assign o_rt_data_B = i_rd_we_B & (i_rd_B == i_rt_B) ? i_wdata_B : i_rd_we_A & (i_rd_A == i_rt_B) ? i_wdata_A : B_rt;

    wire[n-1:0] A_rs = i_rs_A == 3'b000 ? out_reg[0] : i_rs_A == 3'b001 ? out_reg[1] : i_rs_A == 3'b010 ? out_reg[2] :
                       i_rs_A == 3'b011 ? out_reg[3] : i_rs_A == 3'b100 ? out_reg[4] : i_rs_A == 3'b101 ? out_reg[5] :
                       i_rs_A == 3'b110 ? out_reg[6] : out_reg[7];

    wire[n-1:0] B_rs = i_rs_B == 3'b000 ? out_reg[0] : i_rs_B == 3'b001 ? out_reg[1] : i_rs_B == 3'b010 ? out_reg[2] :
                       i_rs_B == 3'b011 ? out_reg[3] :i_rs_B == 3'b100 ? out_reg[4] : i_rs_B == 3'b101 ? out_reg[5] :
                       i_rs_B == 3'b110 ? out_reg[6] : out_reg[7];

    wire[n-1:0] A_rt = i_rt_A == 3'b000 ? out_reg[0] : i_rt_A == 3'b001 ? out_reg[1] : i_rt_A == 3'b010 ? out_reg[2] :
                       i_rt_A == 3'b011 ? out_reg[3] : i_rt_A == 3'b100 ? out_reg[4] : i_rt_A == 3'b101 ? out_reg[5] :
                       i_rt_A == 3'b110 ? out_reg[6] : out_reg[7];

    wire[n-1:0] B_rt = i_rt_B == 3'b000 ? out_reg[0] : i_rt_B == 3'b001 ? out_reg[1] : i_rt_B == 3'b010 ? out_reg[2] :
                       i_rt_B == 3'b011 ? out_reg[3] : i_rt_B == 3'b100 ? out_reg[4] : i_rt_B == 3'b101 ? out_reg[5] :
                       i_rt_B == 3'b110 ? out_reg[6] : out_reg[7];

endmodule
