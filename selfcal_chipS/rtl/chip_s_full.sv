// Chip S with the pose estimator (job24): the professor group-AER word stream is forked to
//   (a) chip_s_core  : decoder -> xf_b8 -> serializer -> world_writer (job23b)
//   (b) est_top      : decoder -> est_tok_expand -> est_core
// est_core's per-frame params (cs, sn, b0x, b0y) drive chip_s_core's frame-param port. A word is consumed when
// both branches have taken it (per-branch "taken" flags), so neither side can run ahead by more than one word;
// est_core emits a frame's params at the frame start, xf_b8 waits for them, so the two stay frame-aligned.
module chip_s_full #(
  parameter int F = 10, SW = 960, SH = 720, NE = 64,
  parameter int PW = 320, NW = 1200, AW = 11, REC = 683, SHQ = 11
)(
  input  logic        clk, rst,
  input  logic [10:0] init_col_x,
  input  logic        init_col_ok, init_dir,
  input  logic [15:0] init_lfsr,
  input  logic signed [15:0] cfg_x0, cfg_y0,
  input  logic [8:0]  cfg_w, cfg_h,
  input  logic        cfg_cm,
  input  logic        w_valid,
  output logic        w_ready,
  input  logic [31:0] w_data,
  // estimator configuration / initial state
  input  logic [1:0]  cfg_mode,
  input  logic signed [11:0] cfg_px, cfg_py,
  input  logic [15:0] cfg_d0, cfg_d1, cfg_d2,
  input  logic [23:0] cfg_min_ev,
  input  logic [15:0] cfg_thr0, cfg_thr1, cfg_thr2,
  input  logic [3:0]  cfg_keyw,
  input  logic signed [31:0] cfg_qi0, cfg_qi1, cfg_qi2,
  input  logic [3:0]  cfg_an,
  input  logic [1:0]  cfg_wk_l2,
  input  logic [3:0]  cfg_Lfix, cfg_slowL, cfg_slow_div,
  input  logic signed [11:0] cfg_wPx, cfg_wPy, cfg_wOx, cfg_wOy,
  input  logic signed [23:0] cfg_KA, cfg_KX, cfg_KY,
  input  logic signed [15:0] cfg_BY16,
  // ---- self-calibration
  input  logic        cfg_sc_en, cfg_sc_retry, cfg_rot_t,
  output logic [1:0]  sc_state,
  output logic [2:0]  sc_res,
  output logic [1:0]  sc_lv,
  output logic [9:0]  sc_r2q10,
  output logic signed [15:0] sc_ux, sc_uy,
  output logic [9:0]  sc_n,
  output logic        sc_pub,
  output logic signed [11:0] sc_px, sc_py,
  input  logic        init_started, init_haskey, init_preroll,
  input  logic signed [31:0] init_q0, init_q1, init_q2, init_v0, init_v1, init_v2,
  input  logic signed [31:0] init_qr0, init_qr1, init_qr2, init_qk0, init_qk1, init_qk2,
  input  logic [23:0] init_nprev,
  input  logic [3:0]  init_Lp,
  input  logic [1:0]  init_cur, init_prev, init_key,
  output logic        frame_done,
  output logic [31:0] n_rd, n_wr,
  output logic        win_done,
  output logic [1:0]  win_branch,
  output logic        win_keyupd,
  output logic        fp_fire,
  output logic signed [F+1:0] fp_cs_o, fp_sn_o,
  output logic signed [27:0]  fp_b0x_o, fp_b0y_o,
  // world memory test port (dbg_en has priority)
  input  logic        dbg_en, dbg_we,
  input  logic [3:0]  dbg_bank,
  input  logic [6:0]  dbg_addr,
  input  logic [63:0] dbg_wdata,
  output logic [63:0] dbg_rdata
);
  // ---- word fork
  logic tk_c, tk_e, rdy_c, rdy_e;
  wire vc = w_valid && !tk_c, ve = w_valid && !tk_e;
  wire done_c = tk_c || (vc && rdy_c), done_e = tk_e || (ve && rdy_e);
  assign w_ready = done_c && done_e;
  always_ff @(posedge clk) begin
    if (rst) begin tk_c <= 1'b0; tk_e <= 1'b0; end
    else if (w_valid && w_ready) begin tk_c <= 1'b0; tk_e <= 1'b0; end
    else begin
      if (vc && rdy_c) tk_c <= 1'b1;
      if (ve && rdy_e) tk_e <= 1'b1;
    end
  end
  // ---- estimator -> frame params
  logic fpv, fpr; logic signed [F+1:0] fcs, fsn; logic signed [27:0] fbx, fby;
  assign fp_fire = fpv && fpr; assign fp_cs_o = fcs; assign fp_sn_o = fsn; assign fp_b0x_o = fbx; assign fp_b0y_o = fby;
  est_top #(.SW(SW), .SH(SH), .PW(PW), .NW(NW), .AW(AW), .REC(REC), .SHQ(SHQ)) u_est (.clk, .rst,
    .init_col_x, .init_col_ok, .init_dir, .w_valid(ve), .w_ready(rdy_e), .w_data,
    .cfg_mode, .cfg_px, .cfg_py, .cfg_d0, .cfg_d1, .cfg_d2, .cfg_min_ev, .cfg_thr0, .cfg_thr1, .cfg_thr2, .cfg_keyw,
    .cfg_qi0, .cfg_qi1, .cfg_qi2, .cfg_an, .cfg_wk_l2, .cfg_Lfix, .cfg_slowL, .cfg_slow_div,
    .cfg_wPx, .cfg_wPy, .cfg_wOx, .cfg_wOy, .cfg_KA, .cfg_KX, .cfg_KY, .cfg_BY16,
    .cfg_sc_en, .cfg_sc_retry, .cfg_rot_t, .sc_state, .sc_res, .sc_lv, .sc_r2q10, .sc_ux, .sc_uy, .sc_n, .sc_pub, .sc_px, .sc_py,
    .init_started, .init_haskey, .init_preroll, .init_q0, .init_q1, .init_q2, .init_v0, .init_v1, .init_v2,
    .init_qr0, .init_qr1, .init_qr2, .init_qk0, .init_qk1, .init_qk2, .init_nprev, .init_Lp, .init_cur, .init_prev, .init_key,
    .fp_valid(fpv), .fp_ready(fpr), .fp_cs(fcs), .fp_sn(fsn), .fp_b0x(fbx), .fp_b0y(fby),
    .win_done, .win_branch, .win_keyupd);
  // ---- world path
  logic cq, cw; logic [3:0] cb; logic [6:0] ca; logic [63:0] cwd, rdat;
  chip_s_core #(.F(F), .SW(SW), .SH(SH), .NE(NE)) u_core (.clk, .rst, .init_col_x, .init_col_ok, .init_dir, .init_lfsr,
    .cfg_x0, .cfg_y0, .cfg_w, .cfg_h, .cfg_cm, .w_valid(vc), .w_ready(rdy_c), .w_data,
    .fp_valid(fpv), .fp_ready(fpr), .fp_cs(fcs), .fp_sn(fsn), .fp_b0x(fbx), .fp_b0y(fby),
    .m_req(cq), .m_we(cw), .m_bank(cb), .m_addr(ca), .m_wdata(cwd), .m_rdata(rdat), .frame_done, .n_rd, .n_wr);
  world_mem u_mem (.clk, .req(dbg_en ? 1'b1 : cq), .we(dbg_en ? dbg_we : cw), .bank(dbg_en ? dbg_bank : cb),
    .addr(dbg_en ? dbg_addr : ca), .wdata(dbg_en ? dbg_wdata : cwd), .rdata(rdat));
  assign dbg_rdata = rdat;
endmodule
