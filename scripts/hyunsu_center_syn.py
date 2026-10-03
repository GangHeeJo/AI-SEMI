import json, sys
import numpy as np
sys.path.insert(0, "scripts")
import run_hyunsu_estimator as R
work, truth = sys.argv[1], sys.argv[2]
t = np.load(truth); e = np.array([np.cos(np.radians(float(t["e_deg"]))), np.sin(np.radians(float(t["e_deg"])))]); c0 = t["c0"]
for s_dom, nm in ((10, "wall layer s=10"), (45, "cage layer s=45"), (90, "clamp/rod layer s=90"), (150, "rod/floor layer s=150"), (-1, "his fixed center (480,352)")):
    ctr = (480.0, 352.0) if s_dom < 0 else tuple(c0 + s_dom * e)
    cfg = dict(N=9, S=3, M=2048, refine=True, R=1, fwarp=True, sbits=4, min_ev=4500)
    r, est, qgt, k0 = R.run(work, "roll", cfg, center=ctr)
    print(json.dumps({"center": nm, "xy": [round(ctr[0], 1), round(ctr[1], 1)], "mean_abs": round(r["mean_abs"], 2), "max_abs": round(r["max_abs"], 2), "final_err": round(r["final"], 2)}), flush=True)
