"""patch the baseline est_core.sv (src_snapshot, b9e6888) into the selfcal version (work/rtl/est_core.sv)."""
import sys
from pathlib import Path
H = Path(__file__).resolve().parent
s = (H.parent / 'src_snapshot/rtl/est_core.sv').read_text(encoding='utf-8')


def R(a, b, n=1):
    global s
    c = s.count(a)
    assert c == n, (c, a[:90])
    s = s.replace(a, b)


R("""  input  logic signed [15:0] cfg_BY16,
  // ---- initial state""", """  input  logic signed [15:0] cfg_BY16,
  // ---- self-calibration (selfcal): rot_t = rotate 3-DOF translation differences into the plane frame
  input  logic        cfg_rot_t,
  input  logic        sc_busy,                 // hold at the window start while the calibrator works
  input  logic        sc_pub,                  // published: roll mode about (sc_px, sc_py), world offset sc_O10 (Q10)
  input  logic        sc_pub_set,              // publication pulse: zero v1, v2
  input  logic signed [11:0] sc_px, sc_py,
  input  logic signed [27:0] sc_O10x, sc_O10y,
  output logic signed [31:0] q_o0, q_o1, q_o2,
  // ---- initial state""")
R("""  typedef logic signed [31:0] s32;
  localparam int NCAND = 27;""", """  typedef logic signed [31:0] s32;
  localparam int NCAND = 27;
  // ------------------------------------------------------------------ effective configuration (legacy when !sc_pub)
  wire [1:0] e_mode = sc_pub ? 2'd0 : cfg_mode;
  wire signed [11:0] e_px = sc_pub ? sc_px : cfg_px;
  wire signed [11:0] e_py = sc_pub ? sc_py : cfg_py;
  wire signed [11:0] e_wPx = sc_pub ? sc_px : cfg_wPx;
  wire signed [11:0] e_wPy = sc_pub ? sc_py : cfg_wPy;
  wire signed [31:0] e_wO10x = sc_pub ? 32'(sc_O10x) : (32'(cfg_wOx) <<< 10);
  wire signed [31:0] e_wO10y = sc_pub ? 32'(sc_O10y) : (32'(cfg_wOy) <<< 10);
  wire rot = cfg_rot_t && (e_mode == 2'd2);""")
R("""  always_comb case (cfg_mode) 2'd0: dofm""", """  always_comb case (e_mode) 2'd0: dofm""")
R("""  wire [4:0] ncand = (cfg_mode == 2'd2)""", """  wire [4:0] ncand = (e_mode == 2'd2)""")
R("""      dx = X - cfg_px; dy = Y - cfg_py;
      rx = cs * dx - sn * dy; ry = sn * dx + cs * dy;
      X = (rx >>> 12) + cfg_px; Y = (ry >>> 12) + cfg_py;""", """      dx = X - e_px; dy = Y - e_py;
      rx = cs * dx - sn * dy; ry = sn * dx + cs * dy;
      X = (rx >>> 12) + e_px; Y = (ry >>> 12) + e_py;""")
R("""  logic signed [13:0] tcs_p [9], tsn_p [9], tcs_k [9], tsn_k [9], fcs, fsn;
  s32 btx_p, bty_p, btx_k, bty_k, ftx, fty;""", """  logic signed [13:0] tcs_p [9], tsn_p [9], tcs_k [9], tsn_k [9], fcs, fsn;
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
  endfunction""")
R("""                            S_NEXTDOF, S_SWAP} st_t;""", """                            S_NEXTDOF, S_SWAP, S_RT, S_RTW, S_RTK, S_RB0, S_RB1, S_RB2} st_t;""")
R("""  wire [1:0] cd = (cfg_mode == 2'd1) ? 2'd1 : cdof;
  wire [3:0] tix = (cd == 2'd0) ? cc4 : 4'd4;
  wire signed [31:0] otx = (cd == 2'd1) ? coff(dd[1], cc4) : 32'sd0;
  wire signed [31:0] oty = (cd == 2'd2) ? coff(dd[2], cc4) : 32'sd0;""", """  wire [1:0] cd = (e_mode == 2'd1) ? 2'd1 : cdof;
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
  wire signed [31:0] otyk = rot ? 32'(rtyk) : oty;""")
R("""      sAp <= xyf(sx, sy, tcs_p[tix], tsn_p[tix], btx_p + otx, bty_p + oty);
      sAk <= xyf(sx, sy, tcs_k[tix], tsn_k[tix], btx_k + otx, bty_k + oty);""", """      sAp <= xyf(sx, sy, tcs_p[tix], tsn_p[tix], btx_p + otxp, bty_p + otyp);
      sAk <= xyf(sx, sy, tcs_k[tix], tsn_k[tix], btx_k + otxk, bty_k + otyk);""")
R("""      win_branch <= '0; win_keyupd <= 1'b0;
    end else begin""", """      win_branch <= '0; win_keyupd <= 1'b0;
      rcp <= '0; rsp <= '0; rck <= '0; rsk <= '0; rcf <= '0; rsf <= '0;
      kp0x <= '0; kp0y <= '0; kp1x <= '0; kp1y <= '0; kk0x <= '0; kk0y <= '0; kk1x <= '0; kk1y <= '0;
    end else begin""")
