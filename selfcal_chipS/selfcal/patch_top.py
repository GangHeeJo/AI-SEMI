"""patch est_top.sv and chip_s_full.sv (baseline b9e6888) for the self-calibration ports."""
from pathlib import Path
H = Path(__file__).resolve().parent
SRC = H.parent / 'src_snapshot/rtl'

SC_PORTS = """  // ---- self-calibration
  input  logic        cfg_sc_en, cfg_sc_retry, cfg_rot_t,
  output logic [1:0]  sc_state,
  output logic [2:0]  sc_res,
  output logic [1:0]  sc_lv,
  output logic [9:0]  sc_r2q10,
  output logic signed [15:0] sc_ux, sc_uy,
  output logic [9:0]  sc_n,
  output logic        sc_pub,
  output logic signed [11:0] sc_px, sc_py,
"""


def patch(fn, reps):
    s = (SRC / fn).read_text(encoding='utf-8')
    for a, b in reps:
        assert s.count(a) == 1, (fn, a[:80])
        s = s.replace(a, b)
    (H / 'rtl' / fn).write_text(s, encoding='utf-8')
    print('patched', fn)


patch('est_top.sv', [
    ("""  input  logic signed [15:0] cfg_BY16,
  input  logic        init_started""", """  input  logic signed [15:0] cfg_BY16,
""" + SC_PORTS + """  input  logic        init_started"""),
    ("""  est_core #(.SW(SW), .SH(SH), .PW(PW), .NW(NW), .AW(AW), .REC(REC), .SHQ(SHQ)) u_core (.clk, .rst,""",
     """  logic sc_busy, sc_pub_set; logic signed [27:0] sc_O10x, sc_O10y; logic signed [31:0] q_o0, q_o1, q_o2;
  est_selfcal #(.SW(SW)) u_sc (.clk, .rst, .en(cfg_sc_en), .retry(cfg_sc_retry), .cfg_px, .cfg_py,
    .cfg_wPx, .cfg_wPy, .cfg_wOx, .cfg_wOy, .win_done, .win_branch, .q0(q_o0), .q1(q_o1), .q2(q_o2),
    .busy(sc_busy), .pub(sc_pub), .pub_set(sc_pub_set), .pub_px(sc_px), .pub_py(sc_py), .pub_O10x(sc_O10x), .pub_O10y(sc_O10y),
    .sc_state, .sc_res, .sc_lv, .sc_r2q10, .sc_ux, .sc_uy, .sc_n);
  est_core #(.SW(SW), .SH(SH), .PW(PW), .NW(NW), .AW(AW), .REC(REC), .SHQ(SHQ)) u_core (.clk, .rst,"""),
    ("""    .cfg_wPx, .cfg_wPy, .cfg_wOx, .cfg_wOy, .cfg_KA, .cfg_KX, .cfg_KY, .cfg_BY16,
    .init_started,""", """    .cfg_wPx, .cfg_wPy, .cfg_wOx, .cfg_wOy, .cfg_KA, .cfg_KX, .cfg_KY, .cfg_BY16,
    .cfg_rot_t(cfg_rot_t | cfg_sc_en), .sc_busy, .sc_pub, .sc_pub_set, .sc_px, .sc_py, .sc_O10x, .sc_O10y, .q_o0, .q_o1, .q_o2,
    .init_started,"""),
])

patch('chip_s_full.sv', [
    ("""  input  logic signed [15:0] cfg_BY16,
  input  logic        init_started""", """  input  logic signed [15:0] cfg_BY16,
""" + SC_PORTS + """  input  logic        init_started"""),
    ("""    .cfg_wPx, .cfg_wPy, .cfg_wOx, .cfg_wOy, .cfg_KA, .cfg_KX, .cfg_KY, .cfg_BY16,
    .init_started,""", """    .cfg_wPx, .cfg_wPy, .cfg_wOx, .cfg_wOy, .cfg_KA, .cfg_KX, .cfg_KY, .cfg_BY16,
    .cfg_sc_en, .cfg_sc_retry, .cfg_rot_t, .sc_state, .sc_res, .sc_lv, .sc_r2q10, .sc_ux, .sc_uy, .sc_n, .sc_pub, .sc_px, .sc_py,
    .init_started,"""),
])
