"""area/timing: share the rot_t rotation unit and k-step multipliers in est_core; register the signed product in
est_selfcal before accumulation. Scheduling only — bit-identical (verified by the full regression)."""
from pathlib import Path
H = Path(__file__).resolve().parent


def patch(fn, reps):
    p = H / 'rtl' / fn
    s = p.read_text(encoding='utf-8')
    for a, b in reps:
        assert s.count(a) == 1, (fn, a[:90])
        s = s.replace(a, b)
    p.write_text(s, encoding='utf-8')
    print('patched', fn)


patch('est_core.sv', [
    # shared rotation unit: operands muxed by state
    ("""  function automatic logic signed [17:0] kmul(input logic signed [13:0] c, input logic [15:0] d);
    logic signed [31:0] t; t = c * $signed({1'b0, d}); return 18'(t >>> 12);
  endfunction""", """  function automatic logic signed [17:0] kmul(input logic signed [13:0] c, input logic [15:0] d);
    logic signed [31:0] t; t = c * $signed({1'b0, d}); return 18'(t >>> 12);
  endfunction
  // one shared rotation unit (S_RB0 prev, S_RB1 key, S_RB2 fill) and one shared k-step unit (S_RTK prev, S_RTK2 key)
  logic signed [13:0] ru_c, ru_s; s32 ru_x, ru_y, ru_rx, ru_ry;
  logic signed [13:0] ku_c, ku_s; logic signed [17:0] ku_0x, ku_0y, ku_1x, ku_1y;"""),
    ("""                            S_NEXTDOF, S_SWAP, S_RT, S_RTW, S_RTK, S_RB0, S_RB1, S_RB2} st_t;""",
     """                            S_NEXTDOF, S_SWAP, S_RT, S_RTW, S_RTK, S_RTK2, S_RB0, S_RB1, S_RB2} st_t;"""),
    ("""  // plane port muxes
  always_comb begin""", """  always_comb begin
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
  always_comb begin"""),
    ("""        S_RTK: begin
          kp0x <= kmul(rcp, cfg_d1); kp0y <= kmul(rsp, cfg_d1); kp1x <= -kmul(rsp, cfg_d2); kp1y <= kmul(rcp, cfg_d2);
          kk0x <= kmul(rck, cfg_d1); kk0y <= kmul(rsk, cfg_d1); kk1x <= -kmul(rsk, cfg_d2); kk1y <= kmul(rck, cfg_d2);
          st <= S_FSTART;
        end""", """        S_RTK:  begin kp0x <= ku_0x; kp0y <= ku_0y; kp1x <= ku_1x; kp1y <= ku_1y; st <= S_RTK2; end
        S_RTK2: begin kk0x <= ku_0x; kk0y <= ku_0y; kk1x <= ku_1x; kk1y <= ku_1y; st <= S_FSTART; end"""),
    ("""        S_RB0: begin btx_p <= rotx(rcp, rsp, btx_p, bty_p); bty_p <= roty(rcp, rsp, btx_p, bty_p); st <= S_RB1; end
        S_RB1: begin btx_k <= rotx(rck, rsk, btx_k, bty_k); bty_k <= roty(rck, rsk, btx_k, bty_k); st <= S_RB2; end
        S_RB2: begin ftx <= rotx(rcf, rsf, ftx, fty); fty <= roty(rcf, rsf, ftx, fty); st <= S_WFP; end""",
     """        S_RB0: begin btx_p <= ru_rx; bty_p <= ru_ry; st <= S_RB1; end
        S_RB1: begin btx_k <= ru_rx; bty_k <= ru_ry; st <= S_RB2; end
        S_RB2: begin ftx <= ru_rx; fty <= ru_ry; st <= S_WFP; end"""),
])

patch('est_selfcal.sv', [
    ("""  logic [111:0] bm_acc, bm_x;""", """  logic [111:0] bm_acc, bm_x;
  logic signed [112:0] bm_ps;                         // registered signed product (timing)"""),
    ("""    S_M, S_MW, S_DV, S_DVW,""", """    S_M, S_MW, S_MA, S_DV, S_DVW,"""),
    ("""      bm_start <= 1'b0; bm_busy <= 1'b0; bm_neg <= 1'b0; bm_a <= '0; bm_b <= '0; bm_acc <= '0; bm_x <= '0; bm_y <= '0; bm_k <= '0;""",
     """      bm_start <= 1'b0; bm_busy <= 1'b0; bm_neg <= 1'b0; bm_a <= '0; bm_b <= '0; bm_acc <= '0; bm_x <= '0; bm_y <= '0; bm_k <= '0;
      bm_ps <= '0;"""),
    ("""        S_MW: if (!bm_start && !bm_busy) begin
          case (op)
            5'd0:  Sd <= 56'(bm_p);
            5'd1, 5'd2: Sd <= Sd - 56'(bm_p);
            5'd3:  T <= 56'(bm_p);
            5'd4, 5'd5: T <= T - 56'(bm_p);
            5'd6:  Bx <= 56'(bm_p);
            5'd7, 5'd8: Bx <= Bx - 56'(bm_p);
            5'd9:  By <= 56'(bm_p);
            5'd10: By <= By + 56'(bm_p);
            5'd11: By <= By - 56'(bm_p);""",
     """        S_MW: if (!bm_start && !bm_busy) begin bm_ps <= bm_p; st <= S_MA; end
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
            5'd11: By <= By - 56'(bm_ps);"""),
])
