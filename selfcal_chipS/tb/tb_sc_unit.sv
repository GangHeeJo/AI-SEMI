// est_selfcal stand-alone edge-case test (selfcal/sc_unit_vec.py vectors, expected values from sc_model.SelfCal).
//   cfg.hex  en retry px py wPx wPy wOx wOy n_obs n_acc n_sol final_state
//   obs.hex  branch q0 q1 q2 (one estimator window end per line; a new one is issued only while the block is idle)
`timescale 1ns/1ps
module tb_sc_unit;
  logic clk = 0, rst = 1;
  always #2.5 clk = ~clk;
  logic [63:0] cfg [16];
  logic [63:0] obs [4096][4];
  logic win_done; logic [1:0] win_branch; logic signed [31:0] q0, q1, q2;
  logic busy, pub, pub_set; logic signed [11:0] pub_px, pub_py; logic signed [27:0] pub_O10x, pub_O10y;
  logic [1:0] sc_state, sc_lv; logic [2:0] sc_res; logic [9:0] sc_r2q10, sc_n; logic signed [15:0] sc_ux, sc_uy;
  est_selfcal #(.SW(960)) dut (.clk, .rst, .en(cfg[0][0]), .retry(cfg[1][0]), .cfg_px(cfg[2][11:0]), .cfg_py(cfg[3][11:0]),
    .cfg_wPx(cfg[4][11:0]), .cfg_wPy(cfg[5][11:0]), .cfg_wOx(cfg[6][11:0]), .cfg_wOy(cfg[7][11:0]),
    .win_done, .win_branch, .q0, .q1, .q2, .busy, .pub, .pub_set, .pub_px, .pub_py, .pub_O10x, .pub_O10y,
    .sc_state, .sc_res, .sc_lv, .sc_r2q10, .sc_ux, .sc_uy, .sc_n);
  string vdir;
  int fd_acc, fd_sol, nobs, ai, soi, err_acc, err_sol, npubset;
  logic solve_seen, busy_d;
  always @(posedge clk) if (!rst && pub_set) npubset++;
  task automatic check_acc();
    logic [63:0] e [11]; logic [63:0] g [11];
    for (int k = 0; k < 11; k++) void'($fscanf(fd_acc, "%h", e[k]));
    g[0] = 64'(dut.N); g[1] = 64'(signed'(dut.Sa)); g[2] = 64'(signed'(dut.Ss)); g[3] = 64'(dut.Saa);
    g[4] = 64'(signed'(dut.Stx)); g[5] = 64'(signed'(dut.Sty)); g[6] = 64'(signed'(dut.Sbx)); g[7] = 64'(signed'(dut.Sby));
    g[8] = 64'(dut.Stt); g[9] = 64'(dut.m16); g[10] = 64'(dut.trig);
    for (int k = 0; k < 11; k++) if (g[k] !== e[k]) begin
      if (err_acc < 10) $display("ACC %0d field %0d: rtl %h exp %h", ai, k, g[k], e[k]);
      err_acc++;
    end
    ai++;
  endtask
  task automatic check_sol();
    logic [63:0] e [15]; logic [63:0] g [15];
    for (int k = 0; k < 15; k++) void'($fscanf(fd_sol, "%h", e[k]));
    g[0] = 64'(sc_res); g[1] = 64'(dut.N); g[2] = 64'(dut.Sd); g[3] = 64'(dut.T); g[4] = 64'(dut.Bx); g[5] = 64'(dut.By);
    g[6] = 64'(sc_r2q10); g[7] = 64'(signed'(sc_ux)); g[8] = 64'(signed'(sc_uy)); g[9] = 64'(sc_lv); g[10] = 64'(sc_state);
    g[11] = pub ? 64'(signed'(pub_px)) : 64'd0; g[12] = pub ? 64'(signed'(pub_py)) : 64'd0;
    g[13] = pub ? 64'(signed'(pub_O10x)) : 64'd0; g[14] = pub ? 64'(signed'(pub_O10y)) : 64'd0;
    for (int k = 0; k < 15; k++) if (g[k] !== e[k]) begin
      if (err_sol < 10) $display("SOL %0d field %0d: rtl %h exp %h", soi, k, g[k], e[k]);
      err_sol++;
    end
    $display("SOLVE %0d: res %0d N %0d r2q10 %0d u (%0d,%0d) lv %0d state %0d pub %0d Q (%0d,%0d)", soi, sc_res, dut.N, sc_r2q10,
             sc_ux, sc_uy, sc_lv, sc_state, pub, pub_px, pub_py);
    soi++;
  endtask
  initial begin
    if (!$value$plusargs("VDIR=%s", vdir)) vdir = ".";
    $readmemh({vdir, "/cfg.hex"}, cfg);
    nobs = cfg[8];
    begin
      int fd; fd = $fopen({vdir, "/obs.hex"}, "r");
      for (int i = 0; i < nobs; i++) for (int k = 0; k < 4; k++) void'($fscanf(fd, "%h", obs[i][k]));
      $fclose(fd);
    end
    fd_acc = $fopen({vdir, "/exp_acc.hex"}, "r"); fd_sol = $fopen({vdir, "/exp_sol.hex"}, "r");
    ai = 0; soi = 0; err_acc = 0; err_sol = 0; npubset = 0;
    win_done = 0; win_branch = 0; q0 = 0; q1 = 0; q2 = 0;
    repeat (4) @(posedge clk); @(negedge clk); rst = 0;
    repeat (3) @(posedge clk);
    for (int i = 0; i < nobs; i++) begin
      logic [9:0] n0; logic bm;
      @(negedge clk);
      while (busy) @(negedge clk);
      n0 = dut.N;
      win_branch = obs[i][0][1:0]; q0 = obs[i][1][31:0]; q1 = obs[i][2][31:0]; q2 = obs[i][3][31:0]; win_done = 1;
      @(negedge clk); win_done = 0;
      bm = 0;
      while (busy) begin @(negedge clk); if (dut.bm_busy) bm = 1; end
      if (dut.N != n0) check_acc();
      if (bm) check_sol();
    end
    repeat (5) @(posedge clk);
    if (ai != cfg[9]) begin $display("ACC count rtl %0d exp %0d", ai, cfg[9]); err_acc++; end
    if (soi != cfg[10]) begin $display("SOL count rtl %0d exp %0d", soi, cfg[10]); err_sol++; end
    if (sc_state !== cfg[11][1:0]) begin $display("final state rtl %0d exp %0d", sc_state, cfg[11]); err_sol++; end
    if (npubset != (pub ? 1 : 0)) begin $display("pub_set pulses %0d with pub %0d", npubset, pub); err_sol++; end
    $display("RESULT obs %0d acc %0d/%0d solves %0d/%0d  mismatches: acc %0d sol %0d", nobs, ai, cfg[9], soi, cfg[10], err_acc, err_sol);
    if (err_acc + err_sol == 0) $display("PASS"); else $display("FAIL");
    $finish;
  end
  initial begin #(64'd200_000_000); $display("TIMEOUT"); $finish; end
endmodule
