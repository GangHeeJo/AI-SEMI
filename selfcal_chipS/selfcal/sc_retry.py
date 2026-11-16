import sys, math
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import sc_model as M
G = M.G
ds = sys.argv[1]
est = M.make_sc(ds, retry=True); st = G.Stream(ds); M.run(est, st)
for o in getattr(est, "sc_hist", []):
    r2 = (o["Bx"] ** 2 + o["By"] ** 2) / (o["Sd"] * o["T"]) if o["Sd"] * o["T"] else 0
    print("%s win=%3d lv=%d N=%3d res=%-9s Q=(%5d,%5d) R=%6.1f r2=%.4f t_std=%5.1f final=%s" % (ds, o["win"], o["lv"], o["N"], M.RNAME[o["res"]],
          o["Qx_est"], o["Qy_est"], math.hypot(o["ux"], o["uy"]), r2, math.sqrt(o["T"]) / o["N"] / 16, o["final"]))
print(ds, "final mode", est.mode, "pivot", est.pivot, "O10", est.O10)
