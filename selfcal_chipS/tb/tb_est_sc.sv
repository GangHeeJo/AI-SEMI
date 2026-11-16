// job24: estimator RTL vs golden (results/job24_vec.py vectors in VDIR).
//   cfg.hex      configuration + initial state + stream info (one 64-bit two's-complement value per line)
//   words.hex    professor group-AER words of the segment
//   exp_fp.hex   per frame: cs sn b0x b0y
//   exp_win.hex  per window: branch keyupd L n q0..2 v0..2 qr0..2 qk0..2 haskey
//   exp_sc.hex   per scoring window: sc[0..26] ks[0..26]
//   plane_{prev,key}{,_end}.hex  NW x 64 bit
`timescale 1ns/1ps
// tb_est_sc: tb_est + self-calibration checks (selfcal/sc_vec.py vectors, run from reset):
//   exp_acc.hex  per bootstrap observation: N Sa Ss Saa Stx Sty Sbx Sby Stt m16 trig
//   exp_sol.hex  per solve: res N Sd T Bx By r2q10 ux uy lv state Qx Qy O10x O10y
//   cfg[53..58]  sc_en retry rot_t n_acc n_sol final sc_state
//   +RSTSOLVE    pulse rst 200 cycles into the first solve, restart the stream and all expectations
module tb_est_sc;
`ifdef UZH
  localparam int SW = 240, SH = 180, PW = 80, NW = 75, AW = 7, REC = 171, SHQ = 9;
