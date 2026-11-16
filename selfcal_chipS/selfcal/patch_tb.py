"""derive tb_est_sc.sv (self-calibration checks) from the baseline tb_est.sv."""
from pathlib import Path
H = Path(__file__).resolve().parent
s = (H.parent / 'src_snapshot/tb/tb_est.sv').read_text(encoding='utf-8')


def R(a, b, n=1):
    global s
    assert s.count(a) == n, (s.count(a), a[:80])
    s = s.replace(a, b)


R("""module tb_est;""", """// tb_est_sc: tb_est + self-calibration checks (selfcal/sc_vec.py vectors, run from reset):
//   exp_acc.hex  per bootstrap observation: N Sa Ss Saa Stx Sty Sbx Sby Stt m16 trig
//   exp_sol.hex  per solve: res N Sd T Bx By r2q10 ux uy lv state Qx Qy O10x O10y
//   cfg[53..58]  sc_en retry rot_t n_acc n_sol final sc_state
//   +RSTSOLVE    pulse rst 200 cycles into the first solve, restart the stream and all expectations
module tb_est_sc;""")
R("""  logic win_done, win_keyupd; logic [1:0] win_branch;""", """  logic win_done, win_keyupd; logic [1:0] win_branch;
  logic [1:0] sc_state, sc_lv; logic [2:0] sc_res; logic [9:0] sc_r2q10, sc_n; logic signed [15:0] sc_ux, sc_uy;
  logic sc_pub; logic signed [11:0] sc_px, sc_py;""")
R("""    .cfg_KA(cfg[23][23:0]), .cfg_KX(cfg[24][23:0]), .cfg_KY(cfg[25][23:0]), .cfg_BY16(cfg[26][15:0]),""",
  """    .cfg_KA(cfg[23][23:0]), .cfg_KX(cfg[24][23:0]), .cfg_KY(cfg[25][23:0]), .cfg_BY16(cfg[26][15:0]),
    .cfg_sc_en(cfg[53][0]), .cfg_sc_retry(cfg[54][0]), .cfg_rot_t(cfg[55][0]),
    .sc_state, .sc_res, .sc_lv, .sc_r2q10, .sc_ux, .sc_uy, .sc_n, .sc_pub, .sc_px, .sc_py,""")
R("""  int nwords, nframes, nwin, wi, fi, si, err_fp, err_win, err_sc, err_pl, fd_fp, fd_win, fd_sc;""",
  """  int nwords, nframes, nwin, wi, fi, si, err_fp, err_win, err_sc, err_pl, fd_fp, fd_win, fd_sc;
  int nacc, nsol, ai, soi, err_acc, err_sol, fd_acc, fd_sol, rst_done, n_rst;
  logic solve_seen, busy_d;
  longint unsigned cyc, cyc_boot_end;""")
# ---- self-calibration checkers appended before the main initial block
R("""  initial begin
    if (!$value$plusargs("VDIR=%s", vdir)) vdir = ".";""", """  // ---- self-calibration: accumulators 12 cycles after each observation (N increments), decisions at busy fall
  logic [9:0] n_last;
  always @(posedge clk) begin
    if (rst) begin n_last <= '0; solve_seen <= 1'b0; busy_d <= 1'b0; end
    else begin
      busy_d <= dut.u_sc.busy;
      if (dut.u_sc.bm_start) solve_seen <= 1'b1;
      if (dut.u_sc.N != n_last) begin
        n_last <= dut.u_sc.N;
        fork begin
          automatic logic [63:0] e [11]; automatic logic [63:0] g [11];
          repeat (16) @(posedge clk);
          for (int k = 0; k < 11; k++) void'($fscanf(fd_acc, "%h", e[k]));
          g[0] = 64'(dut.u_sc.N); g[1] = 64'(signed'(dut.u_sc.Sa)); g[2] = 64'(signed'(dut.u_sc.Ss)); g[3] = 64'(dut.u_sc.Saa);
          g[4] = 64'(signed'(dut.u_sc.Stx)); g[5] = 64'(signed'(dut.u_sc.Sty)); g[6] = 64'(signed'(dut.u_sc.Sbx)); g[7] = 64'(signed'(dut.u_sc.Sby));
          g[8] = 64'(dut.u_sc.Stt); g[9] = 64'(dut.u_sc.m16); g[10] = 64'(dut.u_sc.trig);
          for (int k = 0; k < 11; k++) if (g[k] !== e[k]) begin
            if (err_acc < 20) $display("ACC %0d field %0d: rtl %h exp %h", ai, k, g[k], e[k]);
            err_acc++;
          end
          ai++;
        end join_none
      end
      if (busy_d && !dut.u_sc.busy && solve_seen) begin
        logic [63:0] e [15]; logic [63:0] g [15];
        solve_seen <= 1'b0;
        for (int k = 0; k < 15; k++) void'($fscanf(fd_sol, "%h", e[k]));
        g[0] = 64'(sc_res); g[1] = 64'(dut.u_sc.N); g[2] = 64'(dut.u_sc.Sd); g[3] = 64'(dut.u_sc.T); g[4] = 64'(dut.u_sc.Bx);
        g[5] = 64'(dut.u_sc.By); g[6] = 64'(sc_r2q10); g[7] = 64'(signed'(sc_ux)); g[8] = 64'(signed'(sc_uy)); g[9] = 64'(sc_lv);
        g[10] = 64'(sc_state);
        g[11] = sc_pub ? 64'(signed'(sc_px)) : 64'd0; g[12] = sc_pub ? 64'(signed'(sc_py)) : 64'd0;
        g[13] = sc_pub ? 64'(signed'(dut.sc_O10x)) : 64'd0; g[14] = sc_pub ? 64'(signed'(dut.sc_O10y)) : 64'd0;
        for (int k = 0; k < 15; k++) if (g[k] !== e[k]) begin
          if (err_sol < 20) $display("SOL %0d field %0d: rtl %h exp %h", soi, k, g[k], e[k]);
          err_sol++;
        end
        $display("SOLVE %0d at window %0d: res %0d N %0d r2q10 %0d u (%0d,%0d) lv %0d state %0d pub %0d pivot (%0d,%0d) O10 (%0d,%0d)",
                 soi, wi, sc_res, dut.u_sc.N, sc_r2q10, sc_ux, sc_uy, sc_lv, sc_state, sc_pub, sc_px, sc_py, dut.sc_O10x, dut.sc_O10y);
        soi++;
      end
    end
  end
  // ---- reset during the first solve (+RSTSOLVE): restart stream and every expectation file
  always @(posedge clk) if (!rst && rst_done == 0 && n_rst > 0 && dut.u_sc.bm_start) begin
    rst_done = 1;
    fork begin
      repeat (200) @(posedge clk);
      $display("RSTSOLVE: reset asserted inside the solve at window %0d (sc busy %0d op %0d)", wi, dut.u_sc.busy, dut.u_sc.op);
      @(negedge clk); rst = 1;
      repeat (5) @(posedge clk);
      void'($rewind(fd_fp)); void'($rewind(fd_win)); void'($rewind(fd_sc)); void'($rewind(fd_acc)); void'($rewind(fd_sol));
      wi = 0; fi = 0; si = 0; ai = 0; soi = 0;
      @(negedge clk); rst = 0;
      $display("RSTSOLVE: released, stream restarted");
    end join_none
  end

  initial begin
    if (!$value$plusargs("VDIR=%s", vdir)) vdir = ".";""")
