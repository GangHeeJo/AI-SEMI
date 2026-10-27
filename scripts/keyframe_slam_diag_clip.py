#!/usr/bin/env python3
# 진단(판정 기준 아님): keyframe_slam_test.py 의 C3 잔상 비교는 B1 월드맵이 2비트(최대 3)로 포화되고 K 맵은 키프레임 50~128장을 합산해
# 동적 범위가 달라 불공정할 수 있음. 모든 방법을 같은 조건(미포화 이벤트 히스토그램, 창별 추정 각도)으로 다시 잰다.
import sys
sys.path.insert(0, "scripts")
import numpy as np
import keyframe_slam_test as k

k.CLIP = 1e9
rows = []
for prof in ("P1", "P2", "P3"):
    for seed in (0, 1, 2):
        f, T = k.make_theta(k.PROFILES[prof]); scene = k.make_scene(seed); wins = k.gen_windows(scene, f, T, 400, seed); Tm = k.render_truth(scene)
        th1, _ = k.run_B1(wins); r = k.run_K(wins, 3.0, True, f)
        g1 = k.map_metrics(k.build_map(wins, th1), Tm)[0]; gk = k.map_metrics(k.build_map(wins, r["corr"]), Tm)[0]
        gt = k.map_metrics(k.build_map(wins, f((np.arange(len(wins)) + 0.5) * k.DT)), Tm)[0]
        rows.append(f"{prof}s{seed}  ghost% 미포화: B1 {g1 * 100:5.1f}  K-coarse(보정각) {gk * 100:5.1f}  참 각도 {gt * 100:5.1f}"); print(rows[-1], flush=True)
open("syn/reports/keyframe_slam/diag_unclipped_ghost.txt", "w", encoding="utf-8").write("\n".join(rows) + "\n")
