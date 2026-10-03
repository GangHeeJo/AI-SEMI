import json, sys
import numpy as np
sys.path.insert(0, "scripts")
import run_hyunsu_estimator as R
work, truth = sys.argv[1], sys.argv[2]
grid = [dict(S=2, N=9), dict(S=4, N=9), dict(S=3, N=17), dict(S=2, N=17), dict(S=3, N=9, M=8192), dict(S=3, N=9, min_ev=2000), dict(S=3, N=9, span=4.0)]
for g in grid:
    cfg = dict(N=9, S=3, M=2048, refine=True, R=1, fwarp=True, sbits=4, min_ev=4500); cfg.update(g)
    r, est, qgt, k0 = R.run(work, "roll", cfg)
    v = ~np.isnan(est)
    print(json.dumps({"cfg": g, "mean_abs": round(r["mean_abs"], 2), "max_abs": round(r["max_abs"], 2), "final_err": round(r["final"], 2), "rms": round(r["rms"], 2)}), flush=True)
