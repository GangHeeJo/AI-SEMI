"""timing: register the 18x18 product (pr) before accumulation in est_selfcal (scheduling only, bit-identical)."""
from pathlib import Path
p = Path(__file__).resolve().parent / 'rtl/est_selfcal.sv'
s = p.read_text(encoding='utf-8')


def R(a, b):
    global s
    assert s.count(a) == 1, a[:80]
    s = s.replace(a, b)


R("""    S_OFF, S_IDLE, S_CORD, S_P0, S_P1, S_P2, S_P3, S_P4, S_P5, S_P6, S_P7, S_P8, S_CHK,
    S_M, S_MW, S_DV, S_DVW, S_CLS, S_O0, S_O1, S_O2, S_O3, S_O4, S_PUB, S_DONE""",
  """    S_OFF, S_IDLE, S_CORD, S_P0, S_P1, S_P2, S_P3, S_P4, S_P5, S_P6, S_P7, S_P8, S_P9, S_CHK,
    S_M, S_MW, S_DV, S_DVW, S_CLS, S_O0, S_O1, S_O2, S_O3, S_O4, S_O5, S_PUB, S_DONE""")
R("""  // ---------------------------------------------------------------- 18x18 signed multiplier (combinational)
  logic signed [17:0] ma, mb;
  wire  signed [35:0] mp = ma * mb;""", """  // ---------------------------------------------------------------- 18x18 signed multiplier, product registered (pr)
  // operands set in state k are multiplied in state k+1 and the registered product pr is consumed in state k+2
  logic signed [17:0] ma, mb;
  logic signed [35:0] pr;
  wire  signed [35:0] mp = ma * mb;""")
R("""      c_start <= 1'b0; ma <= '0; mb <= '0;""", """      c_start <= 1'b0; ma <= '0; mb <= '0; pr <= '0;""")
R("""      c_start <= 1'b0; pub_set <= 1'b0; bm_start <= 1'b0; dv_start <= 1'b0;""",
  """      c_start <= 1'b0; pub_set <= 1'b0; bm_start <= 1'b0; dv_start <= 1'b0;
      pr <= mp;""")
R("""        // per-window products through the 18x18 multiplier: ma/mb set in state k, product used in state k+1
        S_P0: begin ma <= a;  mb <= a;  st <= S_P1; end
        S_P1: begin Saa <= Saa + 37'(mp); ma <= s; mb <= s; st <= S_P2; end
        S_P2: begin Saa <= Saa + 37'(mp); ma <= a; mb <= tx; st <= S_P3; end
        S_P3: begin Sbx <= Sbx + 40'(mp); ma <= s; mb <= ty; st <= S_P4; end
        S_P4: begin Sbx <= Sbx + 40'(mp); ma <= s; mb <= tx; st <= S_P5; end
        S_P5: begin Sby <= Sby - 40'(mp); ma <= a; mb <= ty; st <= S_P6; end
        S_P6: begin Sby <= Sby + 40'(mp); ma <= tx; mb <= tx; st <= S_P7; end
        S_P7: begin Stt <= Stt + 42'(mp); ma <= ty; mb <= ty; st <= S_P8; end
        S_P8: begin Stt <= Stt + 42'(mp); ma <= $signed({2'b00, aq0}); mb <= 18'(KM); st <= S_CHK; end
        S_CHK: begin
          automatic logic [19:0] mm = 20'(tx[15] ? -tx : tx) + 20'(ty[15] ? -ty : ty) + 20'(mp[35:10]);""",
  """        // per-window products: ma/mb set in state k, registered product pr consumed in state k+2
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
          automatic logic [19:0] mm = 20'(tx[15] ? -tx : tx) + 20'(ty[15] ? -ty : ty) + 20'(pr[35:10]);""")
R("""        S_O0: begin ma <= ccs; mb <= 18'(Qx - 13'(cfg_wPx)); st <= S_O1; end
        S_O1: begin O10x <= 32'(mp); ma <= csn; mb <= 18'(Qy - 13'(cfg_wPy)); st <= S_O2; end
        S_O2: begin O10x <= ((O10x - 32'(mp)) >>> 2) + (32'(cfg_wOx) <<< 10) - (cq1 <<< 6);
                    ma <= csn; mb <= 18'(Qx - 13'(cfg_wPx)); st <= S_O3; end
        S_O3: begin O10y <= 32'(mp); ma <= ccs; mb <= 18'(Qy - 13'(cfg_wPy)); st <= S_O4; end
        S_O4: begin O10y <= ((O10y + 32'(mp)) >>> 2) + (32'(cfg_wOy) <<< 10) - (cq2 <<< 6); st <= S_PUB; end""",
  """        S_O0: begin ma <= ccs; mb <= 18'(Qx - 13'(cfg_wPx)); st <= S_O1; end
        S_O1: begin ma <= csn; mb <= 18'(Qy - 13'(cfg_wPy)); st <= S_O2; end
        S_O2: begin O10x <= 32'(pr); ma <= csn; mb <= 18'(Qx - 13'(cfg_wPx)); st <= S_O3; end          // cs dx
        S_O3: begin O10x <= ((O10x - 32'(pr)) >>> 2) + (32'(cfg_wOx) <<< 10) - (cq1 <<< 6);           // - sn dy
                    ma <= ccs; mb <= 18'(Qy - 13'(cfg_wPy)); st <= S_O4; end
        S_O4: begin O10y <= 32'(pr); st <= S_O5; end                                                   // sn dx
        S_O5: begin O10y <= ((O10y + 32'(pr)) >>> 2) + (32'(cfg_wOy) <<< 10) - (cq2 <<< 6); st <= S_PUB; end  // + cs dy""")
R("""// Sequential arithmetic: one 18x18 signed multiplier (per-window products),""",
  """// Sequential arithmetic: one 18x18 signed multiplier with a registered product (per-window products),""")
p.write_text(s, encoding='utf-8')
print('ok')
