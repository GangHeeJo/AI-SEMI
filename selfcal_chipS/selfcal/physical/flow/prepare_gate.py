"""Adapt the preserved job25 gate TB generator without changing DUT RTL."""
from pathlib import Path
import subprocess,sys
P=Path('/home/aiasic26911/selfcal_20261115/phys')
C=P.parent/'code'
(P/'tb').mkdir(exist_ok=True)
for mode in ('legacy','selfcal'):
    src=(C/'tb/tb_chip_full_sc.sv').read_text()
    if mode=='legacy':
        for k in (53,54,55): src=src.replace('cfg[%d][0]'%k,"1'b0")
    src=src.replace('  string vdir;', '''  logic [1:0] sc_state, sc_lv;
  logic [2:0] sc_res;
  logic [9:0] sc_r2q10, sc_n;
  logic signed [15:0] sc_ux, sc_uy;
  logic signed [11:0] sc_px, sc_py;
  logic sc_pub;
  logic [63:0] sol_last [15];
  int fd_sol, dummy, err_status = 0;
  bit seen_pub = 0;
  string vdir;''')
    src=src.replace('    .frame_done,', '    .sc_state, .sc_lv, .sc_res, .sc_r2q10, .sc_n, .sc_ux, .sc_uy, .sc_px, .sc_py, .sc_pub,\n    .frame_done,')
    if mode=='selfcal':
        src=src.replace('    nwords = cfg[50];', '''    fd_sol = $fopen({vdir, "/exp_sol.hex"}, "r");
    if (!fd_sol) $fatal(1, "missing exp_sol");
    for (int s=0; s<cfg[57]; s++) for (int k=0; k<15; k++) begin
      dummy = $fscanf(fd_sol, "%h", sol_last[k]);
      if (dummy != 1) $fatal(1, "invalid exp_sol");
    end
    $fclose(fd_sol);
    nwords = cfg[50];''')
        src=src.replace('    $display("RESULT windows', '''    if (sc_state !== cfg[58][1:0] || sc_res !== sol_last[0][2:0] ||
        sc_n !== sol_last[1][9:0] || sc_r2q10 !== sol_last[6][9:0] ||
        sc_ux !== sol_last[7][15:0] || sc_uy !== sol_last[8][15:0] ||
        sc_lv !== sol_last[9][1:0] || sc_px !== sol_last[11][11:0] || sc_py !== sol_last[12][11:0] || !seen_pub)
      err_status++;
    $display("SELFCAL_FINAL state %0d res %0d N %0d r2 %0d u (%0d,%0d) pivot (%0d,%0d) seen_pub %0d errors %0d",
      sc_state, sc_res, sc_n, sc_r2q10, sc_ux, sc_uy, sc_px, sc_py, seen_pub, err_status);
    $display("RESULT windows''')
    src=src.replace('if (err_fp + err_win + err_mem == 0)', 'if (err_fp + err_win + err_mem + err_status == 0)')
    src=src.replace('else $display("FAIL");', 'else $fatal(1, "FAIL");')
    inp=P/'tb'/('input_%s.sv'%mode);out=P/'tb'/('gate_%s.sv'%mode)
    inp.write_text(src)
    subprocess.check_call([sys.executable,str(P/'flow/gen_gate_tb.py'),str(inp),str(out)])
    t=out.read_text().replace('always #2.75 clk = ~clk;', 'always #4.0 clk = ~clk;')
    t=t.replace('$time / 5','pcyc')
    t=t.replace('dut.u_est_u_core.', 'dut.u_est.u_core.')
    t=t.replace('if (pcyc % 20000 == 0)', 'if (pcyc % 1000000 == 0)')
    # Terminate a stalled run instead of burning hours on a known non-progressing state.
    t=t.replace('endmodule', '''  int last_wp = -1, last_wi = -1, last_nfd = -1, stagnant = 0;
  realtime previous_edge = 0;
  always @(posedge clk) begin
    if (previous_edge != 0 && $realtime - previous_edge != 8.0) $fatal(1, "CLOCK_NOT_8NS");
    previous_edge = $realtime;
    if (!rst) begin
      if (sc_pub) seen_pub = 1;
      if (wp == last_wp && wi == last_wi && nfd == last_nfd) stagnant++;
      else stagnant = 0;
      last_wp = wp; last_wi = wi; last_nfd = nfd;
      if (stagnant > 2000000) $fatal(1, "STALL cycles %0d wi %0d wp %0d", pcyc, wi, wp);
    end
  end
endmodule''')
    assert 'always #4.0 clk' in t and '$time / 5' not in t
    assert 'dut.u_est.u_core.q' not in t
    out.write_text(t)
print('Generated legacy/selfcal gate TBs, explicit 8ns, real cycle counter, status checks and stall watchdog.')
