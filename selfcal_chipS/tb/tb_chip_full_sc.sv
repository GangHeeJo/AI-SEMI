// job24: chip_s_full end to end (estimator -> transform -> world) vs golden on a job24 vector segment.
// Checks: per-frame params (exp_fp.hex), per-window estimator state (exp_win.hex), final world memory
// (mem_final_w.hex from job24_world.py, world starts at zero, LFSR 0xACE1). +VDIR=<segment dir>
`timescale 1ns/1ps
module tb_chip_full_sc;
  localparam int SW = 960, SH = 720, PW = 320, NW = 1200, AW = 11, REC = 683, SHQ = 11;
  logic clk = 0, rst = 1;
  always #2.5 clk = ~clk;
  logic [63:0] cfg [64]; logic [63:0] wg [8];
  logic [31:0] words [];
  logic w_valid, w_ready; logic [31:0] w_data;
  logic frame_done, win_done, win_keyupd, fp_fire; logic [1:0] win_branch; logic [31:0] n_rd, n_wr;
  logic signed [11:0] fcs, fsn; logic signed [27:0] fbx, fby;
  logic dbg_en = 0, dbg_we = 0; logic [3:0] dbg_bank; logic [6:0] dbg_addr; logic [63:0] dbg_wdata = '0, dbg_rdata;
  string vdir;
  chip_s_full #(.SW(SW), .SH(SH), .PW(PW), .NW(NW), .AW(AW), .REC(REC), .SHQ(SHQ)) dut (.clk, .rst,
    .init_col_x(cfg[47][10:0]), .init_col_ok(cfg[48][0]), .init_dir(cfg[49][0]), .init_lfsr(16'hACE1),
    .cfg_x0(wg[0][15:0]), .cfg_y0(wg[1][15:0]), .cfg_w(wg[2][8:0]), .cfg_h(wg[3][8:0]), .cfg_cm(1'b0),
    .w_valid, .w_ready, .w_data,
    .cfg_mode(cfg[0][1:0]), .cfg_px(cfg[1][11:0]), .cfg_py(cfg[2][11:0]), .cfg_d0(cfg[3][15:0]), .cfg_d1(cfg[4][15:0]),
    .cfg_d2(cfg[5][15:0]), .cfg_min_ev(cfg[6][23:0]), .cfg_thr0(cfg[7][15:0]), .cfg_thr1(cfg[8][15:0]), .cfg_thr2(cfg[9][15:0]),
    .cfg_keyw(cfg[10][3:0]), .cfg_qi0(cfg[11][31:0]), .cfg_qi1(cfg[12][31:0]), .cfg_qi2(cfg[13][31:0]), .cfg_an(cfg[14][3:0]),
    .cfg_wk_l2(cfg[15][1:0]), .cfg_Lfix(cfg[16][3:0]), .cfg_slowL(cfg[17][3:0]), .cfg_slow_div(cfg[18][3:0]),
    .cfg_wPx(cfg[19][11:0]), .cfg_wPy(cfg[20][11:0]), .cfg_wOx(cfg[21][11:0]), .cfg_wOy(cfg[22][11:0]),
    .cfg_KA(cfg[23][23:0]), .cfg_KX(cfg[24][23:0]), .cfg_KY(cfg[25][23:0]), .cfg_BY16(cfg[26][15:0]), .cfg_sc_en(cfg[53][0]), .cfg_sc_retry(cfg[54][0]), .cfg_rot_t(cfg[55][0]),
    .init_started(cfg[27][0]), .init_haskey(cfg[28][0]), .init_preroll(cfg[29][0]),
    .init_q0(cfg[30][31:0]), .init_q1(cfg[31][31:0]), .init_q2(cfg[32][31:0]),
    .init_v0(cfg[33][31:0]), .init_v1(cfg[34][31:0]), .init_v2(cfg[35][31:0]),
    .init_qr0(cfg[36][31:0]), .init_qr1(cfg[37][31:0]), .init_qr2(cfg[38][31:0]),
    .init_qk0(cfg[39][31:0]), .init_qk1(cfg[40][31:0]), .init_qk2(cfg[41][31:0]),
    .init_nprev(cfg[42][23:0]), .init_Lp(cfg[43][3:0]), .init_cur(cfg[44][1:0]), .init_prev(cfg[45][1:0]), .init_key(cfg[46][1:0]),
    .frame_done, .n_rd, .n_wr, .win_done, .win_branch, .win_keyupd, .fp_fire, .fp_cs_o(fcs), .fp_sn_o(fsn), .fp_b0x_o(fbx), .fp_b0y_o(fby),
    .dbg_en, .dbg_we, .dbg_bank, .dbg_addr, .dbg_wdata, .dbg_rdata);

  int nwords, nframes, nwin, wi, fi, nfd, err_fp, err_win, err_mem, fd_fp, fd_win;
  logic [63:0] pl_tmp [NW]; logic [63:0] mexp [16*128];

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
          dut.u_est.u_core.g_pl[gp].u_pl.g_bank[gb].u_bank.m[a] = img[gp][gb * 128 + a];
      end
    end
    initial begin @(ld_ev); #0; if (img_on[gp]) dut.u_est.u_core.g_pl[gp].u_pl.v = '1; end
  end endgenerate

  int wp;
  always_ff @(posedge clk) begin
    if (rst) begin wp <= 0; w_valid <= 1'b0; end
    else begin
      if (w_valid && w_ready) wp <= wp + 1;
      w_valid <= (w_valid && w_ready) ? (wp + 1 < nwords) : (wp < nwords);
    end
  end
  assign w_data = words[wp];

  always @(posedge clk) if (!rst) begin
    if (fp_fire && fi >= nframes) fi++;
    else if (fp_fire) begin
      logic [31:0] e_cs, e_sn, e_bx, e_by;
      void'($fscanf(fd_fp, "%h %h %h %h\n", e_cs, e_sn, e_bx, e_by));
      if (fcs !== e_cs[11:0] || fsn !== e_sn[11:0] || fbx !== e_bx[27:0] || fby !== e_by[27:0]) err_fp++;
      fi++;
    end
    if (frame_done) nfd++;
    if (win_done) begin
      logic [31:0] e [17];
      for (int k = 0; k < 17; k++) void'($fscanf(fd_win, "%h", e[k]));
      if (win_branch !== e[0][1:0] || win_keyupd !== e[1][0] || dut.u_est.u_core.q[0] !== e[4] || dut.u_est.u_core.q[1] !== e[5]
          || dut.u_est.u_core.v[0] !== e[7] || dut.u_est.u_core.v[1] !== e[8]) begin
        if (err_win < 10) $display("WIN %0d mismatch", wi);
        err_win++;
      end
      wi++;
    end
  end

  initial begin
    if (!$value$plusargs("VDIR=%s", vdir)) vdir = ".";
    $readmemh({vdir, "/cfg.hex"}, cfg);
    $readmemh({vdir, "/wgrid.hex"}, wg);
    $readmemh({vdir, "/mem_final_w.hex"}, mexp);
    nwords = cfg[50]; nframes = cfg[51]; nwin = cfg[52];
    words = new[nwords];
    $readmemh({vdir, "/words.hex"}, words);
    fd_fp = $fopen({vdir, "/exp_fp.hex"}, "r"); fd_win = $fopen({vdir, "/exp_win.hex"}, "r");
    wi = 0; fi = 0; nfd = 0; err_fp = 0; err_win = 0; err_mem = 0;
    // world memory starts at zero
    // world memory <- 0 through the test port (during reset)
    for (int b = 0; b < 16; b++) for (int a = 0; a < 128; a++) begin
      @(negedge clk); dbg_en = 1; dbg_we = 1; dbg_bank = b; dbg_addr = a; dbg_wdata = '0;
    end
    @(negedge clk); dbg_en = 0; dbg_we = 0;
    repeat (3) @(posedge clk);
    img_on = '0;
    load_plane(cfg[45], {vdir, "/plane_prev.hex"});
    if (cfg[46] != cfg[45] && cfg[28][0]) load_plane(cfg[46], {vdir, "/plane_key.hex"});
    ->ld_ev; #1;
    @(negedge clk); rst = 0;
    wait (wi == nwin && nfd == nframes);
    repeat (20) @(posedge clk);
    for (int b = 0; b < 16; b++) for (int a = 0; a < 128; a++) begin
      @(negedge clk); dbg_en = 1; dbg_we = 0; dbg_bank = b; dbg_addr = a;
      @(negedge clk); dbg_en = 0;
      if (dbg_rdata !== mexp[b * 128 + a]) err_mem++;
    end
    $display("RESULT windows %0d/%0d fp %0d/%0d (extra fp after the segment = next window, not checked) frames_done %0d  mismatches: fp %0d win %0d world_words %0d  mem rd %0d wr %0d  cycles %0d",
             wi, nwin, fi, nframes, nfd, err_fp, err_win, err_mem, n_rd, n_wr, $time / 5);
    if (err_fp + err_win + err_mem == 0) $display("PASS"); else $display("FAIL");
    $finish;
  end
  initial begin #(64'd8_000_000_000); $display("TIMEOUT wi %0d fi %0d nfd %0d wp %0d", wi, fi, nfd, wp); $finish; end
endmodule
