/* Tahmid Ahamed (ahamedt) and Albert Wang (albertwa) */

`timescale 1ns / 1ps
`default_nettype none
module lc4_alu(input  wire [15:0] i_insn,
               input wire [15:0]  i_pc,
               input wire [15:0]  i_r1data,
               input wire [15:0]  i_r2data,
               output wire [15:0] o_result);

        wire [15:0] first5;
        assign first5 = {{11{i_insn[4]}}, i_insn[4:0]};
        wire[15:0] logicFinal;
        assign logicFinal = (i_insn[5] == 1'b1) ? (i_r1data & first5) : (i_insn[4:3] == 2'b00) ? (i_r1data & i_r2data) :
                                (i_insn[4:3] == 2'b01) ? (~i_r1data) : (i_insn[4:3] == 2'b10) ? (i_r1data | i_r2data) :
                                (i_insn[4:3] == 2'b11) ? (i_r1data ^ i_r2data) : 16'b0000;

        wire [15:0] unsignedFirst7, first7;
        wire [15:0] cmp, cmpu, cmpi, cmpiu;
        assign unsignedFirst7 = {9'b000000000, i_insn[6:0]};
        assign first7 = {{9{i_insn[6]}}, i_insn[6:0]};
        assign cmp = ($signed(i_r1data) > $signed(i_r2data)) ? 16'h0001 : ($signed(i_r1data) == $signed(i_r2data)) ? 16'h0000 : 16'hffff;
        assign cmpu = ($unsigned(i_r1data) > $unsigned(i_r2data)) ? 16'h0001 : ($unsigned(i_r1data) == $unsigned(i_r2data)) ? 16'h0000 : 16'hffff;
        assign cmpi =   ($signed(i_r1data) > $signed(first7)) ? 16'h0001 : ($signed(i_r1data) == $signed(first7)) ? 16'h0000 : 16'hffff;
        assign cmpiu =  ($unsigned(i_r1data) > unsignedFirst7) ? 16'h0001 : ($unsigned(i_r1data) == unsignedFirst7) ? 16'h0000 : 16'hffff;
        wire[15:0] compareFinal;
        assign compareFinal = (i_insn[8:7] == 2'b00) ? cmp : (i_insn[8:7] == 2'b01) ? cmpu : (i_insn[8:7] == 2'b10) ? cmpi : cmpiu;

        wire [15:0] first8 = {8'b00000000, i_insn[7:0]};
        wire [15:0] hiconst, const;
        assign hiconst = (i_r1data & 16'h00ff) | (first8 << 8);
        assign const = {{7{i_insn[8]}}, i_insn[8:0]};
        wire[15:0] constFinal;
        assign constFinal = (i_insn[15:12] == 4'b1001) ? const : hiconst;

        wire [15: 0] modTemp;
        lc4_divider mod(.i_dividend(i_r1data), .i_divisor(i_r2data), .o_remainder(modTemp),.o_quotient());
        wire [15:0] modFinal;
        assign modFinal = (i_insn[5:4] == 2'b00) ? (i_r1data << i_insn[3:0]) : (i_insn[5:4] == 2'b01) ? $signed($signed(i_r1data) >>> i_insn[3:0]) :
                                  (i_insn[5:4] == 2'b10) ? (i_r1data >> i_insn[3:0]) : modTemp;

        wire [15:0] mulFinal;
        assign mulFinal = i_r1data * i_r2data;
        
        wire [15:0] divFinal;
        lc4_divider DIV_cal(.i_dividend(i_r1data), .i_divisor(i_r2data), .o_remainder(), .o_quotient(divFinal));

        wire [15:0] jsrFinal;
        wire [15:0] jsrrFinal;
        assign jsrFinal = (i_pc & 16'h8000) | (i_insn[10:0] << 4);
        assign jsrrFinal = i_r1data;

        wire [15:0] rtiFinal;
        assign rtiFinal = i_r1data;

        wire [15:0] trap;
        assign trap = (i_pc & 16'h0000) | (16'h8000 | {8'b00000000, i_insn[7:0]});

        wire signed [15:0] claFirst, claSecond;
        assign claFirst = (i_insn[15:12] == 4'b0000) ? i_pc : (i_insn[15:11] == 5'b11001) ? i_pc : i_r1data;
        assign claSecond = (i_insn[15:12] == 4'b0000) ? {{7{i_insn[8]}}, i_insn[8:0]} :
                           ({i_insn[15:12], i_insn[5]} == 5'b00011) ? {{11{i_insn[4]}}, i_insn[4:0]} :
                           ({i_insn[15:12], i_insn[4]} == 5'b00011) ? (~i_r2data) :
                           (i_insn[15:12] == 4'b0110) ? {{10{i_insn[5]}}, i_insn[5:0]} :
                           (i_insn[15:12] == 4'b0111) ? {{10{i_insn[5]}}, i_insn[5:0]} :
                           (i_insn[15:11] == 5'b11000) ? 16'h0000 :
                           (i_insn[15:11] == 5'b11001) ? {{5{i_insn[10]}}, i_insn[10:0]} : i_r2data;
                
        wire claThird;
        assign claThird = (i_insn[15:12] == 4'b0000) ? 1'b1 : ({i_insn[15:12], i_insn[5:3]} == 8'b0001010) ? 1'b1 : (i_insn[15:11] == 5'b11001) ? 1'b1 : 1'b0;
        wire[15:0] claFinal;
        cla16 CLA_cal(.a(claFirst), .b(claSecond), .cin(claThird), .sum(claFinal));

        assign o_result = (i_insn[15:12] == 4'b0101) ? logicFinal :
                          (i_insn[15:12] == 4'b0010) ? compareFinal :
                          (i_insn[15:12] == 4'b1001) ? constFinal :
                          (i_insn[15:12] == 4'b1101) ? constFinal :
                          (i_insn[15:12] == 4'b1010) ? modFinal :
                          ({i_insn[15:12], i_insn[5:3]} == 6'b01001) ? mulFinal :
                          ({i_insn[15:12], i_insn[5:3]} == 6'b01011) ? divFinal :
                          (i_insn[15:11] == 5'b01001) ? jsrFinal :           
                          (i_insn[15:11] == 5'b01000) ? jsrrFinal :          
                          (i_insn[15:12] == 4'b1000) ? rtiFinal :   
                          (i_insn[15:12] == 4'b1111) ? trap :          
                          claFinal;
        
endmodule
