// Chip-S pose estimator (job24), bit-identical to results/job24_est.py EstS:
//   FOV two-plane 1-bit map (3 px cells) + KEYFRAME plane, N=9 candidates per searched DOF (Jacobi), M=2^11
//   samples (stride = n_prev >> 11), parabolic refine, slow-only L=8 window else L=4, velocity blend an/10,
//   alpha-beta OFF. Modes: 0 roll (theta), 1 pan (x, Q4 px; world rotation by integer coupling), 2 3-DOF (UZH).
// Streaming: the window's pixels arrive in sensor order; every 2^wk_l2-th pixel sets a bit of the CUR plane, every
// stride-th pixel (first 2048) is scored against the PREV and KEY planes for all candidates (one candidate per
// cycle through a 4-stage pipeline, input stalled meanwhile). Per-frame candidate rotation tables (CORDIC F=12)
// and the world frame params (CORDIC F=10, job23 port: cs, sn, b0x, b0y) are made at each frame start.
// Planes: 3 physical planes, roles cur / prev / key by index. key == prev only right after a key update, and then
// q_key == q_ref, so one read serves both scores.
module est_core #(
  parameter int SW = 960, SH = 720,
  parameter int PW = 320,                      // ceil(SW/3)
  parameter int NW = 1200, AW = 11,            // 64-bit words per plane (ceil(PW*PH/64))
  parameter int REC = 683, SHQ = 11            // floor(v/3) = (v*REC) >> SHQ for 0 <= v < SW
)(
  input  logic        clk, rst,
  // ---- configuration (static)
  input  logic [1:0]  cfg_mode,                // 0 roll, 1 pan, 2 3d
  input  logic signed [11:0] cfg_px, cfg_py,   // estimator rotation pivot
  input  logic [15:0] cfg_d0, cfg_d1, cfg_d2,  // candidate spacing per DOF (pose units)
  input  logic [23:0] cfg_min_ev,
  input  logic [15:0] cfg_thr0, cfg_thr1, cfg_thr2,
  input  logic [3:0]  cfg_keyw,                // key score weight, Q2
  input  logic signed [31:0] cfg_qi0, cfg_qi1, cfg_qi2,   // pose at start
  input  logic [3:0]  cfg_an,                  // velocity blend an/10
  input  logic [1:0]  cfg_wk_l2,               // map write every 2^wk_l2-th pixel
  input  logic [3:0]  cfg_Lfix, cfg_slowL, cfg_slow_div,
  // world frame params: world = R(ang)(p - P) + O - (dx, dy)/16
  input  logic signed [11:0] cfg_wPx, cfg_wPy, cfg_wOx, cfg_wOy,
  input  logic signed [23:0] cfg_KA, cfg_KX, cfg_KY,      // pan coupling, Q20
  input  logic signed [15:0] cfg_BY16,
  // ---- self-calibration (selfcal): rot_t = rotate 3-DOF translation differences into the plane frame
  input  logic        cfg_rot_t,
  input  logic        sc_busy,                 // hold at the window start while the calibrator works
  input  logic        sc_pub,                  // published: roll mode about (sc_px, sc_py), world offset sc_O10 (Q10)
  input  logic        sc_pub_set,              // publication pulse: zero v1, v2
  input  logic signed [11:0] sc_px, sc_py,
  input  logic signed [27:0] sc_O10x, sc_O10y,
  output logic signed [31:0] q_o0, q_o1, q_o2,
  // ---- initial state (reset values; a real chip starts with zeros and preroll = 1)
  input  logic        init_started, init_haskey, init_preroll,
  input  logic signed [31:0] init_q0, init_q1, init_q2, init_v0, init_v1, init_v2,
  input  logic signed [31:0] init_qr0, init_qr1, init_qr2, init_qk0, init_qk1, init_qk2,
  input  logic [23:0] init_nprev,
  input  logic [3:0]  init_Lp,
  input  logic [1:0]  init_cur, init_prev, init_key,
  // ---- pixel stream (sensor coordinates)
  input  logic        p_valid,
  output logic        p_ready,
  input  logic        p_fend,
  input  logic [10:0] p_x,
  input  logic [9:0]  p_y,
  // ---- world frame params (one per frame)
  output logic        fp_valid,
  input  logic        fp_ready,
  output logic signed [11:0] fp_cs, fp_sn,
  output logic signed [27:0] fp_b0x, fp_b0y,
  // ---- window record (pulse at the end of every window, for test)
  output logic        win_done,
  output logic [1:0]  win_branch,              // 0 idle, 1 start, 2 coast, 3 score
  output logic        win_keyupd
);
  typedef logic signed [31:0] s32;
  localparam int NCAND = 27;
  // ------------------------------------------------------------------ effective configuration (legacy when !sc_pub)
  wire [1:0] e_mode = sc_pub ? 2'd0 : cfg_mode;
  wire signed [11:0] e_px = sc_pub ? sc_px : cfg_px;
  wire signed [11:0] e_py = sc_pub ? sc_py : cfg_py;
  wire signed [11:0] e_wPx = sc_pub ? sc_px : cfg_wPx;
  wire signed [11:0] e_wPy = sc_pub ? sc_py : cfg_wPy;
  wire signed [31:0] e_wO10x = sc_pub ? 32'(sc_O10x) : (32'(cfg_wOx) <<< 10);
  wire signed [31:0] e_wO10y = sc_pub ? 32'(sc_O10y) : (32'(cfg_wOy) <<< 10);
  wire rot = cfg_rot_t && (e_mode == 2'd2);
  // ------------------------------------------------------------------ state
  s32 q [3], v [3], qr [3], qk [3], qc [3], ap [3], w [3], qm [3];
  logic started, haskey, preroll;
  logic [23:0] nprev, n, idx, next_s;
  logic [11:0] nsamp;
  logic [13:0] stp;
  logic [3:0] Lp, L, j;
  logic [1:0] cur_id, prev_id, key_id;
  logic [2:0] dofm;                                    // active DOF mask
  always_comb case (e_mode) 2'd0: dofm = 3'b001; 2'd1: dofm = 3'b010; default: dofm = 3'b111; endcase
  wire [4:0] ncand = (e_mode == 2'd2) ? 5'd27 : 5'd9;
  s32 dd [3]; assign dd[0] = {16'd0, cfg_d0}; assign dd[1] = {16'd0, cfg_d1}; assign dd[2] = {16'd0, cfg_d2};
  s32 thr [3]; assign thr[0] = {16'd0, cfg_thr0}; assign thr[1] = {16'd0, cfg_thr1}; assign thr[2] = {16'd0, cfg_thr2};
  function automatic s32 coff(input s32 d, input logic [3:0] c);     // candidate offset d * (c - 4)
    return d * ($signed({28'd0, c}) - 32'sd4);
  endfunction
  function automatic s32 sabs(input s32 a); return a[31] ? -a : a; endfunction
  function automatic logic [1:0] free_id(input logic [1:0] a, input logic [1:0] b);
    if (a != 2'd0 && b != 2'd0) return 2'd0;
    if (a != 2'd1 && b != 2'd1) return 2'd1;
    return 2'd2;
  endfunction

  // ------------------------------------------------------------------ CORDICs
  logic c12_start, c12_busy, c12_done; logic [13:0] c12_ang; logic signed [13:0] c12_cs, c12_sn;
  est_cordic #(.F(12)) u_c12 (.clk, .rst, .start(c12_start), .ang(c12_ang), .busy(c12_busy), .done(c12_done), .cs(c12_cs), .sn(c12_sn));
  logic c10_start, c10_busy, c10_done; logic [13:0] c10_ang; logic signed [11:0] c10_cs, c10_sn;
  est_cordic #(.F(10)) u_c10 (.clk, .rst, .start(c10_start), .ang(c10_ang), .busy(c10_busy), .done(c10_done), .cs(c10_cs), .sn(c10_sn));
  // per-frame tables: prev / key rotation per theta candidate, fill rotation; translation bases
  logic signed [13:0] tcs_p [9], tsn_p [9], tcs_k [9], tsn_k [9], fcs, fsn;
  s32 btx_p, bty_p, btx_k, bty_k, ftx, fty;
  // rot_t: per-window rotations R(qr0), R(qk0), R(qc0) and rotated candidate steps (c-4) * k
  logic signed [13:0] rcp, rsp, rck, rsk, rcf, rsf;
  logic signed [17:0] kp0x, kp0y, kp1x, kp1y, kk0x, kk0y, kk1x, kk1y;
  function automatic s32 rotx(input logic signed [13:0] c, input logic signed [13:0] sn_, input s32 x, input s32 y);
    logic signed [47:0] t; t = c * x - sn_ * y; return s32'(t >>> 12);
  endfunction
  function automatic s32 roty(input logic signed [13:0] c, input logic signed [13:0] sn_, input s32 x, input s32 y);
    logic signed [47:0] t; t = sn_ * x + c * y; return s32'(t >>> 12);
  endfunction
  function automatic logic signed [17:0] kmul(input logic signed [13:0] c, input logic [15:0] d);
    logic signed [31:0] t; t = c * $signed({1'b0, d}); return 18'(t >>> 12);
  endfunction
  // one shared rotation unit (S_RB0 prev, S_RB1 key, S_RB2 fill) and one shared k-step unit (S_RTK prev, S_RTK2 key)
  logic signed [13:0] ru_c, ru_s; s32 ru_x, ru_y, ru_rx, ru_ry;
  logic signed [13:0] ku_c, ku_s; logic signed [17:0] ku_0x, ku_0y, ku_1x, ku_1y;

  // ------------------------------------------------------------------ divider (unsigned, 40/32)
  logic dv_start, dv_busy, dv_done; logic [39:0] dv_n, dv_q; logic [31:0] dv_d;
  est_udiv u_div (.clk, .rst, .start(dv_start), .n(dv_n), .d(dv_d), .busy(dv_busy), .done(dv_done), .q(dv_q));

  // ------------------------------------------------------------------ geometry stages
  // stage A: rotate about the pivot (theta active), translate (Q4) per active DOF, bound -> {ok, X, Y}
  function automatic logic [22:0] xyf(input logic [10:0] x, input logic [9:0] y,
                                      input logic signed [13:0] cs, input logic signed [13:0] sn, input s32 dtx, input s32 dty);
    logic signed [35:0] X, Y, dx, dy, rx, ry;
    logic ok;
    X = $signed({25'd0, x}); Y = $signed({26'd0, y});
    if (dofm[0]) begin
      dx = X - e_px; dy = Y - e_py;
      rx = cs * dx - sn * dy; ry = sn * dx + cs * dy;
      X = (rx >>> 12) + e_px; Y = (ry >>> 12) + e_py;
    end
    if (dofm[1]) X = ((X <<< 4) - dtx) >>> 4;
    if (dofm[2]) Y = ((Y <<< 4) - dty) >>> 4;
    ok = (X >= 0) && (Y >= 0) && (X < SW) && (Y < SH);
    return {ok, ok ? X[10:0] : 11'd0, ok ? Y[10:0] : 11'd0};
  endfunction
  // stage B: quantise to 3 px cells -> {ok, word, bit}
  function automatic logic [AW+6:0] cellf(input logic [22:0] a);
    logic [31:0] cx, cy, cidx;
    cx = ({21'd0, a[21:11]} * REC) >> SHQ; cy = ({21'd0, a[10:0]} * REC) >> SHQ;
    cidx = cy * PW + cx;
    return {a[22], cidx[AW+5:0]};
  endfunction

  // ------------------------------------------------------------------ planes
  logic pl_clr [3], pl_we [3], pl_re [3], pl_rd [3], pl_busy [3];
  logic [AW-1:0] pl_wa [3], pl_ra [3]; logic [5:0] pl_wb [3], pl_rb [3];
  genvar gp;
  generate for (gp = 0; gp < 3; gp++) begin : g_pl
    est_plane #(.NW(NW), .AW(AW)) u_pl (.clk, .clr(pl_clr[gp]), .we(pl_we[gp]), .waddr(pl_wa[gp]), .wbit(pl_wb[gp]), .busy(pl_busy[gp]),
      .re(pl_re[gp]), .raddr(pl_ra[gp]), .rbit(pl_rb[gp]), .rdata(pl_rd[gp]));
  end endgenerate

  // ------------------------------------------------------------------ FSM
  typedef enum logic [4:0] {S_WSTART, S_WSTART2, S_FSTART, S_TAB, S_TABW, S_WFP, S_WFP2, S_WFP3, S_FPOUT, S_STREAM,
                            S_SCORE, S_DRAIN, S_WEND, S_ARG, S_REFA, S_REF, S_REFB, S_REF2, S_VEL1, S_VEL1W, S_VEL2, S_VEL2W,
                            S_NEXTDOF, S_SWAP, S_RT, S_RTW, S_RTK, S_RTK2, S_RB0, S_RB1, S_RB2} st_t;
  st_t st;
  logic [4:0] tk;
  s32 wdx, wdy; logic [13:0] wang;
  // sample
  logic [10:0] sx; logic [9:0] sy;
  logic [4:0] ci;
  // score pipeline: A (xy) -> B (cidx, read issue) -> C (read data) -> accumulate
  logic sAv, sBv, sCv; logic [4:0] sAc, sBc, sCc;
  logic [22:0] sAp, sAk; logic sBokp, sBokk, sCokp, sCokk;
  logic [AW+5:0] sBpc, sBkc;
  logic [11:0] sc [NCAND], ks [NCAND];
  // fill pipeline: A (xy) -> B (cidx) -> write
  logic fAv, fBv; logic [22:0] fAxy; logic [AW+6:0] fBcell;
  // end-of-window
  logic [1:0] dk; logic [3:0] am; s32 best; logic [3:0] jb;
  logic dneg; s32 vnew; s32 ra_, rb_, rc_, rden_, rnum_;
  logic signed [47:0] pKA, pKX, pKY;

  function automatic s32 tot_of(input logic [4:0] i);
    return $signed({20'd0, sc[i]}) + (($signed({28'd0, cfg_keyw}) * $signed({20'd0, ks[i]})) >>> 2);
  endfunction

  // pixel accept
  // fill stall: the write stage holds while the cur plane finishes a read-modify-write
  wire fstall = fBv && fBcell[AW+6] && pl_busy[cur_id];
  assign p_ready = (st == S_STREAM) && !fstall;
  wire acc   = p_valid && p_ready;
  wire is_px = acc && !p_fend;
  wire do_fill = is_px && !preroll && ((idx & ((24'd1 << cfg_wk_l2) - 24'd1)) == 24'd0);
  wire do_samp = is_px && !preroll && started && (idx == next_s) && (nsamp < 12'd2048);

  // candidate of the issue stage
  wire [1:0] cdof = (ci < 5'd9) ? 2'd0 : ((ci < 5'd18) ? 2'd1 : 2'd2);
  wire [3:0] cc4 = (ci < 5'd9) ? ci[3:0] : ((ci < 5'd18) ? 4'(ci - 5'd9) : 4'(ci - 5'd18));
  wire [1:0] cd = (e_mode == 2'd1) ? 2'd1 : cdof;
  wire [3:0] tix = (cd == 2'd0) ? cc4 : 4'd4;
  wire signed [31:0] otx = (cd == 2'd1) ? coff(dd[1], cc4) : 32'sd0;
  wire signed [31:0] oty = (cd == 2'd2) ? coff(dd[2], cc4) : 32'sd0;
  wire signed [3:0]  cm4 = 4'($signed({1'b0, cc4}) - 5'sd4);
  wire signed [21:0] rtxp = (cd == 2'd1) ? cm4 * kp0x : ((cd == 2'd2) ? cm4 * kp1x : 22'sd0);
  wire signed [21:0] rtyp = (cd == 2'd1) ? cm4 * kp0y : ((cd == 2'd2) ? cm4 * kp1y : 22'sd0);
  wire signed [21:0] rtxk = (cd == 2'd1) ? cm4 * kk0x : ((cd == 2'd2) ? cm4 * kk1x : 22'sd0);
  wire signed [21:0] rtyk = (cd == 2'd1) ? cm4 * kk0y : ((cd == 2'd2) ? cm4 * kk1y : 22'sd0);
  wire signed [31:0] otxp = rot ? 32'(rtxp) : otx;
  wire signed [31:0] otyp = rot ? 32'(rtyp) : oty;
  wire signed [31:0] otxk = rot ? 32'(rtxk) : otx;
  wire signed [31:0] otyk = rot ? 32'(rtyk) : oty;
  wire issue = (st == S_SCORE) && (ci < ncand);

  always_comb begin
    case (st)
      S_RB1:   begin ru_c = rck; ru_s = rsk; ru_x = btx_k; ru_y = bty_k; end
      S_RB2:   begin ru_c = rcf; ru_s = rsf; ru_x = ftx;   ru_y = fty;   end
      default: begin ru_c = rcp; ru_s = rsp; ru_x = btx_p; ru_y = bty_p; end
    endcase
    ru_rx = rotx(ru_c, ru_s, ru_x, ru_y); ru_ry = roty(ru_c, ru_s, ru_x, ru_y);
    if (st == S_RTK2) begin ku_c = rck; ku_s = rsk; end else begin ku_c = rcp; ku_s = rsp; end
    ku_0x = kmul(ku_c, cfg_d1); ku_0y = kmul(ku_s, cfg_d1); ku_1x = -kmul(ku_s, cfg_d2); ku_1y = kmul(ku_c, cfg_d2);
  end
  // plane port muxes
  always_comb begin
    for (int i = 0; i < 3; i++) begin
      pl_clr[i] = (st == S_WSTART) && (cur_id == i[1:0]);
      pl_we[i]  = fBv && fBcell[AW+6] && !fstall && (cur_id == i[1:0]);
      pl_wa[i]  = fBcell[AW+5:6]; pl_wb[i] = fBcell[5:0];
      pl_re[i]  = sBv && ((prev_id == i[1:0]) || (haskey && key_id == i[1:0]));
      if (prev_id == i[1:0]) begin pl_ra[i] = sBpc[AW+5:6]; pl_rb[i] = sBpc[5:0]; end
      else begin pl_ra[i] = sBkc[AW+5:6]; pl_rb[i] = sBkc[5:0]; end
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      st <= S_WSTART;
      started <= init_started; haskey <= init_haskey; preroll <= init_preroll;
      q[0] <= init_q0; q[1] <= init_q1; q[2] <= init_q2; v[0] <= init_v0; v[1] <= init_v1; v[2] <= init_v2;
      qr[0] <= init_qr0; qr[1] <= init_qr1; qr[2] <= init_qr2; qk[0] <= init_qk0; qk[1] <= init_qk1; qk[2] <= init_qk2;
      nprev <= init_nprev; Lp <= init_Lp; cur_id <= init_cur; prev_id <= init_prev; key_id <= init_key;
      fp_valid <= 1'b0; win_done <= 1'b0; c12_start <= 1'b0; c10_start <= 1'b0; dv_start <= 1'b0;
      sAv <= 1'b0; sBv <= 1'b0; sCv <= 1'b0; fAv <= 1'b0; fBv <= 1'b0; ci <= '0; tk <= '0;
      win_branch <= '0; win_keyupd <= 1'b0;
      rcp <= '0; rsp <= '0; rck <= '0; rsk <= '0; rcf <= '0; rsf <= '0;
      kp0x <= '0; kp0y <= '0; kp1x <= '0; kp1y <= '0; kk0x <= '0; kk0y <= '0; kk1x <= '0; kk1y <= '0;
    end else begin
      win_done <= 1'b0; c12_start <= 1'b0; c10_start <= 1'b0; dv_start <= 1'b0;
      // ---- fill pipeline
      if (!fstall) begin
        fAv <= do_fill; fAxy <= xyf(p_x, p_y, fcs, fsn, ftx, fty);
        fBv <= fAv;     fBcell <= cellf(fAxy);
      end
      // ---- score pipeline
      sAv <= issue; sAc <= ci;
      sAp <= xyf(sx, sy, tcs_p[tix], tsn_p[tix], btx_p + otxp, bty_p + otyp);
      sAk <= xyf(sx, sy, tcs_k[tix], tsn_k[tix], btx_k + otxk, bty_k + otyk);
      sBv <= sAv; sBc <= sAc;
      begin
        automatic logic [AW+6:0] pc = cellf(sAp), kc = cellf(sAk);
        sBokp <= pc[AW+6]; sBpc <= pc[AW+5:0]; sBokk <= kc[AW+6] && haskey; sBkc <= kc[AW+5:0];
      end
      sCv <= sBv; sCc <= sBc; sCokp <= sBokp; sCokk <= sBokk;
      if (sCv) begin
        if (sCokp && pl_rd[prev_id]) sc[sCc] <= sc[sCc] + 12'd1;
        if (sCokk && pl_rd[key_id])  ks[sCc] <= ks[sCc] + 12'd1;
      end
      case (st)
        // ============ window start (cur plane cleared this cycle)
        S_WSTART: if (!sc_busy) begin
          if (preroll) L <= 4'd1;
          else if (started && (!dofm[0] || ((sabs(v[0]) >>> 2) * $signed({28'd0, cfg_slow_div}) < dd[0])) &&
                              (!dofm[1] || ((sabs(v[1]) >>> 2) * $signed({28'd0, cfg_slow_div}) < dd[1])) &&
                              (!dofm[2] || ((sabs(v[2]) >>> 2) * $signed({28'd0, cfg_slow_div}) < dd[2]))) L <= cfg_slowL;
          else L <= cfg_Lfix;
          n <= '0; idx <= '0; nsamp <= '0; next_s <= '0;
          stp <= ((nprev >> 11) == 24'd0) ? 14'd1 : 14'(nprev >> 11);
          for (int i = 0; i < NCAND; i++) begin sc[i] <= '0; ks[i] <= '0; end
          j <= '0; st <= S_WSTART2;
        end
        S_WSTART2: begin
          for (int k = 0; k < 3; k++)
            qc[k] <= started ? (q[k] + ((v[k] * ($signed({28'd0, Lp}) + $signed({28'd0, L}))) >>> 3)) : q[k];
          tk <= '0; st <= rot ? S_RT : S_FSTART;
        end
        // ============ rot_t: per-window rotations R(qr0), R(qk0), R(qc0) (CORDIC F=12, positive angles)
        S_RT: begin
          c12_start <= 1'b1;
          c12_ang <= (tk == 5'd0) ? 14'(qr[0]) : ((tk == 5'd1) ? 14'(qk[0]) : 14'(qc[0]));
          st <= S_RTW;
        end
        S_RTW: if (c12_done) begin
          if (tk == 5'd0) begin rcp <= c12_cs; rsp <= c12_sn; end
          else if (tk == 5'd1) begin rck <= c12_cs; rsk <= c12_sn; end
          else begin rcf <= c12_cs; rsf <= c12_sn; end
          if (tk == 5'd2) st <= S_RTK; else begin tk <= tk + 5'd1; st <= S_RT; end
        end
        S_RTK:  begin kp0x <= ku_0x; kp0y <= ku_0y; kp1x <= ku_1x; kp1y <= ku_1y; st <= S_RTK2; end
        S_RTK2: begin kk0x <= ku_0x; kk0y <= ku_0y; kk1x <= ku_1x; kk1y <= ku_1y; st <= S_FSTART; end
        // ============ frame start
        S_FSTART: begin
          for (int k = 0; k < 3; k++)
            w[k] <= started ? ((v[k] * (($signed({28'd0, j}) <<< 1) - ($signed({28'd0, L}) - 32'sd1))) >>> 3) : 32'sd0;
          tk <= '0; st <= S_TAB;
        end
        S_TAB: begin
          for (int k = 0; k < 3; k++) ap[k] <= qc[k] + w[k];
          btx_p <= qc[1] + w[1] - qr[1]; bty_p <= qc[2] + w[2] - qr[2];
          btx_k <= qc[1] + w[1] - qk[1]; bty_k <= qc[2] + w[2] - qk[2];
          ftx <= w[1]; fty <= w[2];
          // rotation jobs (theta active): 0..8 prev (started), 9..17 key (started & key), 18 fill
          if (!dofm[0] || tk > 5'd18) begin tk <= '0; st <= rot ? S_RB0 : S_WFP; end
          else if ((tk < 5'd9 && !started) || (tk >= 5'd9 && tk < 5'd18 && !(started && haskey))) tk <= tk + 5'd1;
          else begin
            c12_start <= 1'b1;
            if (tk < 5'd9)       c12_ang <= 14'(-(qc[0] + coff(dd[0], tk[3:0]) + w[0] - qr[0]));
            else if (tk < 5'd18) c12_ang <= 14'(-(qc[0] + coff(dd[0], 4'(tk - 5'd9)) + w[0] - qk[0]));
            else                 c12_ang <= 14'(-w[0]);
            st <= S_TABW;
          end
        end
        S_TABW: if (c12_done) begin
          if (tk < 5'd9)       begin tcs_p[tk[3:0]] <= c12_cs; tsn_p[tk[3:0]] <= c12_sn; end
          else if (tk < 5'd18) begin tcs_k[4'(tk - 5'd9)] <= c12_cs; tsn_k[4'(tk - 5'd9)] <= c12_sn; end
          else                 begin fcs <= c12_cs; fsn <= c12_sn; end
          tk <= tk + 5'd1; st <= S_TAB;
        end
        // ============ rot_t: rotate the translation bases into the plane frames (one rotation per cycle)
        S_RB0: begin btx_p <= ru_rx; bty_p <= ru_ry; st <= S_RB1; end
        S_RB1: begin btx_k <= ru_rx; bty_k <= ru_ry; st <= S_RB2; end
        S_RB2: begin ftx <= ru_rx; fty <= ru_ry; st <= S_WFP; end
        // ============ world frame params
        S_WFP: begin
          pKA <= ap[1] * cfg_KA; pKX <= ap[1] * cfg_KX; pKY <= ap[1] * cfg_KY;
          st <= S_WFP2;
        end
        S_WFP2: begin
          if (e_mode == 2'd1) begin
            wang <= 14'((pKA + 48'sd524288) >>> 20);
            wdx  <= ap[1] + 32'(pKX >>> 20);
            wdy  <= 32'(pKY >>> 20) + cfg_BY16;
          end else begin
            wang <= 14'(-ap[0]);
            wdx  <= (e_mode == 2'd2) ? ap[1] : 32'sd0;
            wdy  <= (e_mode == 2'd2) ? ap[2] : 32'sd0;
          end
          c10_start <= 1'b0; st <= S_WFP3; tk <= '0;
        end
        S_WFP3: begin
          if (tk == 5'd0) begin c10_start <= 1'b1; c10_ang <= wang; tk <= 5'd1; end
          else if (c10_done) begin
            fp_cs <= c10_cs; fp_sn <= c10_sn;
            fp_b0x <= 28'(e_wO10x - (s32'(c10_cs) * s32'(e_wPx) - s32'(c10_sn) * s32'(e_wPy)) - (wdx <<< 6));
            fp_b0y <= 28'(e_wO10y - (s32'(c10_sn) * s32'(e_wPx) + s32'(c10_cs) * s32'(e_wPy)) - (wdy <<< 6));
            fp_valid <= 1'b1; tk <= '0; st <= S_FPOUT;
          end
        end
        S_FPOUT: if (fp_ready) begin fp_valid <= 1'b0; st <= S_STREAM; end
        // ============ streaming
        S_STREAM: begin
          if (is_px) begin
            if (!preroll) begin n <= n + 24'd1; idx <= idx + 24'd1; end
            if (do_samp) begin
              sx <= p_x; sy <= p_y; nsamp <= nsamp + 12'd1; next_s <= next_s + {10'd0, stp};
              ci <= '0; st <= S_SCORE;
            end
          end else if (acc) begin                                   // frame end
            if (j + 4'd1 == L) st <= S_DRAIN;
            else begin j <= j + 4'd1; st <= S_FSTART; end
          end
        end
        S_SCORE: begin
          if (ci < ncand) ci <= ci + 5'd1;
          else if (!sAv && !sBv && !sCv) begin ci <= '0; st <= S_STREAM; end
        end
        S_DRAIN: if (!fAv && !fBv && !pl_busy[cur_id]) st <= S_WEND;
        // ============ window end
        S_WEND: begin
          if (preroll) begin preroll <= 1'b0; st <= S_WSTART; end
          else if (!started) begin
            if (n >= cfg_min_ev) begin
              started <= 1'b1; q[0] <= cfg_qi0; q[1] <= cfg_qi1; q[2] <= cfg_qi2;
              v[0] <= '0; v[1] <= '0; v[2] <= '0;
              qm[0] <= cfg_qi0; qm[1] <= cfg_qi1; qm[2] <= cfg_qi2;
              win_branch <= 2'd1; st <= S_SWAP;
            end else begin
              win_branch <= 2'd0; win_keyupd <= 1'b0; nprev <= n; Lp <= L; win_done <= 1'b1; st <= S_WSTART;
            end
          end else if (n < cfg_min_ev) begin
            for (int k = 0; k < 3; k++) q[k] <= qc[k];
            win_branch <= 2'd2; win_keyupd <= 1'b0; nprev <= n; Lp <= L; win_done <= 1'b1; st <= S_WSTART;
          end else begin
            win_branch <= 2'd3;
            for (int k = 0; k < 3; k++) qm[k] <= qc[k];
            dk <= (e_mode == 2'd1) ? 2'd1 : 2'd0; am <= '0; st <= S_ARG;
          end
        end
        S_ARG: begin                                                // first maximum of the 9 candidates of DOF dk
          automatic logic [4:0] base = (e_mode == 2'd2) ? 5'(dk * 9) : 5'd0;
          automatic s32 t = tot_of(base + 5'(am));
          if (am == 4'd0 || t > best) begin best <= t; jb <= am; end
          if (am == 4'd8) st <= S_REFA;
          else am <= am + 4'd1;
        end
        S_REFA: begin                                               // fetch the three neighbouring scores (timing: split S_REF)
          automatic logic [4:0] base = (e_mode == 2'd2) ? 5'(dk * 9) : 5'd0;
          ra_ <= tot_of(base + 5'(jb) - 5'd1);
          rb_ <= tot_of(base + 5'(jb));
          rc_ <= tot_of(base + 5'(jb) + 5'd1);
          st <= S_REF;
        end
        S_REF: begin                                                // parabola numerator / denominator
          rden_ <= ra_ - (rb_ <<< 1) + rc_;
          rnum_ <= dd[dk] * (ra_ - rc_);
          qm[dk] <= qc[dk] + coff(dd[dk], jb);
          st <= S_REFB;
        end
        S_REFB: begin                                               // parabolic refine (truncating divide)
          automatic s32 den = rden_;
          automatic s32 num = rnum_;
          if (jb != 4'd0 && jb != 4'd8 && den < 0) begin
            dv_n <= 40'(sabs(num)); dv_d <= 32'(sabs(den <<< 1)); dv_start <= 1'b1;
            dneg <= (num > 0);                                      // den2 < 0: result negative iff num > 0
            st <= S_REF2;
          end else st <= S_VEL1;
        end
        S_REF2: if (dv_done) begin
          qm[dk] <= qm[dk] + (dneg ? -$signed(dv_q[31:0]) : $signed(dv_q[31:0]));
          st <= S_VEL1;
        end
        S_VEL1: begin                                               // vnew = floor((qm - q) * 8 / (Lp + L))
          automatic s32 nu = (qm[dk] - q[dk]) <<< 3;
          automatic s32 de = $signed({28'd0, Lp}) + $signed({28'd0, L});
          dv_n <= 40'(nu[31] ? (-nu + de - 32'sd1) : nu); dv_d <= 32'(de); dv_start <= 1'b1; dneg <= nu[31];
          st <= S_VEL1W;
        end
        S_VEL1W: if (dv_done) begin vnew <= dneg ? -$signed(dv_q[31:0]) : $signed(dv_q[31:0]); st <= S_VEL2; end
        S_VEL2: begin                                               // v = floor((an vnew + (10-an) v) / 10)
          automatic s32 nu = $signed({28'd0, cfg_an}) * vnew + (32'sd10 - $signed({28'd0, cfg_an})) * v[dk];
          dv_n <= 40'(nu[31] ? (-nu + 32'sd9) : nu); dv_d <= 32'd10; dv_start <= 1'b1; dneg <= nu[31];
          st <= S_VEL2W;
        end
        S_VEL2W: if (dv_done) begin
          v[dk] <= dneg ? -$signed(dv_q[31:0]) : $signed(dv_q[31:0]);
          q[dk] <= qm[dk]; st <= S_NEXTDOF;
        end
        S_NEXTDOF: begin
          if (e_mode == 2'd2 && dk != 2'd2) begin dk <= dk + 2'd1; am <= '0; st <= S_ARG; end
          else st <= S_SWAP;
        end
        S_SWAP: begin                                               // swap planes, q_ref = q, key update
          automatic logic upd = !haskey ||
                                (dofm[0] && sabs(qm[0] - qk[0]) > thr[0]) ||
                                (dofm[1] && sabs(qm[1] - qk[1]) > thr[1]) ||
                                (dofm[2] && sabs(qm[2] - qk[2]) > thr[2]);
          automatic logic [1:0] nkey = upd ? cur_id : key_id;
          prev_id <= cur_id; key_id <= nkey; cur_id <= free_id(cur_id, nkey);
          for (int k = 0; k < 3; k++) begin qr[k] <= qm[k]; if (upd) qk[k] <= qm[k]; end
          if (upd) haskey <= 1'b1;
          win_keyupd <= upd; nprev <= n; Lp <= L; win_done <= 1'b1;
          st <= S_WSTART;
        end
        default: st <= S_WSTART;
      endcase
      if (sc_pub_set) begin v[1] <= '0; v[2] <= '0; end      // entering 1-DOF mode (job26 _enter_rot1: v[1:] = 0)
    end
  end
  assign q_o0 = q[0]; assign q_o1 = q[1]; assign q_o2 = q[2];
endmodule

// unsigned 40 / 32 restoring divider, one quotient bit per cycle (40 cycles)
module est_udiv (
  input  logic        clk, rst, start,
  input  logic [39:0] n,
  input  logic [31:0] d,
  output logic        busy, done,
  output logic [39:0] q
);
  logic [39:0] nn; logic [32:0] r; logic [5:0] k;
  always_ff @(posedge clk) begin
    if (rst) begin busy <= 1'b0; done <= 1'b0; end
    else begin
      done <= 1'b0;
      if (start && !busy) begin busy <= 1'b1; nn <= n; r <= '0; k <= 6'd40; q <= '0; end
      else if (busy) begin
        automatic logic [32:0] r2 = {r[31:0], nn[39]};
        if (r2 >= {1'b0, d}) begin r <= r2 - {1'b0, d}; q <= {q[38:0], 1'b1}; end
        else begin r <= r2; q <= {q[38:0], 1'b0}; end
        nn <= {nn[38:0], 1'b0};
        k <= k - 6'd1;
        if (k == 6'd1) begin busy <= 1'b0; done <= 1'b1; end
      end
    end
  end
endmodule
