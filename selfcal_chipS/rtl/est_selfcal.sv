// Chip-S automatic pivot self-calibration (bootstrap FSM of job26 EstU._maybe_calibrate, exact integer form).
// Bit-exact spec: selfcal/sc_model.py SelfCal, SPEC.md.
//   per 'score' window of the 3-DOF bootstrap (q = pose after the window):
//     (cs, sn) = CORDIC12(-q0);  a = cs - 4096, s = sn       (R(-th) - I = [[a, -s], [s, a]], Q12)
//     tx, ty   = sat16(q1), sat16(q2)  (Q4 px; |.| > 32767 sets the sticky overflow flag)
//     N++, Sa += a, Ss += s, Saa += a^2 + s^2, Stx += tx, Sty += ty,
//     Sbx += a tx + s ty, Sby += -s tx + a ty, Stt += tx^2 + ty^2
//     m16 = |tx| + |ty| + ((min(|q0|, 65535) * KM) >> 10)   trigger when m16 >= MTHR << lv  (or N == NMAX)
//   solve (centred 2x2 LS, S = s_c I):
//     Sd = N Saa - Sa^2 - Ss^2,  T = N Stt - Stx^2 - Sty^2,
//     Bx = N Sbx - Sa Stx - Ss Sty,  By = N Sby + Ss Stx - Sa Sty
//     r2 >= 9/10  <=>  10 (Bx^2 + By^2) >= 9 Sd T          (no division in the decision)
//     u = round_half_away(256 B / Sd) px,  Q = P + u
//     result priority: notrigger > overflow > nomotion (T < N^2 TMIN^2) > singular (Sd <= 0) > r2low > range > accept
//   accept -> publish roll mode about Q with world continuity offset (Q10)
//     O10 = ((R12(-th)(Q - wP)) >>> 2) + (wO << 10) - (t << 6)
//   retry (cfg): nomotion / singular -> keep accumulating, next checkpoint at MTHR << (lv+1), up to lv = 3.
// Sequential arithmetic: one 18x18 signed multiplier with a registered product (per-window products), one 56x56 shift-add multiplier and one
// 120-bit restoring divider (solve, ~1.3k cycles once). While busy the estimator holds at its window start (sc_busy),
// so publication is atomic with respect to the estimator / world pipeline.
module est_selfcal #(
  parameter int SW = 960
)(
  input  logic        clk, rst,
  input  logic        en,                       // cfg_sc_en (static)
  input  logic        retry,                    // cfg_sc_retry (static)
  input  logic signed [11:0] cfg_px, cfg_py,    // bootstrap 3-DOF pivot P
  input  logic signed [11:0] cfg_wPx, cfg_wPy, cfg_wOx, cfg_wOy,
  input  logic        win_done,
  input  logic [1:0]  win_branch,
  input  logic signed [31:0] q0, q1, q2,
  output logic        busy,
  output logic        pub,                      // level: roll mode about the published pivot is active
  output logic        pub_set,                  // pulse (while busy): estimator zeroes v1, v2
  output logic signed [11:0] pub_px, pub_py,
  output logic signed [27:0] pub_O10x, pub_O10y,
  output logic [1:0]  sc_state,                 // 0 off, 1 bootstrap, 2 calibrated (rot1), 3 general (3-DOF kept)
  output logic [2:0]  sc_res,                   // last decision: 0 none 1 accept 2 r2low 3 nomotion 4 singular 5 range 6 ovf 7 notrigger
  output logic [1:0]  sc_lv,
  output logic [9:0]  sc_r2q10,                 // floor(1024 r2), saturated at 1023 (observability only)
  output logic signed [15:0] sc_ux, sc_uy,      // pivot estimate u = Q - P (px, saturated), valid after a decision
  output logic [9:0]  sc_n
);
  localparam int KM   = (2 * SW * 355 + 113) / 226;                    // round(pi * SW) via 355/113 (960 -> 3016, 240 -> 754)
  localparam int MTHR = (2 * SW * 16) / 5;
  localparam int TMIN = (16 * SW) / 100;
  localparam int TM2  = TMIN * TMIN;
  localparam int NMAX = 1023;

  typedef enum logic [5:0] {
    S_OFF, S_IDLE, S_CORD, S_P0, S_P1, S_P2, S_P3, S_P4, S_P5, S_P6, S_P7, S_P8, S_P9, S_CHK,
    S_M, S_MW, S_MA, S_DV, S_DVW, S_CLS, S_O0, S_O1, S_O2, S_O3, S_O4, S_O5, S_PUB, S_DONE
  } st_t;
  st_t st;
  logic [1:0] mst;                                    // mode state (sc_state)

  // ---------------------------------------------------------------- accumulators (widths: SPEC.md)
  logic [9:0]  N;
  logic signed [23:0] Sa, Ss;
  logic [36:0] Saa;
  logic signed [25:0] Stx, Sty;
  logic signed [39:0] Sbx, Sby;
  logic [41:0] Stt;
  logic ovf;
  logic [1:0] lv;
  // per-window operands
  logic signed [15:0] a, s, tx, ty;
  logic [15:0] aq0;
  logic signed [31:0] cq0, cq1, cq2;                  // captured pose
  logic signed [13:0] ccs, csn;                       // CORDIC12(-q0) of the captured window
  logic [19:0] m16;
  logic trig;

  // ---------------------------------------------------------------- CORDIC F=12
  logic c_start, c_busy, c_done; logic signed [13:0] c_cs, c_sn;
  est_cordic #(.F(12)) u_cord (.clk, .rst, .start(c_start), .ang(14'(-cq0)), .busy(c_busy), .done(c_done), .cs(c_cs), .sn(c_sn));

  // ---------------------------------------------------------------- 18x18 signed multiplier, product registered (pr)
  // operands set in state k are multiplied in state k+1 and the registered product pr is consumed in state k+2
  logic signed [17:0] ma, mb;
  logic signed [35:0] pr;
  wire  signed [35:0] mp = ma * mb;

  // ---------------------------------------------------------------- 56x56 sequential multiplier (signed via magnitude)
  logic        bm_start, bm_busy, bm_neg;
  logic [55:0] bm_a, bm_b;
  logic [111:0] bm_acc, bm_x;
  logic signed [112:0] bm_ps;                         // registered signed product (timing)
  logic [55:0] bm_y;
  logic [6:0]  bm_k;
  wire signed [112:0] bm_p = bm_neg ? -$signed({1'b0, bm_acc}) : $signed({1'b0, bm_acc});
  function automatic logic [55:0] mag56(input logic signed [55:0] v); return v[55] ? 56'(-v) : 56'(v); endfunction

  // ---------------------------------------------------------------- 120-bit restoring divider (unsigned)
  logic         dv_start, dv_busy;
  logic [119:0] dv_n, dv_q;
  logic [111:0] dv_d;
  logic [112:0] dv_r;
  logic [6:0]   dv_k;

  // ---------------------------------------------------------------- solve registers
  logic signed [55:0] Sd, T, Bx, By;                 // Sd < 2^48, T < 2^52, |B| < 2^52
  logic [111:0] B2, D, NM;
  logic [4:0]  op;                                   // micro-step
  logic signed [55:0] opa, opb;
  logic [119:0] ux_m, uy_m, r2_m;
  logic signed [12:0] Qx, Qy;
  logic signed [31:0] O10x, O10y;
  logic signed [27:0] o_acc;

  // ---------------------------------------------------------------- operand select for the solve micro-program
  //  op : product                      accumulate into
  //   0  N * Saa                       Sd  = +
  //   1  Sa * Sa                       Sd -=
  //   2  Ss * Ss                       Sd -=
  //   3  N * Stt                       T   = +
  //   4  Stx * Stx                     T  -=
  //   5  Sty * Sty                     T  -=
  //   6  N * Sbx                       Bx  = +
  //   7  Sa * Stx                      Bx -=
  //   8  Ss * Sty                      Bx -=
  //   9  N * Sby                       By  = +
  //  10  Ss * Stx                      By +=
  //  11  Sa * Sty                      By -=
  //  12  Bx * Bx                       B2  = +
  //  13  By * By                       B2 +=
  //  14  Sd * T   (if Sd > 0, T > 0)   D   =
  //  15  N * N                         NM  =
  //  16  NM * TM2                      NM  =
  always_comb begin
    opa = '0; opb = '0;
    case (op)
      5'd0:  begin opa = 56'(N);   opb = 56'(Saa); end
      5'd1:  begin opa = 56'(Sa);  opb = 56'(Sa);  end
      5'd2:  begin opa = 56'(Ss);  opb = 56'(Ss);  end
      5'd3:  begin opa = 56'(N);   opb = 56'(Stt); end
      5'd4:  begin opa = 56'(Stx); opb = 56'(Stx); end
      5'd5:  begin opa = 56'(Sty); opb = 56'(Sty); end
      5'd6:  begin opa = 56'(N);   opb = 56'(Sbx); end
      5'd7:  begin opa = 56'(Sa);  opb = 56'(Stx); end
      5'd8:  begin opa = 56'(Ss);  opb = 56'(Sty); end
      5'd9:  begin opa = 56'(N);   opb = 56'(Sby); end
      5'd10: begin opa = 56'(Ss);  opb = 56'(Stx); end
      5'd11: begin opa = 56'(Sa);  opb = 56'(Sty); end
      5'd12: begin opa = Bx;       opb = Bx;       end
      5'd13: begin opa = By;       opb = By;       end
      5'd14: begin opa = Sd;       opb = T;        end
      5'd15: begin opa = 56'(N);   opb = 56'(N);   end
      default: begin opa = 56'(NM[55:0]); opb = 56'(TM2); end
    endcase
  end

  assign busy = (st != S_OFF && st != S_IDLE) || (st == S_IDLE && mst == 2'd1 && win_done && win_branch == 2'd3);
  assign sc_state = mst;
  assign sc_n = N;
  assign sc_lv = lv;

  function automatic logic signed [15:0] sat16(input logic signed [31:0] v);
    return (v > 32'sd32767) ? 16'sd32767 : ((v < -32'sd32767) ? -16'sd32767 : v[15:0]);
  endfunction
  function automatic logic big16(input logic signed [31:0] v);
    return (v > 32'sd32767) || (v < -32'sd32767);
  endfunction
  function automatic logic signed [15:0] sat16w(input logic [119:0] m, input logic neg);
    logic signed [15:0] r;
    r = (m > 120'd32767) ? 16'sd32767 : $signed({1'b0, m[14:0]});
    return neg ? -r : r;
  endfunction

  always_ff @(posedge clk) begin
    if (rst) begin
      st <= S_OFF; mst <= 2'd0;
      N <= '0; Sa <= '0; Ss <= '0; Saa <= '0; Stx <= '0; Sty <= '0; Sbx <= '0; Sby <= '0; Stt <= '0; ovf <= 1'b0; lv <= '0;
      a <= '0; s <= '0; tx <= '0; ty <= '0; aq0 <= '0; cq0 <= '0; cq1 <= '0; cq2 <= '0; ccs <= '0; csn <= '0; m16 <= '0; trig <= 1'b0;
      c_start <= 1'b0; ma <= '0; mb <= '0; pr <= '0;
      bm_start <= 1'b0; bm_busy <= 1'b0; bm_neg <= 1'b0; bm_a <= '0; bm_b <= '0; bm_acc <= '0; bm_x <= '0; bm_y <= '0; bm_k <= '0;
      bm_ps <= '0;
      dv_start <= 1'b0; dv_busy <= 1'b0; dv_n <= '0; dv_q <= '0; dv_d <= '0; dv_r <= '0; dv_k <= '0;
      Sd <= '0; T <= '0; Bx <= '0; By <= '0; B2 <= '0; D <= '0; NM <= '0; op <= '0;
      ux_m <= '0; uy_m <= '0; r2_m <= '0; Qx <= '0; Qy <= '0; O10x <= '0; O10y <= '0; o_acc <= '0;
      pub <= 1'b0; pub_set <= 1'b0; pub_px <= '0; pub_py <= '0; pub_O10x <= '0; pub_O10y <= '0;
      sc_res <= '0; sc_r2q10 <= '0; sc_ux <= '0; sc_uy <= '0;
    end else begin
      c_start <= 1'b0; pub_set <= 1'b0; bm_start <= 1'b0; dv_start <= 1'b0;
      pr <= mp;
      // ---- sequential multiplier: bm_acc = |a| * |b|, one bit per cycle (56 cycles)
      if (bm_start) begin
        bm_busy <= 1'b1; bm_acc <= '0; bm_x <= {56'd0, bm_a}; bm_y <= bm_b; bm_k <= 7'd56;
      end else if (bm_busy) begin
        if (bm_y[0]) bm_acc <= bm_acc + bm_x;
        bm_x <= bm_x << 1; bm_y <= bm_y >> 1; bm_k <= bm_k - 7'd1;
        if (bm_k == 7'd1) bm_busy <= 1'b0;
      end
      // ---- restoring divider: dv_q = dv_n / dv_d (120 cycles); dv_d > 0 guaranteed by the caller
      if (dv_start) begin
        dv_busy <= 1'b1; dv_r <= '0; dv_k <= 7'd120;
      end else if (dv_busy) begin
        automatic logic [112:0] r2 = {dv_r[111:0], dv_n[119]};
        if (r2 >= {1'b0, dv_d}) begin dv_r <= r2 - {1'b0, dv_d}; dv_q <= {dv_q[118:0], 1'b1}; end
        else begin dv_r <= r2; dv_q <= {dv_q[118:0], 1'b0}; end
        dv_n <= dv_n << 1; dv_k <= dv_k - 7'd1;
        if (dv_k == 7'd1) dv_busy <= 1'b0;
      end

      case (st)
        S_OFF: if (en) begin st <= S_IDLE; mst <= 2'd1; end
        // ============ bootstrap: one observation per estimator 'score' window
        S_IDLE: if (mst == 2'd1 && win_done && win_branch == 2'd3) begin
          cq0 <= q0; cq1 <= q1; cq2 <= q2; c_start <= 1'b1; st <= S_CORD;
        end
        S_CORD: if (c_done) begin
          automatic logic signed [15:0] t1 = sat16(cq1);
          automatic logic signed [15:0] t2 = sat16(cq2);
          ccs <= c_cs; csn <= c_sn;
          a <= 16'(c_cs) - 16'sd4096; s <= 16'(c_sn); tx <= t1; ty <= t2;
          if (big16(cq1) || big16(cq2)) ovf <= 1'b1;
          aq0 <= (cq0 > 32'sd65535 || cq0 < -32'sd65535) ? 16'hFFFF : 16'(cq0[31] ? -cq0 : cq0);
          N <= N + 10'd1;
          Sa <= Sa + 24'(16'(c_cs) - 16'sd4096); Ss <= Ss + 24'(c_sn);
          Stx <= Stx + 26'(t1); Sty <= Sty + 26'(t2);
          st <= S_P0;
        end
        // per-window products: ma/mb set in state k, registered product pr consumed in state k+2
        S_P0: begin ma <= a;  mb <= a;  st <= S_P1; end
        S_P1: begin ma <= s;  mb <= s;  st <= S_P2; end
        S_P2: begin Saa <= Saa + 37'(pr); ma <= a; mb <= tx; st <= S_P3; end             // a^2
        S_P3: begin Saa <= Saa + 37'(pr); ma <= s; mb <= ty; st <= S_P4; end             // s^2
        S_P4: begin Sbx <= Sbx + 40'(pr); ma <= s; mb <= tx; st <= S_P5; end             // a tx
        S_P5: begin Sbx <= Sbx + 40'(pr); ma <= a; mb <= ty; st <= S_P6; end             // s ty
        S_P6: begin Sby <= Sby - 40'(pr); ma <= tx; mb <= tx; st <= S_P7; end            // s tx
        S_P7: begin Sby <= Sby + 40'(pr); ma <= ty; mb <= ty; st <= S_P8; end            // a ty
        S_P8: begin Stt <= Stt + 42'(pr); ma <= $signed({2'b00, aq0}); mb <= 18'(KM); st <= S_P9; end   // tx^2
        S_P9: begin Stt <= Stt + 42'(pr); st <= S_CHK; end                                // ty^2
        S_CHK: begin                                                                      // pr = min(|q0|,65535) * KM
          automatic logic [19:0] mm = 20'(tx[15] ? -tx : tx) + 20'(ty[15] ? -ty : ty) + 20'(pr[35:10]);
          automatic logic tg = {4'd0, mm} >= (24'(MTHR) << lv);
          m16 <= mm; trig <= tg;
          if (tg || N == 10'(NMAX)) begin op <= '0; st <= S_M; end
          else st <= S_IDLE;
        end
        // ============ solve: 17 products through the sequential multiplier
        S_M: begin
          bm_a <= mag56(opa); bm_b <= mag56(opb); bm_neg <= opa[55] ^ opb[55];
          if (op == 5'd14 && !(Sd > 0 && T > 0)) begin D <= '0; op <= op + 5'd1; end
          else begin bm_start <= 1'b1; st <= S_MW; end
        end
        S_MW: if (!bm_start && !bm_busy) begin bm_ps <= bm_p; st <= S_MA; end
        S_MA: begin
          case (op)
            5'd0:  Sd <= 56'(bm_ps);
            5'd1, 5'd2: Sd <= Sd - 56'(bm_ps);
            5'd3:  T <= 56'(bm_ps);
            5'd4, 5'd5: T <= T - 56'(bm_ps);
            5'd6:  Bx <= 56'(bm_ps);
            5'd7, 5'd8: Bx <= Bx - 56'(bm_ps);
            5'd9:  By <= 56'(bm_ps);
            5'd10: By <= By + 56'(bm_ps);
            5'd11: By <= By - 56'(bm_ps);
            5'd12: B2 <= bm_acc;
            5'd13: B2 <= B2 + bm_acc;
            5'd14: D <= bm_acc;
            default: NM <= bm_acc;
          endcase
          if (op == 5'd16) begin op <= '0; st <= S_DV; end
          else begin op <= op + 5'd1; st <= S_M; end
        end
        // ============ three divisions: ux, uy (if Sd > 0), r2q10 (if D > 0)
        S_DV: begin
          if (op == 5'd0 || op == 5'd1) begin
            if (Sd > 0) begin
              automatic logic [55:0] bm = mag56(op == 5'd0 ? Bx : By);
              dv_n <= ({64'd0, bm} << 8) + 120'(Sd >>> 1); dv_d <= 112'(Sd); dv_q <= '0; dv_start <= 1'b1; st <= S_DVW;
            end else begin
              if (op == 5'd0) ux_m <= '0; else uy_m <= '0;
              op <= op + 5'd1;
            end
          end else begin
            if (D != 0) begin dv_n <= {B2[109:0], 10'd0}; dv_d <= D; dv_q <= '0; dv_start <= 1'b1; st <= S_DVW; end
            else begin r2_m <= '0; st <= S_CLS; end
          end
        end
        S_DVW: if (!dv_start && !dv_busy) begin
          case (op)
            5'd0: ux_m <= dv_q;
            5'd1: uy_m <= dv_q;
            default: r2_m <= dv_q;
          endcase
          if (op == 5'd2) st <= S_CLS;
          else begin op <= op + 5'd1; st <= S_DV; end
        end
        // ============ classification
        S_CLS: begin
          automatic logic rng = (ux_m <= 120'd4095) && (uy_m <= 120'd4095);
          automatic logic signed [13:0] qx = 14'(cfg_px) + (Bx[55] ? -14'(ux_m[12:0]) : 14'(ux_m[12:0]));
          automatic logic signed [13:0] qy = 14'(cfg_py) + (By[55] ? -14'(uy_m[12:0]) : 14'(uy_m[12:0]));
          automatic logic [2:0] res;
          rng = rng && (qx >= -14'sd2048) && (qx <= 14'sd2047) && (qy >= -14'sd2048) && (qy <= 14'sd2047);
          if (!trig)                                 res = 3'd7;
          else if (ovf)                              res = 3'd6;
          else if ($unsigned(T) < {56'd0, NM[55:0]}) res = 3'd3;
          else if (Sd <= 0)                          res = 3'd4;
          else if ((B2 << 3) + (B2 << 1) < (D << 3) + D) res = 3'd2;
          else if (!rng)                             res = 3'd5;
          else                                       res = 3'd1;
          sc_res <= res;
          sc_r2q10 <= (r2_m > 120'd1023) ? 10'd1023 : r2_m[9:0];
          sc_ux <= sat16w(ux_m, Bx[55]); sc_uy <= sat16w(uy_m, By[55]);
          Qx <= qx[12:0]; Qy <= qy[12:0];
          if (res == 3'd1) st <= S_O0;
          else begin
            if (retry && (res == 3'd3 || res == 3'd4) && lv != 2'd3 && N != 10'(NMAX)) begin lv <= lv + 2'd1; mst <= 2'd1; end
            else mst <= 2'd3;
            st <= S_DONE;
          end
        end
        // ============ continuity offset O10 = (R12(-th)(Q - wP) >>> 2) + (wO << 10) - (t << 6)
        S_O0: begin ma <= ccs; mb <= 18'(Qx - 13'(cfg_wPx)); st <= S_O1; end
        S_O1: begin ma <= csn; mb <= 18'(Qy - 13'(cfg_wPy)); st <= S_O2; end
        S_O2: begin O10x <= 32'(pr); ma <= csn; mb <= 18'(Qx - 13'(cfg_wPx)); st <= S_O3; end          // cs dx
        S_O3: begin O10x <= ((O10x - 32'(pr)) >>> 2) + (32'(cfg_wOx) <<< 10) - (cq1 <<< 6);           // - sn dy
                    ma <= ccs; mb <= 18'(Qy - 13'(cfg_wPy)); st <= S_O4; end
        S_O4: begin O10y <= 32'(pr); st <= S_O5; end                                                   // sn dx
        S_O5: begin O10y <= ((O10y + 32'(pr)) >>> 2) + (32'(cfg_wOy) <<< 10) - (cq2 <<< 6); st <= S_PUB; end  // + cs dy
        S_PUB: begin
          pub <= 1'b1; pub_set <= 1'b1; pub_px <= Qx[11:0]; pub_py <= Qy[11:0];
          pub_O10x <= O10x[27:0]; pub_O10y <= O10y[27:0]; mst <= 2'd2; st <= S_DONE;
        end
        S_DONE: st <= S_IDLE;
        default: st <= S_OFF;
      endcase
    end
  end
endmodule