R("""    wi = 0; fi = 0; si = 0; err_fp = 0; err_win = 0; err_sc = 0; err_pl = 0;""",
  """    wi = 0; fi = 0; si = 0; err_fp = 0; err_win = 0; err_sc = 0; err_pl = 0;
    nacc = cfg[56]; nsol = cfg[57]; ai = 0; soi = 0; err_acc = 0; err_sol = 0; rst_done = 0;
    n_rst = $test$plusargs("RSTSOLVE") ? 1 : 0;
    fd_acc = $fopen({vdir, "/exp_acc.hex"}, "r"); fd_sol = $fopen({vdir, "/exp_sol.hex"}, "r");""")
R("""    $display("RESULT windows %0d/%0d frames_fp %0d/%0d score_windows %0d  mismatches: fp %0d win %0d sc %0d plane %0d  cycles %0d",
             wi, nwin, fi, nframes, si, err_fp, err_win, err_sc, err_pl, $time / 5);
    if (err_fp + err_win + err_sc + err_pl == 0) $display("PASS"); else $display("FAIL");""",
  """    if (ai != nacc) begin $display("ACC count rtl %0d exp %0d", ai, nacc); err_acc++; end
    if (soi != nsol) begin $display("SOL count rtl %0d exp %0d", soi, nsol); err_sol++; end
    if (sc_state !== cfg[58][1:0]) begin $display("final sc_state rtl %0d exp %0d", sc_state, cfg[58]); err_sol++; end
    $display("RESULT windows %0d/%0d frames_fp %0d/%0d score_windows %0d acc %0d/%0d solves %0d/%0d  mismatches: fp %0d win %0d sc %0d plane %0d acc %0d sol %0d  cycles %0d (clock 5 ns)",
             wi, nwin, fi, nframes, si, ai, nacc, soi, nsol, err_fp, err_win, err_sc, err_pl, err_acc, err_sol, $time / 5);
    if (err_fp + err_win + err_sc + err_pl + err_acc + err_sol == 0 && (n_rst == 0 || rst_done == 1)) $display("PASS"); else $display("FAIL");""")
R("""  initial begin #(64'd400_000_000); $display("TIMEOUT wi %0d fi %0d wp %0d", wi, fi, wp); $finish; end""",
  """  initial begin
    longint unsigned tmo;
    if (!$value$plusargs("TMO=%d", tmo)) tmo = 64'd4_000_000_000;
    #(tmo); $display("TIMEOUT wi %0d fi %0d wp %0d", wi, fi, wp); $finish;
  end
  // per-window cycle log (throughput; clock 5 ns so $time/5 is a true cycle count)
  always @(posedge clk) if (win_done && $test$plusargs("WINLOG"))
    $display("WINLOG %0d branch %0d L %0d n %0d mode %0d t %0d", wi, win_branch, dut.u_core.L, dut.u_core.n, dut.u_core.e_mode, $time / 5);""")
(H / 'tb/tb_est_sc.sv').write_text(s, encoding='utf-8')
print('ok')
