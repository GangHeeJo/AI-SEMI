"""self-calibration RTL vectors from the integer model (sc_model): a full run FROM RESET (preroll, no GT, q_init = 0).
    python3 sc_vec.py <roll|pan> <tag> <retry 0|1> <extra windows after the final decision> [P=x,y]
-> out/vec/<tag>/: cfg.hex (tb_est layout + [53] sc_en [54] retry [55] rot_t [56] n_acc [57] n_sol [58] exp sc_state),
   words.hex, exp_fp.hex, exp_win.hex, exp_sc.hex, exp_acc.hex, exp_sol.hex, plane_*.hex, meta.json
"""
import sys, json, math
from pathlib import Path
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parent))
import sc_model as M
G = M.G
ds, tag, retry, extra = sys.argv[1], sys.argv[2], sys.argv[3] == '1', int(sys.argv[4])
P = tuple(int(v) for v in sys.argv[5].split('=')[1].split(',')) if len(sys.argv) > 5 else None
OUT = Path(__file__).resolve().parent / 'out/vec' / tag; OUT.mkdir(parents=True, exist_ok=True)
M64 = (1 << 64) - 1
h64 = lambda v: format(int(v) & M64, '016x')
h32 = lambda v: format(int(v) & 0xFFFFFFFF, '08x')

est = M.make_sc(ds, P=P, retry=retry)
st = G.Stream(ds)
fp = [est.wparams(list(est.q))]                       # preroll frame 0 (not started: pose = q)
win, scr = [], []
nf = st.nf; f = 1; wi = 0; stop_at = None
while f < nf:
    L = est.next_len()
    frames = list(range(f, min(f + L, nf)))
    evs = [st.frame(k) for k in frames]
    n = sum(len(e[0]) for e in evs)
    wev = (np.concatenate([e[0] for e in evs]), np.concatenate([e[1] for e in evs]),
           np.concatenate([np.full(len(e[0]), j, np.int8) for j, e in enumerate(evs)]))
    qc, per = est.begin_poses(len(frames)); est._applied = qc
    fp += [est.wparams(p) for p in per]
    est.end(wi, frames, wev, n)
    r = est.trace[-1]
    b = dict(idle=0, start=1, coast=2, score=3)[r['branch']]
    win.append([b, int(bool(r.get("key_upd", False))), r["L"], r["n"], *r["q_out"], *r["v_out"], *est.q_ref, *est.q_key, int(est.kplane is not None)])
    if b == 3:
        pad = [0] * 27
        scr.append((r['sc'] + pad)[:27] + (r['ks'] + pad)[:27])
    wi += 1; f += len(frames)
    if stop_at is None and est.sc.st in (M.ST_ROT1, M.ST_GEN):
        stop_at = wi + extra
    if stop_at is not None and wi >= stop_at:
        break
f1 = f
sc = est.sc
hist = getattr(est, 'sc_hist', [])
s0, s1 = st.wstart[0], st.wstart[f1]
col = int(st.fcol[0])
mode = 2
cfg = [mode, est.sc.P[0], est.sc.P[1], est.d[0], est.d[1], est.d[2], est.min_ev, *est.key_thr, est.key_w, 0, 0, 0, est.an,
       int(math.log2(est.wk)), est.Lfix, est.slowL, est.slow_div, sc.wP[0], sc.wP[1], sc.wO[0], sc.wO[1], 0, 0, 0, 0,
       0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, est.Lfix, 0, 1, 2,
       max(col, 0), int(col >= 0), int(st.fdir[0]), int(s1 - s0), f1, len(win),
       1, int(retry), 1, len(sc.acc_log), len(hist), sc.st]
assert len(cfg) == 59
with open(OUT / 'cfg.hex', 'w') as fh:
    fh.writelines(h64(v) + '\n' for v in cfg)
with open(OUT / 'words.hex', 'w') as fh:
    for w_ in st.words[s0:s1]:
        fh.write(''.join(format(int(v_), '02x') for v_ in w_) + '\n')
with open(OUT / 'exp_fp.hex', 'w') as fh:
    fh.writelines(f'{h32(a)} {h32(b)} {h32(c)} {h32(d)}\n' for a, b, c, d in fp)
with open(OUT / 'exp_win.hex', 'w') as fh:
    fh.writelines(' '.join(h32(v) for v in r) + '\n' for r in win)
with open(OUT / 'exp_sc.hex', 'w') as fh:
    fh.writelines(' '.join(h32(v) for v in r) + '\n' for r in scr)
with open(OUT / 'exp_acc.hex', 'w') as fh:
    fh.writelines(' '.join(h64(v) for v in r) + '\n' for r in sc.acc_log)
sat = lambda v: max(-32767, min(32767, v))
with open(OUT / 'exp_sol.hex', 'w') as fh:
    for o in hist:
        stt = M.ST_BOOT if not o['final'] else (M.ST_ROT1 if o['res'] == M.R_ACCEPT else M.ST_GEN)
        fh.write(' '.join(h64(v) for v in [o['res'], o['N'], o['Sd'], o['T'], o['Bx'], o['By'], o['r2q10'], sat(o['ux']), sat(o['uy']),
                                           o['lv'], stt, o['Qx'], o['Qy'], o['O10x'], o['O10y']]) + '\n')
NWd = -(-est.W * est.H // 64)


def plane_words(a):
    bits = np.zeros(NWd * 64, np.uint8); bits[:len(a)] = a
    bb = bits.reshape(NWd, 64).astype(np.uint64)
    return [int((bb[i] << np.arange(64, dtype=np.uint64)).sum()) for i in range(NWd)]


z = np.zeros(est.W * est.H, np.uint8)
for nm, arr in (('plane_prev', z), ('plane_key', z), ('plane_prev_end', est.prev),
                ('plane_key_end', est.kplane if est.kplane is not None else z)):
    with open(OUT / f'{nm}.hex', 'w') as fh:
        fh.writelines(h64(v) + '\n' for v in plane_words(arr))
br = [r[0] for r in win]
meta = dict(ds=ds, tag=tag, retry=retry, P=est.sc.P, frames=f1, windows=len(win), words=int(s1 - s0),
            branches={k: br.count(v) for k, v in dict(idle=0, start=1, coast=2, score=3).items()},
            n_acc=len(sc.acc_log), solves=[dict(win=o['win'], res=M.RNAME[o['res']], N=o['N'], lv=o['lv'], Qx=o['Qx_est'], Qy=o['Qy_est'],
                                                 r2q10=o['r2q10'], final=o['final']) for o in hist],
            final_state=sc.st, final_mode=est.mode, pivot=est.pivot, O10=est.O10)
json.dump(meta, open(OUT / 'meta.json', 'w'), indent=1)
print(json.dumps(meta))