`else
  localparam int SW = 960, SH = 720, PW = 320, NW = 1200, AW = 11, REC = 683, SHQ = 11;
`endif
  logic clk = 0, rst = 1;
  always #2.5 clk = ~clk;
  logic [63:0] cfg [64];
  logic [31:0] words [];
  logic w_valid, w_ready; logic [31:0] w_data;
  logic fp_valid, fp_ready; logic signed [11:0] fp_cs, fp_sn; logic signed [27:0] fp_b0x, fp_b0y;
  logic win_done, win_keyupd; logic [1:0] win_branch;
  logic [1:0] sc_state, sc_lv; logic [2:0] sc_res; logic [9:0] sc_r2q10, sc_n; logic signed [15:0] sc_ux, sc_uy;
  logic sc_pub; logic signed [11:0] sc_px, sc_py;
  string vdir;
  est_top #(.SW(SW), .SH(SH), .PW(PW), .NW(NW), .AW(AW), .REC(REC), .SHQ(SHQ)) dut (.clk, .rst,
    .init_col_x(cfg[47][10:0]), .init_col_ok(cfg[48][0]), .init_dir(cfg[49][0]),
    .w_valid, .w_ready, .w_data,
    .cfg_mode(cfg[0][1:0]), .cfg_px(cfg[1][11:0]), .cfg_py(cfg[2][11:0]), .cfg_d0(cfg[3][15:0]), .cfg_d1(cfg[4][15:0]),
    .cfg_d2(cfg[5][15:0]), .cfg_min_ev(cfg[6][23:0]), .cfg_thr0(cfg[7][15:0]), .cfg_thr1(cfg[8][15:0]), .cfg_thr2(cfg[9][15:0]),
    .cfg_keyw(cfg[10][3:0]), .cfg_qi0(cfg[11][31:0]), .cfg_qi1(cfg[12][31:0]), .cfg_qi2(cfg[13][31:0]), .cfg_an(cfg[14][3:0]),
    .cfg_wk_l2(cfg[15][1:0]), .cfg_Lfix(cfg[16][3:0]), .cfg_slowL(cfg[17][3:0]), .cfg_slow_div(cfg[18][3:0]),
    .cfg_wPx(cfg[19][11:0]), .cfg_wPy(cfg[20][11:0]), .cfg_wOx(cfg[21][11:0]), .cfg_wOy(cfg[22][11:0]),
    .cfg_KA(cfg[23][23:0]), .cfg_KX(cfg[24][23:0]), .cfg_KY(cfg[25][23:0]), .cfg_BY16(cfg[26][15:0]),
    .cfg_sc_en(cfg[53][0]), .cfg_sc_retry(cfg[54][0]), .cfg_rot_t(cfg[55][0]),
    .sc_state, .sc_res, .sc_lv, .sc_r2q10, .sc_ux, .sc_uy, .sc_n, .sc_pub, .sc_px, .sc_py,
    .init_started(cfg[27][0]), .init_haskey(cfg[28][0]), .init_preroll(cfg[29][0]),
    .init_q0(cfg[30][31:0]), .init_q1(cfg[31][31:0]), .init_q2(cfg[32][31:0]),
    .init_v0(cfg[33][31:0]), .init_v1(cfg[34][31:0]), .init_v2(cfg[35][31:0]),
    .init_qr0(cfg[36][31:0]), .init_qr1(cfg[37][31:0]), .init_qr2(cfg[38][31:0]),
    .init_qk0(cfg[39][31:0]), .init_qk1(cfg[40][31:0]), .init_qk2(cfg[41][31:0]),
    .init_nprev(cfg[42][23:0]), .init_Lp(cfg[43][3:0]), .init_cur(cfg[44][1:0]), .init_prev(cfg[45][1:0]), .init_key(cfg[46][1:0]),
    .fp_valid, .fp_ready, .fp_cs, .fp_sn, .fp_b0x, .fp_b0y, .win_done, .win_branch, .win_keyupd);

  int nwords, nframes, nwin, wi, fi, si, err_fp, err_win, err_sc, err_pl, fd_fp, fd_win, fd_sc;
  int nacc, nsol, ai, soi, err_acc, err_sol, fd_acc, fd_sol, rst_done, n_rst;
  logic solve_seen, busy_d;
  longint unsigned cyc, cyc_boot_end;
  logic [63:0] pl_tmp [NW];
  assign fp_ready = 1'b1;

  // plane images (prev / key at the segment start), copied into the macro banks by per-bank generate blocks
  localparam int NBK = (NW + 127) / 128;
  logic [63:0] img [3][NW];
  logic [2:0]  img_on;
  event ld_ev;
  task automatic load_plane(input int id, input string fn);
    $readmemh(fn, pl_tmp);
    for (int i = 0; i < NW; i++) img[id][i] = pl_tmp[i];
    img_on[id] = 1'b1;
  endtask
  genvar gp, gb;
  generate for (gp = 0; gp < 3; gp++) begin : g_ldp
    for (gb = 0; gb < NBK; gb++) begin : g_ldb
      initial begin
        @(ld_ev);
        if (img_on[gp]) for (int a = 0; a < 128; a++) if (gb * 128 + a < NW)
          dut.u_core.g_pl[gp].u_pl.g_bank[gb].u_bank.m[a] = img[gp][gb * 128 + a];
      end
    end
    initial begin @(ld_ev); #0; if (img_on[gp]) dut.u_core.g_pl[gp].u_pl.v = '1; end
  end endgenerate
  // read back through the generate blocks
  logic [63:0] rb [3][NW];
  event rb_ev;
  generate for (gp = 0; gp < 3; gp++) begin : g_rbp
    for (gb = 0; gb < NBK; gb++) begin : g_rbb
      always @(rb_ev) for (int a = 0; a < 128; a++) if (gb * 128 + a < NW)
        rb[gp][gb * 128 + a] = dut.u_core.g_pl[gp].u_pl.v[gb * 128 + a] ? dut.u_core.g_pl[gp].u_pl.g_bank[gb].u_bank.m[a] : 64'd0;
    end
  end endgenerate
  function automatic logic [63:0] plw(input int id, input int i);
    return rb[id][i];
  endfunction
  task automatic check_plane(input int id, input string fn, input string nm);
    int bad = 0;
    $readmemh(fn, pl_tmp);
    for (int i = 0; i < NW; i++) if (plw(id, i) !== pl_tmp[i]) bad++;
    if (bad) $display("PLANE %s mismatch words %0d", nm, bad);
    err_pl += bad;
  endtask

  // ---- word feeder
  int wp;
  always_ff @(posedge clk) begin
    if (rst) begin wp <= 0; w_valid <= 1'b0; end
    else begin
      if (w_valid && w_ready) wp <= wp + 1;
      w_valid <= (w_valid && w_ready) ? (wp + 1 < nwords) : (wp < nwords);
    end
  end
  assign w_data = words[wp];

  // ---- checkers
  always @(posedge clk) if (!rst) begin
    if (fp_valid && fp_ready) begin
      logic [31:0] e_cs, e_sn, e_bx, e_by;
      void'($fscanf(fd_fp, "%h %h %h %h\n", e_cs, e_sn, e_bx, e_by));
      if (fp_cs !== e_cs[11:0] || fp_sn !== e_sn[11:0] || fp_b0x !== e_bx[27:0] || fp_b0y !== e_by[27:0]) begin
        if (err_fp < 10) $display("FP %0d: rtl %h %h %h %h exp %h %h %h %h", fi, fp_cs, fp_sn, fp_b0x, fp_b0y, e_cs[11:0], e_sn[11:0], e_bx[27:0], e_by[27:0]);
        err_fp++;
      end
      fi++;
    end
    if (win_done) begin
      logic [31:0] e [17];
      logic [31:0] got [17];
      for (int k = 0; k < 17; k++) void'($fscanf(fd_win, "%h", e[k]));
      got[0] = win_branch; got[1] = win_keyupd; got[2] = dut.u_core.L; got[3] = dut.u_core.n;
      for (int k = 0; k < 3; k++) begin
        got[4 + k] = dut.u_core.q[k]; got[7 + k] = dut.u_core.v[k]; got[10 + k] = dut.u_core.qr[k]; got[13 + k] = dut.u_core.qk[k];
      end
      got[16] = dut.u_core.haskey;
      for (int k = 0; k < 17; k++) if (got[k] !== e[k]) begin
        if (err_win < 20) $display("WIN %0d field %0d: rtl %h exp %h", wi, k, got[k], e[k]);
        err_win++;
      end
      if (win_branch == 2'd3) begin
        logic [31:0] es;
        for (int k = 0; k < 27; k++) begin void'($fscanf(fd_sc, "%h", es)); if (dut.u_core.sc[k] !== es[11:0]) err_sc++; end
        for (int k = 0; k < 27; k++) begin void'($fscanf(fd_sc, "%h", es)); if (dut.u_core.ks[k] !== es[11:0]) err_sc++; end
        si++;
      end
      wi++;
    end
  end

  // ---- self-calibration: accumulators 12 cycles after each observation (N increments), decisions at busy fall
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
    if (!$value$plusargs("VDIR=%s", vdir)) vdir = ".";
    $readmemh({vdir, "/cfg.hex"}, cfg);
    nwords = cfg[50]; nframes = cfg[51]; nwin = cfg[52];
    words = new[nwords];
    $readmemh({vdir, "/words.hex"}, words);
    fd_fp = $fopen({vdir, "/exp_fp.hex"}, "r"); fd_win = $fopen({vdir, "/exp_win.hex"}, "r"); fd_sc = $fopen({vdir, "/exp_sc.hex"}, "r");
    wi = 0; fi = 0; si = 0; err_fp = 0; err_win = 0; err_sc = 0; err_pl = 0;
    nacc = cfg[56]; nsol = cfg[57]; ai = 0; soi = 0; err_acc = 0; err_sol = 0; rst_done = 0;
    n_rst = $test$plusargs("RSTSOLVE") ? 1 : 0;
    fd_acc = $fopen({vdir, "/exp_acc.hex"}, "r"); fd_sol = $fopen({vdir, "/exp_sol.hex"}, "r");
    repeat (3) @(posedge clk);
    img_on = '0;
    load_plane(cfg[45], {vdir, "/plane_prev.hex"});
    if (cfg[46] != cfg[45] && cfg[28][0]) load_plane(cfg[46], {vdir, "/plane_key.hex"});
    ->ld_ev; #1;
    @(negedge clk); rst = 0;
    wait (wi == nwin);
    repeat (5) @(posedge clk);
    ->rb_ev; #1;
    check_plane(dut.u_core.prev_id, {vdir, "/plane_prev_end.hex"}, "prev");
    if (dut.u_core.haskey) check_plane(dut.u_core.key_id, {vdir, "/plane_key_end.hex"}, "key");
    if (ai != nacc) begin $display("ACC count rtl %0d exp %0d", ai, nacc); err_acc++; end
    if (soi != nsol) begin $display("SOL count rtl %0d exp %0d", soi, nsol); err_sol++; end
    if (sc_state !== cfg[58][1:0]) begin $display("final sc_state rtl %0d exp %0d", sc_state, cfg[58]); err_sol++; end
    $display("RESULT windows %0d/%0d frames_fp %0d/%0d score_windows %0d acc %0d/%0d solves %0d/%0d  mismatches: fp %0d win %0d sc %0d plane %0d acc %0d sol %0d  cycles %0d (clock 5 ns)",
             wi, nwin, fi, nframes, si, ai, nacc, soi, nsol, err_fp, err_win, err_sc, err_pl, err_acc, err_sol, $time / 5);
    if (err_fp + err_win + err_sc + err_pl + err_acc + err_sol == 0 && (n_rst == 0 || rst_done == 1)) $display("PASS"); else $display("FAIL");
    $finish;
  end
  initial begin
    longint unsigned tmo;
    if (!$value$plusargs("TMO=%d", tmo)) tmo = 64'd4_000_000_000;
    #(tmo); $display("TIMEOUT wi %0d fi %0d wp %0d", wi, fi, wp); $finish;
  end
  // per-window cycle log (throughput; clock 5 ns so $time/5 is a true cycle count)
  always @(posedge clk) if (win_done && $test$plusargs("WINLOG"))
    $display("WINLOG %0d branch %0d L %0d n %0d mode %0d t %0d", wi, win_branch, dut.u_core.L, dut.u_core.n, dut.u_core.e_mode, $time / 5);
endmodule
