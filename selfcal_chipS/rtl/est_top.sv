// Stand-alone chip-S estimator: professor group-AER words -> aer_decoder -> est_tok_expand -> est_core.
// (In the full chip the decoder tokens are forked to xf_b8 and to est_tok_expand; see chip_s_full.)
module est_top #(
  parameter int SW = 960, SH = 720, PW = 320, NW = 1200, AW = 11, REC = 683, SHQ = 11
)(
  input  logic        clk, rst,
  input  logic [10:0] init_col_x,
  input  logic        init_col_ok, init_dir,
  input  logic        w_valid,
  output logic        w_ready,
  input  logic [31:0] w_data,
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
  output logic        fp_valid,
  input  logic        fp_ready,
  output logic signed [11:0] fp_cs, fp_sn,
  output logic signed [27:0] fp_b0x, fp_b0y,
  output logic        win_done,
  output logic [1:0]  win_branch,
  output logic        win_keyupd
);
  logic tv, tr, tpa, tpb; logic [1:0] tt; logic [10:0] tx; logic [6:0] tga; logic signed [7:0] tgb; logic [7:0] tma, tmb;
  logic pv, pr, pf; logic [10:0] px; logic [9:0] py;
  aer_decoder u_dec (.clk, .rst, .init_dir, .in_valid(w_valid), .in_ready(w_ready), .in_word(w_data),
    .tok_valid(tv), .tok_ready(tr), .tok_type(tt), .tok_x(tx), .tok_ga(tga), .tok_gb(tgb), .tok_pa(tpa), .tok_pb(tpb),
    .tok_ma(tma), .tok_mb(tmb));
  est_tok_expand #(.SW(SW), .SH(SH)) u_exp (.clk, .rst, .init_col_x, .init_col_ok, .tok_valid(tv), .tok_ready(tr),
    .tok_type(tt), .tok_x(tx), .tok_ga(tga), .tok_gb(tgb), .tok_pa(tpa), .tok_pb(tpb), .tok_ma(tma), .tok_mb(tmb),
    .p_valid(pv), .p_ready(pr), .p_fend(pf), .p_x(px), .p_y(py));
  logic sc_busy, sc_pub_set; logic signed [27:0] sc_O10x, sc_O10y; logic signed [31:0] q_o0, q_o1, q_o2;
  est_selfcal #(.SW(SW)) u_sc (.clk, .rst, .en(cfg_sc_en), .retry(cfg_sc_retry), .cfg_px, .cfg_py,
    .cfg_wPx, .cfg_wPy, .cfg_wOx, .cfg_wOy, .win_done, .win_branch, .q0(q_o0), .q1(q_o1), .q2(q_o2),
    .busy(sc_busy), .pub(sc_pub), .pub_set(sc_pub_set), .pub_px(sc_px), .pub_py(sc_py), .pub_O10x(sc_O10x), .pub_O10y(sc_O10y),
    .sc_state, .sc_res, .sc_lv, .sc_r2q10, .sc_ux, .sc_uy, .sc_n);
  est_core #(.SW(SW), .SH(SH), .PW(PW), .NW(NW), .AW(AW), .REC(REC), .SHQ(SHQ)) u_core (.clk, .rst,
    .cfg_mode, .cfg_px, .cfg_py, .cfg_d0, .cfg_d1, .cfg_d2, .cfg_min_ev, .cfg_thr0, .cfg_thr1, .cfg_thr2, .cfg_keyw,
    .cfg_qi0, .cfg_qi1, .cfg_qi2, .cfg_an, .cfg_wk_l2, .cfg_Lfix, .cfg_slowL, .cfg_slow_div,
    .cfg_wPx, .cfg_wPy, .cfg_wOx, .cfg_wOy, .cfg_KA, .cfg_KX, .cfg_KY, .cfg_BY16,
    .cfg_rot_t(cfg_rot_t | cfg_sc_en), .sc_busy, .sc_pub, .sc_pub_set, .sc_px, .sc_py, .sc_O10x, .sc_O10y, .q_o0, .q_o1, .q_o2,
    .init_started, .init_haskey, .init_preroll, .init_q0, .init_q1, .init_q2, .init_v0, .init_v1, .init_v2,
    .init_qr0, .init_qr1, .init_qr2, .init_qk0, .init_qk1, .init_qk2, .init_nprev, .init_Lp, .init_cur, .init_prev, .init_key,
    .p_valid(pv), .p_ready(pr), .p_fend(pf), .p_x(px), .p_y(py),
    .fp_valid, .fp_ready, .fp_cs, .fp_sn, .fp_b0x, .fp_b0y, .win_done, .win_branch, .win_keyupd);
endmodule
