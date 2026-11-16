# generate tb_chip_full_gate.sv (gate-level + SDF) from tb_chip_full.sv. usage: python3 gen_gate_tb.py tb_chip_full.sv out.sv
import sys,re
src=open(sys.argv[1]).read()
NW=1200; NBK=(NW+127)//128
# 1. DUT without parameters
src=src.replace("chip_s_full #(.SW(SW), .SH(SH), .PW(PW), .NW(NW), .AW(AW), .REC(REC), .SHQ(SHQ)) dut","chip_s_full dut")
# 2. clock 5.5 ns
src=src.replace("always #2.5 clk = ~clk;","always #2.75 clk = ~clk;")
# 3. inputs launched TIN after the clock edge (hold safety against SDF)
src=src.replace("w_valid <= (w_valid && w_ready) ? (wp + 1 < nwords) : (wp < nwords);","w_valid <= #1.0 (w_valid && w_ready) ? (wp + 1 < nwords) : (wp < nwords);")
src=src.replace("if (rst) begin wp <= 0; w_valid <= 1'b0; end","if (rst) begin wp <= 0; w_valid <= #1.0 1'b0; end")
src=src.replace("assign w_data = words[wp];","assign #1.0 w_data = words[wp];")
# 3b. TB-side timing: every DUT input (dbg_*, rst) changes 1 ns after a clock edge like the SDC input_delay, not at the negedge
src=src.replace("@(negedge clk); dbg_en = 1; dbg_we = 1;","@(posedge clk); #1.0; dbg_en = 1; dbg_we = 1;")
src=src.replace("@(negedge clk); dbg_en = 0; dbg_we = 0;","@(posedge clk); #1.0; dbg_en = 0; dbg_we = 0;")
src=src.replace("repeat (3) @(posedge clk);","repeat (3) @(posedge clk); #1.0;")
src=src.replace("->ld_ev; #1;","->ld_ev; #0.1; rst = 0; /*")
src=src.replace("@(negedge clk); rst = 0;","*/")
src=src.replace("@(negedge clk); dbg_en = 1; dbg_we = 0;","@(posedge clk); #1.0; dbg_en = 1; dbg_we = 0;")
src=src.replace("@(negedge clk); dbg_en = 0;\n","@(posedge clk); #1.0; dbg_en = 0; @(posedge clk); #1.0;\n")
# 3c. let the clock-gating latches resolve out of X before the first world-memory zeroing write (otherwise word 0 of bank 0 is lost at MAX)
src=src.replace("// world memory <- 0 through the test port (during reset)","repeat (4) @(posedge clk); repeat (2) begin @(posedge clk); #1.0; dbg_en = 1; dbg_we = 1; dbg_bank = 0; dbg_addr = 0; dbg_wdata = '0; end")
# 4. window check without hierarchical taps into flattened registers
src=re.sub(r"if \(win_branch !== e\[0\]\[1:0\] \|\| win_keyupd !== e\[1\]\[0\] \|\|.*?\) begin",
           "if (win_branch !== e[0][1:0] || win_keyupd !== e[1][0]) begin",src,flags=re.S)
# 5. plane preload through generated hierarchical names
a=src.index("  genvar gp, gb;"); b=src.index("  int wp;")
lines=["  // gate level: plane banks and valid bits preloaded through hierarchical names of the flattened netlist"]
lines.append("  initial begin @(ld_ev);")
for gp in range(3):
    lines.append(f"    if (img_on[{gp}]) begin")
    for gb in range(NBK):
        lines.append(f"      for (int a = 0; a < 128; a++) if ({gb}*128 + a < NW) dut.u_est_u_core.\g_pl[{gp}].u_pl_g_bank[{gb}].u_bank .m[a] = img[{gp}][{gb}*128 + a];")
    for i in range(NW):
        lines.append(f"      $deposit(dut.u_est_u_core.\g_pl[{gp}].u_pl_v_reg[{i}] .int_fwire_N30, 1'b1);")
    lines.append("    end")
lines.append("  end")
src=src[:a]+"\n".join(lines)+"\n"+src[b:]
# 6. SDF annotation
src=src.replace("  string vdir;","  string vdir;\n  initial $sdf_annotate(`SDF, dut, , \"sdf.log\", `SDFMODE);",1)
open(sys.argv[2],'w').write(src)
# progress print every 20000 cycles
s2=open(sys.argv[2]).read()
s2=s2.replace("endmodule","  int pcyc = 0;\n  always @(posedge clk) begin pcyc++; if (pcyc % 20000 == 0) $display(\"PROG cyc %0d wi %0d fi %0d nfd %0d wp %0d / %0d\", pcyc, wi, fi, nfd, wp, nwords); end\nendmodule")
open(sys.argv[2],'w').write(s2)
# debug probe (env GATE_PROBE=1): count X words in the 16 world macros right after the TB zeroing, and at 3 us later
import os
if os.environ.get("GATE_PROBE"):
    s3=open(sys.argv[2]).read()
    p="  initial begin @(ld_ev); #20; probe(\"after_zero\"); #3000; probe(\"stall\"); end\n  task automatic probe(input string tag); int nx; logic [63:0] w;\n"
    for b in range(16):
        p+=f"    nx=0; for (int a=0;a<128;a++) begin w=dut.\\u_mem_g_bank[{b}].u_bank .m[a]; if ($isunknown(w)) begin nx++; $display(\"PROBE xaddr bank{b} %0d\", a); end end $display(\"PROBE %s bank{b} xwords %0d rdata %h\", tag, nx, dut.\\u_mem_g_bank[{b}].u_bank .rdata);\n"
    for b in (0, 1, 2):
        p+=f"    $display(\"PROBE %s ifc bank{b} en %b we %b addr %h clk %b\", tag, dut.\\u_mem_g_bank[{b}].u_bank .en, dut.\\u_mem_g_bank[{b}].u_bank .we, dut.\\u_mem_g_bank[{b}].u_bank .addr, dut.\\u_mem_g_bank[{b}].u_bank .clk);\n"
    p+="  endtask\n"
    s3=s3.replace("endmodule",p+"endmodule")
    open(sys.argv[2],'w').write(s3)
