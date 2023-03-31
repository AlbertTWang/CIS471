/* Albert Wang (albertwa) & Tahmid Ahamed (ahamedt) */

`timescale 1ns / 1ps

// disable implicit wire declaration
`default_nettype none

module lc4_processor
   (input  wire        clk,                // main clock
    input wire         rst, // global reset
    input wire         gwe, // global we for single-step clock
                                    
    output wire [15:0] o_cur_pc, // Address to read from instruction memory
    input wire [15:0]  i_cur_insn, // Output of instruction memory
    output wire [15:0] o_dmem_addr, // Address to read/write from/to data memory
    input wire [15:0]  i_cur_dmem_data, // Output of data memory
    output wire        o_dmem_we, // Data memory write enable
    output wire [15:0] o_dmem_towrite, // Value to write to data memory
   
    output wire [1:0]  test_stall, // Testbench: is this is stall cycle? (don't compare the test values)
    output wire [15:0] test_cur_pc, // Testbench: program counter
    output wire [15:0] test_cur_insn, // Testbench: instruction bits
    output wire        test_regfile_we, // Testbench: register file write enable
    output wire [2:0]  test_regfile_wsel, // Testbench: which register to write in the register file 
    output wire [15:0] test_regfile_data, // Testbench: value to write into the register file
    output wire        test_nzp_we, // Testbench: NZP condition codes write enable
    output wire [2:0]  test_nzp_new_bits, // Testbench: value to write to NZP bits
    output wire        test_dmem_we, // Testbench: data memory write enable
    output wire [15:0] test_dmem_addr, // Testbench: address to read/write memory
    output wire [15:0] test_dmem_data, // Testbench: value read/writen from/to memory

    input wire [7:0]   switch_data, // Current settings of the Zedboard switches
    output wire [7:0]  led_data // Which Zedboard LEDs should be turned on?
    );

   
   
   /*** YOUR CODE HERE ***/

   /* Add $display(...) calls in the always block below to
    * print out debug information at the end of every cycle.
    * 
    * You may also use if statements inside the always block
    * to conditionally print out information.
    *
    * You do not need to resynthesize and re-implement if this is all you change;
    * just restart the simulation.
    */


   assign led_data = switch_data;

   localparam INIT_PC = 16'h8200;

   // All Wires
   wire [15:0] pcPlusOne;
   wire [15:0] pc;
   wire [15:0] next_pc = branch_taken ? execute_aluout : (stall ? pc : pcPlusOne);
   wire [15:0] decode_pc;
   wire [15:0] decode_insn;
   wire [15:0] decode_pc_plus_one;
   wire [17:0] decode_out;
   wire [15:0] decode_r1;
   wire [15:0] decode_r2;
   wire [15:0] decode_r1_out;
   wire [15:0] decode_r2_out;
   wire [15:0] execute_pc;
   wire [15:0] execute_insn;
   wire [17:0] execute_decode;
   wire [15:0] execute_r1;
   wire [15:0] execute_r2;
   wire [15:0] execute_pcPlusOne;
   wire [15:0] execute_aluout;
   wire [15:0] memory_pc;
   wire [15:0] memory_insn;
   wire [17:0] memory;
   wire [15:0] memory_r2;
   wire [15:0] memory_alu;
   wire [15:0] execute_r1_final;
   wire [15:0] execute_r2_final;
   wire [15:0] memory_pcPlusOne;
   wire [15:0] writeback_pc;
   wire [15:0] writeback_insn;
   wire [17:0] writeback;
   wire [15:0] writeback_rd;
   wire [15:0] writeback_dmem;
   wire [15:0] writeback_dmem_write;
   wire [15:0] writeback_addr;

   // PC register
   Nbit_reg #(16, INIT_PC) pcReg (
      .in(next_pc), 
      .out(pc), 
      .clk(clk), 
      .we(1'b1), 
      .gwe(gwe),
      .rst(rst)
   );
   
   // PC increment
   cla16 pcInc (
      .a(pc), 
      .b(16'b1), 
      .cin(1'b0), 
      .sum(pcPlusOne)
   );


   // D-stage instruction register
   Nbit_reg #(16, 16'd0) decode_insn_pipe (
      .in(branch_taken ? 16'b0 : i_cur_insn), 
      .out(decode_insn),
      .clk(clk),
      .we(!stall),
      .gwe(gwe),
      .rst(rst)
   );
   
   // D-stage PC register
   Nbit_reg #(16, INIT_PC) decode_pc_pipe (
      .in(branch_taken ? 16'b0 : pc),
      .out(decode_pc),
      .clk(clk),
      .we(!stall),
      .gwe(gwe),
      .rst(rst)
   );

   // D-stage PC+1 register
   Nbit_reg #(16, 16'd0) decode_pcPlusOne_pipe (
      .in(branch_taken ? 16'b0 : pcPlusOne),
      .out(decode_pc_plus_one),
      .clk(clk),
      .we(!stall),
      .gwe(gwe),
      .rst(rst)
   );


   // Define stall
   wire stall = (decode_out[16] | (decode_out[7] & !decode_out[15] & decode_out[6:4] == execute_decode[10:8]) | ((decode_out[2:0] == execute_decode[10:8]) & decode_out[3])) & execute_decode[14];

   // LC4 decoder
   lc4_decoder decoder (
      .insn(decode_insn), 
      .r1sel(decode_out[2:0]),
      .r1re(decode_out[3]),
      .r2sel(decode_out[6:4]),
      .r2re(decode_out[7]),
      .wsel(decode_out[10:8]),
      .regfile_we(decode_out[11]), 
      .nzp_we(decode_out[12]), 
      .select_pc_plus_one(decode_out[13]),
      .is_load(decode_out[14]), 
      .is_store(decode_out[15]), 
      .is_branch(decode_out[16]), 
      .is_control_insn(decode_out[17])
   );

   // LC4 register file
   lc4_regfile#(16) regfile (
      .clk(clk), 
      .gwe(gwe), 
      .rst(rst), 
      .i_rs(decode_out[2:0]), 
      .o_rs_data(decode_r1), 
      .i_rt(decode_out[6:4]), 
      .o_rt_data(decode_r2), 
      .i_rd(writeback[10:8]), 
      .i_wdata(writeback_rd), 
      .i_rd_we(writeback[11])
   );

   // D-Stage Register values
   assign decode_r1_out = (writeback[10:8] == decode_out[2:0] & writeback[11] & decode_out[3]) ? writeback_rd : decode_r1;
   assign decode_r2_out = (writeback[10:8] == decode_out[6:4] & writeback[11] & decode_out[7]) ? writeback_rd : decode_r2;

   // X-stage registers
   Nbit_reg #(16, 16'd0) execute_insn_pipe (
      .in(branch_taken ? 16'b0 : (stall ? 16'b1 : decode_insn)), 
      .out(execute_insn), 
      .clk(clk), 
      .we(1'b1), 
      .gwe(gwe),
      .rst(rst)
   );
   
   Nbit_reg #(16, INIT_PC) execute_pc_pipe (
      .in((stall | branch_taken) ? 16'b0 : decode_pc), 
      .out(execute_pc), 
      .clk(clk), 
      .we(1'b1), 
      .gwe(gwe),
      .rst(rst)
   );

   Nbit_reg #(16, 16'd0) execute_pcPlusOne_pipe (
      .in((branch_taken | stall) ? 16'b0 : decode_pc_plus_one), 
      .out(execute_pcPlusOne), 
      .clk(clk), 
      .we(1'b1), 
      .gwe(gwe), 
      .rst(rst)
   );

   Nbit_reg #(16, 16'd0) execute_r1_pipe (
      .in((branch_taken | stall) ? 16'b0 : decode_r1_out), 
      .out(execute_r1 ), 
      .clk(clk), 
      .we(1'b1), 
      .gwe(gwe), 
      .rst(rst)
   );

   Nbit_reg #(16, 16'd0) execute_r2_pipe (
      .in((branch_taken | stall) ? 16'b0 : decode_r2_out), 
      .out(execute_r2), 
      .clk(clk), 
      .we(1'b1), 
      .gwe(gwe), 
      .rst(rst)
   );

   Nbit_reg #(18, 18'd0) execute_decode_pipe (
      .in((branch_taken | stall) ? 18'b0 : decode_out), 
      .out(execute_decode), 
      .clk(clk), 
      .we(1'b1), 
      .gwe(gwe), 
      .rst(rst)
   );

   // X-stage register values
   assign execute_r1_final = (memory[10:8] == execute_decode[2:0] & !memory[14] & memory[11] & execute_decode[3]) ? memory_alu : ((writeback[10:8] == execute_decode[2:0] & writeback[11] & execute_decode[3]) ? writeback_rd : execute_r1 );
   assign execute_r2_final = (memory[10:8] == execute_decode[6:4] & !memory[14] & memory[11] & execute_decode[7]) ? memory_alu : ((writeback[10:8] == execute_decode[6:4] & writeback[11] & execute_decode[7]) ? writeback_rd : execute_r2);

   // ALU
   lc4_alu alu(
      .i_insn(execute_insn), 
      .i_pc(execute_pc), 
      .i_r1data(execute_r1_final), 
      .i_r2data(execute_r2_final ), 
      .o_result(execute_aluout)
   );

   // Branch Taken Wire
   wire branch_taken;
   assign branch_taken = execute_decode[17] | (execute_decode[16] & ((execute_insn[11:9] & (memory[12] ? nzp: nzp_memory)) != 3'b0));

   // M-stage registers
   Nbit_reg #(16, 16'd0) memory_insn_pipe (
      .in(execute_insn), 
      .out(memory_insn), 
      .clk(clk), 
      .we(1'b1), 
      .gwe(gwe), 
      .rst(rst)
   );
   
   Nbit_reg #(16, 16'h8200) memory_pc_pipe (
      .in(execute_pc), 
      .out(memory_pc), 
      .clk(clk), 
      .we(1'b1), 
      .gwe(gwe), 
      .rst(rst)
   );

   Nbit_reg #(16, 16'd0) memory_pcPlusOne_pipe (
      .in(execute_pcPlusOne),
      .out(memory_pcPlusOne),
      .clk(clk),
      .we(1'b1),
      .gwe(gwe),
      .rst(rst)
   );
   
   Nbit_reg #(16, 16'd0) memory_r2_pipe (
      .in(execute_r2_final ), 
      .out(memory_r2), 
      .clk(clk), 
      .we(1'b1), 
      .gwe(gwe),
      .rst(rst)
   );

   Nbit_reg #(18, 18'd0) memory_decode_pipe (
      .in(execute_decode), 
      .out(memory), 
      .clk(clk), 
      .we(1'b1), 
      .gwe(gwe), 
      .rst(rst)
   );

   Nbit_reg #(16, 16'd0) memory_alu_pipe (
      .in(execute_aluout),
      .out(memory_alu),
      .clk(clk),
      .we(1'b1),
      .gwe(gwe),
      .rst(rst)
   );

   // NZP register & calculations
   wire[2:0] nzp;
   assign nzp[0] = $signed(memory_rd) > 0;
   assign nzp[1] = $signed(memory_rd) == 0;
   assign nzp[2] = $signed(memory_rd) < 0;

   wire[15:0] memory_rd = memory[13] ? memory_pcPlusOne : (memory[14] ? i_cur_dmem_data : memory_alu);
   
   wire[2:0] nzp_memory;
   Nbit_reg #(3, 3'd0) nzp_pipe (
      .in(nzp),
      .out(nzp_memory),
      .clk(clk),
      .we(memory[12]),
      .gwe(gwe),
      .rst(rst)
   );
   

   // W-stage registers
   Nbit_reg #(16, 16'd0) writeback_insn_pipe (
      .in(memory_insn), 
      .out(writeback_insn), 
      .clk(clk), 
      .we(1'b1), 
      .gwe(gwe), 
      .rst(rst)
   );

   Nbit_reg #(16, 16'h8200) writeback_pc_pipe (
      .in(memory_pc), 
      .out(writeback_pc), 
      .clk(clk), 
      .we(1'b1), 
      .gwe(gwe), 
      .rst(rst)
   );

   Nbit_reg #(18, 18'd0) writeback_pipe (
      .in(memory), 
      .out(writeback), 
      .clk(clk), 
      .we(1'b1), 
      .gwe(gwe), 
      .rst(rst)
   );

   Nbit_reg #(16, 16'd0) writeback_rd_pipe (
      .in(memory_rd), 
      .out(writeback_rd), 
      .clk(clk), 
      .we(1'b1), 
      .gwe(gwe), 
      .rst(rst)
   );

   Nbit_reg #(16, 16'd0) writeback_dmem_pipe (
      .in(i_cur_dmem_data), 
      .out(writeback_dmem), 
      .clk(clk), 
      .we(1'b1), 
      .gwe(gwe), 
      .rst(rst)
   );

   Nbit_reg #(16, 16'd0) writeback_dmem_write_pipe (
      .in(o_dmem_towrite), 
      .out(writeback_dmem_write), 
      .clk(clk), 
      .we(1'b1), 
      .gwe(gwe), 
      .rst(rst)
   );

   Nbit_reg #(16, 16'd0) writeback_addr_pipe (
      .in(o_dmem_addr), 
      .out(writeback_addr), 
      .clk(clk), 
      .we(1'b1), 
      .gwe(gwe), 
      .rst(rst)
   );

   // Test signals
   assign o_cur_pc = pc;
   assign test_stall = (writeback_insn == 16'b0) ? 2'b10 : (writeback_insn == 16'b1 ? 2'b11 : 2'b00);
   assign test_cur_pc = writeback_pc;
   assign test_cur_insn = writeback_insn;
   assign test_regfile_we = writeback[11];
   assign test_regfile_wsel = writeback[10:8];
   assign test_regfile_data = writeback_rd;
   assign test_nzp_we = writeback[12];
   assign test_nzp_new_bits = nzp_memory;
   assign test_dmem_we = writeback[15];
   assign test_dmem_addr = writeback_addr;
   assign test_dmem_data = writeback[14] ? writeback_dmem : (writeback[15] ? writeback_dmem_write : 16'b0);
   assign o_dmem_addr = (memory[14] | memory[15]) ? memory_alu : 16'b0;
   assign o_dmem_we = memory[15];
   assign o_dmem_towrite = (memory[15] & writeback[11] & memory[6:4] == writeback[10:8]) ? writeback_rd : memory_r2;

`ifndef NDEBUG
   always @(posedge gwe) begin
      // $display("%d %h %h %h %h %h", $time, f_pc, decode_pc, e_pc, memory_pc, test_cur_pc);
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
      // run it for that many nano-seconds, then set
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
`endif
endmodule