R("""        S_WSTART: begin
          if (preroll) L <= 4'd1;""", """        S_WSTART: if (!sc_busy) begin
          if (preroll) L <= 4'd1;""")
R("""          for (int k = 0; k < 3; k++)
            qc[k] <= started ? (q[k] + ((v[k] * ($signed({28'd0, Lp}) + $signed({28'd0, L}))) >>> 3)) : q[k];
          st <= S_FSTART;
        end""", """          for (int k = 0; k < 3; k++)
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
        S_RTK: begin
          kp0x <= kmul(rcp, cfg_d1); kp0y <= kmul(rsp, cfg_d1); kp1x <= -kmul(rsp, cfg_d2); kp1y <= kmul(rcp, cfg_d2);
          kk0x <= kmul(rck, cfg_d1); kk0y <= kmul(rsk, cfg_d1); kk1x <= -kmul(rsk, cfg_d2); kk1y <= kmul(rck, cfg_d2);
          st <= S_FSTART;
        end""")
R("""          if (!dofm[0] || tk > 5'd18) begin tk <= '0; st <= S_WFP; end""", """          if (!dofm[0] || tk > 5'd18) begin tk <= '0; st <= rot ? S_RB0 : S_WFP; end""")
R("""        // ============ world frame params
        S_WFP: begin""", """        // ============ rot_t: rotate the translation bases into the plane frames (one rotation per cycle)
        S_RB0: begin btx_p <= rotx(rcp, rsp, btx_p, bty_p); bty_p <= roty(rcp, rsp, btx_p, bty_p); st <= S_RB1; end
        S_RB1: begin btx_k <= rotx(rck, rsk, btx_k, bty_k); bty_k <= roty(rck, rsk, btx_k, bty_k); st <= S_RB2; end
        S_RB2: begin ftx <= rotx(rcf, rsf, ftx, fty); fty <= roty(rcf, rsf, ftx, fty); st <= S_WFP; end
        // ============ world frame params
        S_WFP: begin""")
R("""          if (cfg_mode == 2'd1) begin
            wang <=""", """          if (e_mode == 2'd1) begin
            wang <=""")
R("""            wdx  <= (cfg_mode == 2'd2) ? ap[1] : 32'sd0;
            wdy  <= (cfg_mode == 2'd2) ? ap[2] : 32'sd0;""", """            wdx  <= (e_mode == 2'd2) ? ap[1] : 32'sd0;
            wdy  <= (e_mode == 2'd2) ? ap[2] : 32'sd0;""")
R("""            fp_b0x <= 28'(($signed({20'd0, 12'd0}) + (s32'(cfg_wOx) <<< 10)) - (s32'(c10_cs) * s32'(cfg_wPx) - s32'(c10_sn) * s32'(cfg_wPy)) - (wdx <<< 6));
            fp_b0y <= 28'((s32'(cfg_wOy) <<< 10) - (s32'(c10_sn) * s32'(cfg_wPx) + s32'(c10_cs) * s32'(cfg_wPy)) - (wdy <<< 6));""",
  """            fp_b0x <= 28'(e_wO10x - (s32'(c10_cs) * s32'(e_wPx) - s32'(c10_sn) * s32'(e_wPy)) - (wdx <<< 6));
            fp_b0y <= 28'(e_wO10y - (s32'(c10_sn) * s32'(e_wPx) + s32'(c10_cs) * s32'(e_wPy)) - (wdy <<< 6));""")
R("""            dk <= (cfg_mode == 2'd1) ? 2'd1 : 2'd0; am <= '0; st <= S_ARG;""", """            dk <= (e_mode == 2'd1) ? 2'd1 : 2'd0; am <= '0; st <= S_ARG;""")
R("""          automatic logic [4:0] base = (cfg_mode == 2'd2) ? 5'(dk * 9) : 5'd0;""", """          automatic logic [4:0] base = (e_mode == 2'd2) ? 5'(dk * 9) : 5'd0;""", 2)
R("""          if (cfg_mode == 2'd2 && dk != 2'd2) begin""", """          if (e_mode == 2'd2 && dk != 2'd2) begin""")
R("""        default: st <= S_WSTART;
      endcase
    end
  end
endmodule""", """        default: st <= S_WSTART;
      endcase
      if (sc_pub_set) begin v[1] <= '0; v[2] <= '0; end      // entering 1-DOF mode (job26 _enter_rot1: v[1:] = 0)
    end
  end
  assign q_o0 = q[0]; assign q_o1 = q[1]; assign q_o2 = q[2];
endmodule""")
body = s.split('always_comb case (e_mode)')[1]
for bad in ('cfg_mode', 'cfg_px', 'cfg_py', 'cfg_wPx', 'cfg_wPy', 'cfg_wOx', 'cfg_wOy'):
    assert bad not in body, bad
(H / 'rtl/est_core.sv').write_text(s, encoding='utf-8')
print('patched est_core.sv, e_mode uses', s.count('e_mode'))
