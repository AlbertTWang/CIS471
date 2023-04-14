`timescale 1ns / 1ps

// Prevent implicit wire declaration
`default_nettype none

module lc4_processor(input wire         clk,             // main clock
                     input wire         rst,             // global reset
                     input wire         gwe,             // global we for single-step clock

                     output wire[15:0] o_cur_pc,        // address to read from instruction memory
                     input wire[15:0]  i_cur_insn_A,    // output of instruction memory (pipe A)
                     input wire[15:0]  i_cur_insn_B,    // output of instruction memory (pipe B)

                     output wire[15:0] o_dmem_addr,     // address to read/write from/to data memory
                     input wire[15:0]  i_cur_dmem_data, // contents of o_dmem_addr
                     output wire        o_dmem_we,       // data memory write enable
                     output wire[15:0] o_dmem_towrite,  // data to write to o_dmem_addr if we is set

                     // testbench signals (always emitted from the WB stage)
                     output wire[ 1:0] test_stall_A,        // is this a stall cycle?  (0: no stall,
                     output wire[ 1:0] test_stall_B,        // 1: pipeline stall, 2: branch stall, 3: load stall)

                     output wire[15:0] test_cur_pc_A,       // program counter
                     output wire[15:0] test_cur_pc_B,
                     output wire[15:0] test_cur_insn_A,     // instruction bits
                     output wire[15:0] test_cur_insn_B,
                     output wire        test_regfile_we_A,   // register file write-enable
                     output wire        test_regfile_we_B,
                     output wire[ 2:0] test_regfile_wsel_A, // which register to write
                     output wire[ 2:0] test_regfile_wsel_B,
                     output wire[15:0] test_regfile_data_A, // data to write to register file
                     output wire[15:0] test_regfile_data_B,
                     output wire        test_nzp_we_A,       // nzp register write enable
                     output wire        test_nzp_we_B,
                     output wire[ 2:0] test_nzp_new_bits_A, // new nzp bits
                     output wire[ 2:0] test_nzp_new_bits_B,
                     output wire        test_dmem_we_A,      // data memory write enable
                     output wire        test_dmem_we_B,
                     output wire[15:0] test_dmem_addr_A,    // address to read/write from/to memory
                     output wire[15:0] test_dmem_addr_B,
                     output wire[15:0] test_dmem_data_A,    // data to read/write from/to memory
                     output wire[15:0] test_dmem_data_B,

                     // zedboard switches/display/leds (ignore if you don't want to control these)
                     input  wire[ 7:0] switch_data,         // read on/off status of zedboard's 8 switches
                     output wire[ 7:0] led_data             // set on/off status of zedboard's 8 leds
                     );

   assign led_data = switch_data;

   // Flush signals
   wire flush_A = 1'b0;
   wire flush_B = 1'b0;

   // Decode Wires
   wire[2:0] decode_A_rs_sel, decode_A_rt_sel, decode_A_rd_sel, decode_B_rs_sel, decode_B_rt_sel, decode_B_rd_sel;
   wire decode_rs_A, decode_rt_A, decode_A_regfile, decode_A_nzp, decode_A_increment, decode_A_load, decode_A_store, decode_A_branch, decode_A_control;
   wire decode_rs_B, decode_rt_B, decode_B_regfile, decode_B_nzp, decode_B_increment, decode_B_load, decode_B_store, decode_B_branch, decode_B_control;

   // Super-dependency & Memory Check
   wire A_super = ((decode_A_rd_sel == decode_B_rs_sel && decode_rs_B) || (decode_A_rd_sel == decode_B_rt_sel && decode_rt_B)) && decode_A_regfile;
   wire decode_mem = (decode_A_load || decode_A_store) && (decode_B_load || decode_B_store);
   
   // Stall conditions for A and B
   wire A_stall = (execute_A_load && (AA_hazard || decode_A_branch) && !(AB_hazard && execute_B_regfile)) || (execute_B_load && (AB_hazard || decode_A_branch));
   wire B_stall = (!A_super && ((execute_A_load && (BA_hazard || decode_B_branch) && !(BB_hazard && execute_B_regfile)) || (execute_B_load && (BB_hazard || decode_B_branch))));

   // Intermediate signals for stall conditions
   wire[1:0] A_stall_fetch = (flush_A || flush_B) ? 2'b10 : 2'b0;
   wire[1:0] B_stall_fetch = (flush_A || flush_B) ? 2'b10 : 2'b0;

   // Intermediate signals for load-use hazard check
   wire AA_hazard = (decode_A_rs_sel == decode_rs_A && execute_A_rd_sel) || (decode_A_rt_sel == decode_rt_A && execute_A_rd_sel && (!decode_A_store));
   wire AB_hazard = (decode_A_rs_sel == decode_rs_A && execute_B_rd_sel) || (decode_A_rt_sel == decode_rt_A && execute_B_rd_sel && (!decode_A_store));
   wire BA_hazard = (decode_B_rs_sel == decode_rs_B && execute_A_rd_sel) || (decode_B_rt_sel == decode_rt_B && execute_A_rd_sel && (!decode_B_store));
   wire BB_hazard = (decode_B_rs_sel == decode_rs_B && execute_B_rd_sel) || (decode_B_rt_sel == decode_rt_B && execute_B_rd_sel && (!decode_B_store));

   // Stall registers for A and B
   wire[1:0] decode_A_stall, decode_B_stall, execute_A_stall, execute_B_stall, memory_A_stall, memory_B_stall, write_A_stall, write_B_stall;
   Nbit_reg #(2, 2'b10) decode_A (.in(A_stall_fetch), .out(decode_A_stall), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(2, 2'b10) decode_B (.in(B_stall_fetch), .out(decode_B_stall), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(2, 2'b10) execute_A (.in(decode_A_stall), .out(execute_A_stall), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(2, 2'b10) execute_B_func (.in(pipe ? 2'b01 : decode_B_stall), .out(execute_B_stall), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(2, 2'b10) memory_A (.in(execute_A_stall), .out(memory_A_stall), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(2, 2'b10) memory_B (.in(execute_B_stall), .out(memory_B_stall), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(2, 2'b10) write_A (.in(memory_A_stall), .out(write_A_stall), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(2, 2'b10) write_B (.in(memory_B_stall), .out(write_B_stall), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));

   // Pipe switch signal & PC+1 vs PC+2
   wire pipe = A_super || B_stall || decode_mem;


   // Fetch (F)
   wire[15:0] fetch_A_pc;
   wire[15:0] pc_next;

   // F stage PC register for A
   Nbit_reg #(16, 16'h8200) fetch_A_pc_func (.in(pc_next), .out(fetch_A_pc), .clk(clk), .we(!A_stall && !B_stall), .gwe(gwe), .rst(rst));

   // Compute fetch_B_pc as fetch_A_pc + 1
   wire[15:0] fetch_B_pc;
   wire[15:0] F_pc_plus_one_B;
   cla16 A_pc_increment (.a(fetch_A_pc), .b(16'b1), .cin(1'b0), .sum(fetch_B_pc));
   cla16 B_pc_increment (.a(fetch_B_pc), .b(16'b1), .cin(1'b0), .sum(F_pc_plus_one_B));

   wire[15:0] pc_incr = pipe ? fetch_B_pc : F_pc_plus_one_B;
   assign pc_next = flush_A ? execute_A_alu : flush_B ? execute_B_alu : pc_incr;

   // Decode (D)        
   // D stage registers for A
   wire[15:0] decode_A_insn, decode_A_pc, decode_A_pc_incr;
   Nbit_reg #(16) decode_insn_A (.in(pipe ? decode_B_insn : i_cur_insn_A), .out(decode_A_insn), .clk(clk), .we(!A_stall), .gwe(gwe), .rst(rst || flush_A || flush_B));
   Nbit_reg #(16) decode_pc_A (.in(pipe ? decode_B_pc : fetch_A_pc), .out(decode_A_pc), .clk(clk), .we(!A_stall), .gwe(gwe), .rst(rst || flush_A || flush_B));
   Nbit_reg #(16) decode_pc_increment_A (.in(pipe ? decode_B_pc_incr : fetch_B_pc), .out(decode_A_pc_incr), .clk(clk), .we(!A_stall), .gwe(gwe), .rst(rst || flush_A || flush_B));

   // D stage registers for B
   wire[15:0] decode_B_insn, decode_B_pc, decode_B_pc_incr;
   Nbit_reg #(16) decode_insn_B (.in(pipe ? i_cur_insn_A : i_cur_insn_B), .out(decode_B_insn), .clk(clk), .we(!A_stall && !B_stall), .gwe(gwe), .rst(rst || flush_A || flush_B));
   Nbit_reg #(16) decode_pc_B (.in(pipe ? fetch_A_pc : fetch_B_pc), .out(decode_B_pc), .clk(clk), .we(!A_stall && !B_stall), .gwe(gwe), .rst(rst || flush_A || flush_B));
   Nbit_reg #(16) decode_pc_increment_B (.in(pipe ? decode_A_pc_incr : F_pc_plus_one_B), .out(decode_B_pc_incr), .clk(clk), .we(!A_stall && !B_stall), .gwe(gwe), .rst(rst || flush_A || flush_B));

   // Regfile
   wire[15:0] decode_A_rs, decode_A_rt, decode_B_rs, decode_B_rt;
   lc4_regfile_ss #(.n(16)) regfile(.clk(clk),.gwe(gwe), .rst(rst),
                                    .i_rs_A(decode_A_rs_sel), .o_rs_data_A(decode_A_rs), .i_rt_A(decode_A_rt_sel), .o_rt_data_A(decode_A_rt),
                                    .i_rd_A(write_A_rd), .i_wdata_A(write_A_data), .i_rd_we_A(write_A_regfile),
                                    .i_rs_B(decode_B_rs_sel), .o_rs_data_B(decode_B_rs), .i_rt_B(decode_B_rt_sel), .o_rt_data_B(decode_B_rt),
                                    .i_rd_B(write_B_rd), .i_wdata_B(write_B_data), .i_rd_we_B(write_B_regfile));

   // LC4 decoder for A
   lc4_decoder lc4_decode_A (.insn(decode_A_insn), .r1sel(decode_A_rs_sel), .r1re(decode_rs_A), .r2sel(decode_A_rt_sel), .r2re(decode_rt_A),
                            .wsel(decode_A_rd_sel), .regfile_we(decode_A_regfile), .nzp_we(decode_A_nzp), .select_pc_plus_one(decode_A_increment),
                            .is_load(decode_A_load), .is_store(decode_A_store), .is_branch(decode_A_branch), .is_control_insn(decode_A_control));

   // LC4 decoder for B
   lc4_decoder lc4_decode_B (.insn(decode_B_insn), .r1sel(decode_B_rs_sel), .r1re(decode_rs_B), .r2sel(decode_B_rt_sel), .r2re(decode_rt_B),
                            .wsel(decode_B_rd_sel), .regfile_we(decode_B_regfile), .nzp_we(decode_B_nzp), .select_pc_plus_one(decode_B_increment),
                            .is_load(decode_B_load), .is_store(decode_B_store), .is_branch(decode_B_branch), .is_control_insn(decode_B_control));
                                    

   // Execute (X)
   wire[15:0] execute_A_rs, execute_A_rt, execute_A_insn, execute_A_pc, execute_A_increment;
   Nbit_reg #(16) execute_A_rs_func (.in(decode_A_rs), .out(execute_A_rs), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst || flush_A || A_stall));
   Nbit_reg #(16) execute_A_rt_func (.in(decode_A_rt), .out(execute_A_rt), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst || flush_A || A_stall));
   Nbit_reg #(16) execute_A_insn_func (.in(decode_A_insn), .out(execute_A_insn), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst || flush_A || A_stall));
   Nbit_reg #(16) execute_A_pc_func (.in(decode_A_pc), .out(execute_A_pc), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst || flush_A || A_stall));
   Nbit_reg #(16) execute_A_increment_func (.in(decode_A_pc_incr), .out(execute_A_increment), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst || flush_A || A_stall));

   wire execute_A_load, execute_A_branch, execute_A_store, execute_A_control, execute_A_regfile, execute_A_nzp, execute_A_increment_sel;
   Nbit_reg #(1) execute_A_load_func (.in(decode_A_load), .out(execute_A_load), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst || flush_A || A_stall));
   Nbit_reg #(1) execute_A_store_func (.in(decode_A_store), .out(execute_A_store), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst || flush_A || A_stall));
   Nbit_reg #(1) execute_A_branch_func (.in(decode_A_branch), .out(execute_A_branch), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst || flush_A || A_stall));
   Nbit_reg #(1) execute_A_control_func (.in(decode_A_control), .out(execute_A_control), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst || flush_A || A_stall));
   Nbit_reg #(1) execute_A_regfile_func (.in(decode_A_regfile), .out(execute_A_regfile), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst || flush_A || A_stall));
   Nbit_reg #(1) execute_A_nzp_func (.in(decode_A_nzp), .out(execute_A_nzp), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst || flush_A || A_stall));
   Nbit_reg #(1) execute_A_increment_sel_func (.in(decode_A_increment), .out(execute_A_increment_sel), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst || flush_A || A_stall));

   wire[2:0] execute_A_rs_sel, execute_A_rt_sel, execute_A_rd_sel;
   Nbit_reg #(3) execute_A_rs_sel_func (.in(decode_A_rs_sel), .out(execute_A_rs_sel), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst || flush_A || A_stall));
   Nbit_reg #(3) execute_A_rt_sel_func (.in(decode_A_rt_sel), .out(execute_A_rt_sel), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst || flush_A || A_stall));
   Nbit_reg #(3) execute_A_rd_sel_func (.in(decode_A_rd_sel), .out(execute_A_rd_sel), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst || flush_A || A_stall));


   wire execute_B = A_stall || pipe || flush_A || flush_B;
   wire[15:0] execute_B_rs, execute_B_rt, execute_B_insn, execute_B_pc, execute_B_increment;
   Nbit_reg #(16) execute_B_rs_func (.in(decode_B_rs), .out(execute_B_rs), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst || execute_B));
   Nbit_reg #(16) execute_B_rt_func (.in(decode_B_rt), .out(execute_B_rt), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst || execute_B));
   Nbit_reg #(16) execute_B_insn_func (.in(decode_B_insn), .out(execute_B_insn), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst || execute_B));
   Nbit_reg #(16) execute_B_pc_func (.in(decode_B_pc), .out(execute_B_pc), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst || execute_B));
   Nbit_reg #(16) execute_B_increment_func (.in(decode_B_pc_incr), .out(execute_B_increment), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst || execute_B));

   wire execute_B_load, execute_B_branch, execute_B_store, execute_B_control, execute_B_regfile, execute_B_nzp, execute_B_increment_sel;
   Nbit_reg #(1) execute_B_load_func (.in(decode_B_load), .out(execute_B_load), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst || execute_B));
   Nbit_reg #(1) execute_B_store_func (.in(decode_B_store), .out(execute_B_store), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst || execute_B));
   Nbit_reg #(1) execute_B_branch_func (.in(decode_B_branch), .out(execute_B_branch), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst || execute_B));
   Nbit_reg #(1) execute_B_control_func (.in(decode_B_control), .out(execute_B_control), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst || execute_B));
   Nbit_reg #(1) execute_B_regfile_func (.in(decode_B_regfile), .out(execute_B_regfile), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst || execute_B));
   Nbit_reg #(1) execute_B_nzp_func (.in(decode_B_nzp), .out(execute_B_nzp), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst || flush_A || execute_B));
   Nbit_reg #(1) execute_B_increment_sel_func (.in(decode_B_increment), .out(execute_B_increment_sel), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst || execute_B));

   wire[2:0] execute_B_rs_sel, execute_B_rt_sel, execute_B_rd_sel;
   Nbit_reg #(3) execute_B_rs_sel_func (.in(decode_B_rs_sel), .out(execute_B_rs_sel), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst || execute_B));
   Nbit_reg #(3) execute_B_rt_sel_func (.in(decode_B_rt_sel), .out(execute_B_rt_sel), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst || execute_B));
   Nbit_reg #(3) execute_B_rd_sel_func (.in(decode_B_rd_sel), .out(execute_B_rd_sel), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst || execute_B));

   wire[15:0] execute_A_first_mux = ((execute_A_rs_sel == memory_B_rd_sel) && memory_B_regfile) ? memory_B_alu :
                                        ((execute_A_rs_sel == memory_A_rd_sel) && memory_A_regfile) ? memory_A_alu :
                                        ((execute_A_rs_sel == write_B_rd) && write_B_regfile) ? write_B_which :
                                        ((execute_A_rs_sel == write_A_rd) && write_A_regfile) ? write_A_which : execute_A_rs;
                                    
   wire[15:0] execute_A_second_mux = ((execute_A_rt_sel == memory_B_rd_sel) && memory_B_regfile) ? memory_B_alu :
                                        ((execute_A_rt_sel == memory_A_rd_sel) && memory_A_regfile) ? memory_A_alu :
                                        ((execute_A_rt_sel == write_B_rd) && write_B_regfile)? write_B_which :
                                        ((execute_A_rt_sel == write_A_rd) && write_A_regfile)? write_A_which : execute_A_rt;
   
   wire[15:0] execute_A_alu;                                    
   lc4_alu A_alu(.i_insn(execute_A_insn), .i_pc(execute_A_pc), .i_r1data(execute_A_first_mux), .i_r2data(execute_A_second_mux), .o_result(execute_A_alu));

   wire[15:0] execute_B_first_mux = (execute_B_rs_sel == memory_B_rd_sel & memory_B_regfile) ? memory_B_alu :
                                        (execute_B_rs_sel == memory_A_rd_sel & memory_A_regfile) ? memory_A_alu :
                                        (execute_B_rs_sel == write_B_rd & write_B_regfile) ? write_B_which :
                                        (execute_B_rs_sel == write_A_rd & write_A_regfile) ? write_A_which : execute_B_rs;
                                       
   wire[15:0] execute_B_second_mux = (execute_B_rt_sel == memory_B_rd_sel & memory_B_regfile) ? memory_B_alu :
                                       (execute_B_rt_sel == memory_A_rd_sel & memory_A_regfile) ? memory_A_alu :
                                       (execute_B_rt_sel == write_B_rd & write_B_regfile) ? write_B_which :
                                       (execute_B_rt_sel == write_A_rd & write_A_regfile) ? write_A_which : execute_B_rt;
                                       
   wire[15:0] execute_B_alu;
   lc4_alu alu_B(.i_insn(execute_B_insn), .i_pc(execute_B_pc), .i_r1data(execute_B_first_mux), .i_r2data(execute_B_second_mux), .o_result(execute_B_alu));

   wire[2:0] execute_A_nzp_new, execute_B_nzp_new;
   assign execute_A_nzp_new[0] = $signed(execute_A_nzp_write) > 0;
   assign execute_A_nzp_new[1] = $signed(execute_A_nzp_write) == 0;
   assign execute_A_nzp_new[2] = $signed(execute_A_nzp_write) < 0;
   
   assign execute_B_nzp_new[0] = $signed(execute_B_nzp_write) > 0;
   assign execute_B_nzp_new[1] = $signed(execute_B_nzp_write) == 0;
   assign execute_B_nzp_new[2] = $signed(execute_B_nzp_write) < 0;

   wire temp_A_insn = execute_A_insn[15:12];
   wire temp_B_insn = execute_B_insn[15:12];
   wire execute_A_last = (temp_A_insn == 4'b1000 || temp_A_insn == 4'b1111 || temp_A_insn == 4'b0100);
   wire execute_B_last = (temp_B_insn == 4'b1000 || temp_B_insn == 4'b1111 || temp_B_insn == 4'b0100);
   wire[15:0] execute_A_nzp_write = execute_A_last ? execute_A_increment : execute_A_alu;
   wire[15:0] execute_B_nzp_write = execute_B_last ? execute_B_increment : execute_B_alu;

   wire[2:0] execute_nzp_which = execute_B_nzp ? execute_B_nzp_new : execute_A_nzp ? execute_A_nzp_new : 3'b000;
   wire execute_nzp_which_we = execute_A_nzp ||  execute_B_nzp;

   wire[2:0] nzp_out;
   Nbit_reg #(3) nzp (.in(execute_nzp_which), .out(nzp_out), .clk(clk), .we(execute_nzp_which_we), .gwe(gwe), .rst(rst));
       

   // Memory (M)
   wire[15:0] memory_A_alu, memory_A_rt, memory_A_insn, memory_A_pc, memory_A_increment;
   Nbit_reg #(16) memory_A_alu_func (.in(execute_A_alu), .out(memory_A_alu), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(16) memory_A_rt_func (.in(execute_A_second_mux), .out(memory_A_rt), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(16) memory_A_insn_func (.in(execute_A_insn), .out(memory_A_insn), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(16) memory_A_pc_func (.in(execute_A_pc), .out(memory_A_pc), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(16) memory_A_increment_func (.in(execute_A_increment), .out(memory_A_increment), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));

   wire memory_A_regfile, memory_A_nzp, memory_A_increment_select, memory_A_load, memory_A_branch, memory_A_store, memory_A_control;
   Nbit_reg #(1) memory_A_regfile_func (.in(execute_A_regfile), .out(memory_A_regfile), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(1) memory_A_nzp_func (.in(execute_A_nzp), .out(memory_A_nzp), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(1) memory_A_increment_sel_func (.in(execute_A_increment_sel), .out(memory_A_increment_select), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(1) memory_A_load_func (.in(execute_A_load), .out(memory_A_load), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(1) memory_A_store_func (.in(execute_A_store), .out(memory_A_store), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(1) memory_A_branch_func (.in(execute_A_branch), .out(memory_A_branch), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(1) memory_A_control_func (.in(execute_A_control), .out(memory_A_control), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));

   wire[2:0] memory_A_rs_sel, memory_A_rt_sel, memory_A_rd_sel, memory_A_nzp_new;
   Nbit_reg #(3) memory_A_rs_sel_func (.in(execute_A_rs_sel), .out(memory_A_rs_sel), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(3) memory_A_rt_sel_func (.in(execute_A_rt_sel), .out(memory_A_rt_sel), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(3) memory_A_rd_sel_func (.in(execute_A_rd_sel), .out(memory_A_rd_sel), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(3) memory_A_nzp_new_func (.in(execute_A_nzp_new), .out(memory_A_nzp_new), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));


   wire[15:0] memory_B_alu, memory_B_rt, memory_B_insn, memory_B_pc, memory_B_increment;
   Nbit_reg #(16) memory_B_alu_func (.in(execute_B_alu), .out(memory_B_alu), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(16) memory_B_rt_func (.in(execute_B_second_mux), .out(memory_A_rt), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(16) memory_B_insn_func (.in(execute_B_insn), .out(memory_B_insn), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(16) memory_B_pc_func (.in(execute_B_pc), .out(memory_B_pc), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(16) memory_B_increment_func (.in(execute_B_increment), .out(memory_B_increment), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));

   wire memory_B_regfile, memory_B_nzp, memory_B_increment_select, memory_B_load, memory_B_branch, memory_B_store, memory_B_control;
   Nbit_reg #(1) memory_B_regfile_func (.in(execute_B_regfile), .out(memory_B_regfile), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(1) memory_B_nzp_func (.in(execute_B_nzp), .out(memory_B_nzp), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(1) memory_B_increment_sel_func (.in(execute_B_increment_sel), .out(memory_B_increment_select), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(1) memory_B_load_func (.in(execute_B_load), .out(memory_B_load), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(1) memory_B_store_func (.in(execute_B_store), .out(memory_B_store), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(1) memory_B_branch_func (.in(execute_B_branch), .out(memory_B_branch), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(1) memory_B_control_func (.in(execute_B_control), .out(memory_B_control), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));

   wire[2:0] memory_B_rs_sel, memory_B_rt_sel, memory_B_rd_sel, memory_B_nzp_new;
   Nbit_reg #(3) memory_B_rs_sel_func (.in(execute_B_rs_sel), .out(memory_B_rs_sel), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(3) memory_B_rt_sel_func (.in(execute_B_rt_sel), .out(memory_B_rt_sel), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(3) memory_B_rd_sel_func (.in(execute_B_rd_sel), .out(memory_B_rd_sel), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(3) memory_B_nzp_new_func (.in(execute_B_nzp_new), .out(memory_B_nzp_new), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));

   wire[15:0] memory_A_bypass = (write_B_regfile && (write_B_rd == memory_A_rt_sel) && memory_A_store) ? write_B_which :
                                (write_A_regfile && (write_A_rd == memory_A_rt_sel) && memory_A_store) ? write_A_which : memory_A_rt;

   wire[15:0] memory_B_bypass = (write_B_regfile && (write_B_rd == memory_B_store) && write_B_regfile) ? write_B_which :
                                (write_A_regfile && (write_A_rd == memory_B_rt_sel) && memory_B_store) ? write_A_which : memory_B_rt;

   wire[15:0] memory_A_which = memory_A_load ? i_cur_dmem_data : memory_A_alu;
   wire[15:0] memory_B_which = memory_B_load ? i_cur_dmem_data : memory_B_alu;
   wire[15:0] memory_A_regfile_write = memory_A_increment_select ? memory_A_increment : memory_A_which;
   wire[15:0] memory_B_regfile_write = memory_B_increment_select ? memory_B_increment : memory_B_which;


   // Write (W)
   wire[2:0] memory_nzp;
   assign memory_nzp[0] = $signed(i_cur_dmem_data) > 0;
   assign memory_nzp[1] = $signed(i_cur_dmem_data) == 0;
   assign memory_nzp[2] = $signed(i_cur_dmem_data) < 0;
   
   wire[2:0] write_A_nzp_new;
   wire[2:0] write_B_nzp_new;
   Nbit_reg #(3) write_A_nzp_new_func (.in(memory_A_load ? memory_nzp : memory_A_nzp_new), .out(write_A_nzp_new), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(3) write_B_nzp_new_func (.in(memory_B_load ? memory_nzp : memory_B_nzp_new), .out(write_B_nzp_new), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   
   wire[15:0] write_A_alu, write_A_dmem, write_A_insn, write_A_pc, write_A_increment, write_A_dmem_inp, write_A_dmem_addr, write_A_which, write_A_data;
   Nbit_reg #(16) write_A_alu_func (.in(memory_A_alu), .out(write_A_alu), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(16) write_A_dmem_func (.in(i_cur_dmem_data), .out(write_A_dmem), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(16) write_A_insn_func (.in(memory_A_insn), .out(write_A_insn), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(16) write_A_pc_func (.in(memory_A_pc), .out(write_A_pc), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(16) write_A_increment_func (.in(memory_A_increment), .out(write_A_increment), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(16) write_A_dmem_inp_func (.in(memory_A_bypass), .out(write_A_dmem_inp), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(16) write_A_dmem_addr_func (.in(memory_A_alu), .out(write_A_dmem_addr), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(16) write_A_which_func (.in(memory_A_which), .out(write_A_which), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(16) write_A_data_func (.in(memory_A_regfile_write), .out(write_A_data), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));

   wire write_A_regfile, write_A_nzp, write_A_increment_sel, write_A_dmem_reg, write_A_load, write_A_branch, write_A_control;
   Nbit_reg #(1) write_A_regfile_func (.in(memory_A_regfile), .out(write_A_regfile), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(1) write_A_nzp_func (.in(memory_A_nzp), .out(write_A_nzp), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(1) write_A_increment_sel_func (.in(memory_A_increment_select), .out(write_A_increment_sel), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(1) write_A_dmem_reg_func (.in(memory_A_store), .out(write_A_dmem_reg), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(1) write_A_load_func (.in(memory_A_load), .out(write_A_load), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(1) write_A_branch_func (.in(memory_A_branch), .out(write_A_branch), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(1) write_A_control_func (.in(memory_A_control), .out(write_A_control), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));

   wire[2:0] write_A_rd;
   Nbit_reg #(3) write_A_rd_func (.in(memory_A_rd_sel), .out(write_A_rd), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));


   wire[15:0] write_B_alu, write_B_dmem, write_B_insn, write_B_pc, write_B_increment, write_B_dmem_inp, write_B_dmem_addr, write_B_which, write_B_data;
   Nbit_reg #(16) write_B_alu_func (.in(memory_B_alu), .out(write_B_alu), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(16) write_B_dmem_func (.in(i_cur_dmem_data), .out(write_B_dmem), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(16) write_B_insn_func (.in(memory_B_insn), .out(write_B_insn), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(16) write_B_pc_func (.in(memory_B_pc), .out(write_B_pc), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(16) write_B_increment_func (.in(memory_B_increment), .out(write_B_increment), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(16) write_B_dmem_inp_func (.in(memory_B_bypass), .out(write_B_dmem_inp), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(16) write_B_dmem_addr_func (.in(memory_B_alu), .out(write_B_dmem_addr), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(16) write_B_which_func (.in(memory_B_which), .out(write_B_which), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(16) write_B_data_func (.in(memory_B_regfile_write), .out(write_B_data), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));

   wire write_B_regfile, write_B_nzp, write_B_increment_sel, write_B_dmem_reg, write_B_load, write_B_branch, write_B_control;
   Nbit_reg #(1) write_B_regfile_func (.in(memory_B_regfile), .out(write_B_regfile), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(1) write_B_nzp_func (.in(memory_B_nzp), .out(write_B_nzp), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(1) write_B_increment_sel_func (.in(memory_B_increment_select), .out(write_B_increment_sel), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(1) write_B_dmem_reg_func (.in(memory_B_store), .out(write_B_dmem_reg), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(1) write_B_load_func (.in(memory_B_load), .out(write_B_load), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(1) write_B_branch_func (.in(memory_B_branch), .out(write_B_branch), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));
   Nbit_reg #(1) write_B_control_func (.in(memory_B_control), .out(write_B_control), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));

   wire[2:0] write_B_rd;
   Nbit_reg #(3) write_B_rd_func (.in(memory_B_rd_sel), .out(write_B_rd), .clk(clk), .we(1'b1), .gwe(gwe), .rst(rst));


   assign o_cur_pc = fetch_A_pc;
   assign test_cur_pc_A = write_A_pc;
   assign test_cur_pc_B = write_B_pc;
   assign test_cur_insn_A = write_A_insn;
   assign test_cur_insn_B = write_B_insn;
   assign test_regfile_we_A = write_A_regfile;
   assign test_regfile_we_B = write_B_regfile;
   assign test_regfile_wsel_A = write_A_rd;
   assign test_regfile_wsel_B = write_B_rd;
   assign test_regfile_data_A = write_A_data;
   assign test_regfile_data_B = write_B_data;
   assign test_nzp_we_A = write_A_nzp;
   assign test_nzp_we_B = write_B_nzp;
   assign test_nzp_new_bits_A = write_A_nzp_new;
   assign test_nzp_new_bits_B = write_B_nzp_new;
   assign test_dmem_we_A = write_A_dmem_reg;
   assign test_dmem_we_B = write_B_dmem_reg;
   assign test_dmem_addr_A = (write_A_dmem_reg || write_A_load) ? write_A_dmem_addr : 16'b0;
   assign test_dmem_addr_B = (write_B_dmem_reg || write_B_load) ? write_B_dmem_addr : 16'b0;
   assign test_dmem_data_A = (write_A_load) ? write_A_dmem : (write_A_dmem_reg) ? write_A_dmem_inp : 16'b0;
   assign test_dmem_data_B = (write_B_load) ? write_B_dmem : (write_B_dmem_reg) ? write_B_dmem_inp : 16'b0;
   assign test_stall_A = write_A_stall;
   assign test_stall_B = write_B_stall;


   /* Add $display(...) calls in the always block below to
    * print out debug information at the end of every cycle.
    *
    * You may also use if statements inside the always block
    * to conditionally print out information.
    */
   always @(posedge gwe) begin
      // $display("%d %h %h %h %h %h", $time, f_pc, d_pc, e_pc, m_pc, test_cur_pc);
      // if (o_dmem_we)
      //   $display("%d STORE %h <= %h", $time, o_dmem_addr, o_dmem_towrite);

      // Start each $display() format string with a %d argument for time
      // it will make the output easier to read.  Use %b, %h, and %d
      // for binary, hex, and decimal output of additional variables.
      // You do not need to add a \n at the end of your format string.
      // $display("%d ...", $time);

      // Try adding a $display() call that prints out the PCs of
      // each pipeline stage in hex.  Then you can easily look up the
      // instructions in the .asm files in test_data.

      // basic if syntax:
      // if (cond) begin
      //    ...;
      //    ...;
      // end

      // Set a breakpoint on the empty $display() below
      // to step through your pipeline cycle-by-cycle.
      // You'll need to rewind the simulation to start
      // stepping from the beginning.

      // You can also simulate for XXX ns, then set the
      // breakpoint to start stepping midway through the
      // testbench.  Use the $time printouts you added above (!)
      // to figure out when your problem instruction first
      // enters the fetch stage.  Rewind your simulation,
      // run it for that many nanoseconds, then set
      // the breakpoint.

      // In the objects view, you can change the values to
      // hexadecimal by selecting all signals (Ctrl-A),
      // then right-click, and select Radix->Hexadecimal.

      // To see the values of wires within a module, select
      // the module in the hierarchy in the "Scopes" pane.
      // The Objects pane will update to display the wires
      // in that module.

      //$display();
   end
endmodule
