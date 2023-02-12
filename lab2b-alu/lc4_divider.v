/* Albert Wang (albertwa) & Tahmid Ahamed (ahamedt) */

`timescale 1ns / 1ps
`default_nettype none

module lc4_divider(input  wire [15:0] i_dividend,
                   input  wire [15:0] i_divisor,
                   output wire [15:0] o_remainder,
                   output wire [15:0] o_quotient);
      
      wire [15:0] next_dividend[16:0];
      assign next_dividend[0] = i_dividend;

      wire [15:0] next_remainder[16:0];
      assign next_remainder[0] = 16'h0;

      wire [15:0] next_quotient[16:0];
      assign next_quotient[0] = 16'h0;

      genvar i;
      for (i = 0; i < 16; i = i + 1) begin
            lc4_divider_one_iter divider(.i_dividend(next_dividend[i]),
                                          .i_divisor(i_divisor),
                                          .i_remainder(next_remainder[i]),
                                          .i_quotient(next_quotient[i]),
                                          .o_dividend(next_dividend[i + 1]),
                                          .o_remainder(next_remainder[i + 1]),
                                          .o_quotient(next_quotient[i + 1]));
      end

      assign o_remainder = (i_divisor == 16'h0) ? 0 : next_remainder[16];
      assign o_quotient = (i_divisor == 16'h0) ? 0 : next_quotient[16];

endmodule // lc4_divider

module lc4_divider_one_iter(input  wire [15:0] i_dividend,
                            input  wire [15:0] i_divisor,
                            input  wire [15:0] i_remainder,
                            input  wire [15:0] i_quotient,
                            output wire [15:0] o_dividend,
                            output wire [15:0] o_remainder,
                            output wire [15:0] o_quotient);
                        
      wire [15:0] next_remainder;

      assign next_remainder = (i_remainder << 1) | ((i_dividend >> 15) & 16'b1);
      assign o_dividend = i_dividend << 1;

      assign o_remainder = (next_remainder < i_divisor) ? next_remainder : (next_remainder - i_divisor);
      assign o_quotient = (next_remainder < i_divisor) ? (i_quotient << 1) : ((i_quotient << 1) | 16'b1);


endmodule
