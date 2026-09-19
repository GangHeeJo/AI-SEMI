#!/usr/bin/env python3
# rtl/bayes_filter.v를 실제 UZH 이벤트로 검증하기 위한 기대값 벡터 생성.
# run_bayes_filter_fixed()(RTL과 동일한 정수 고정소수점 오라클, §131/132에서 확정한
# eps_shift=8/alpha=2)를 그대로 돌려 이벤트마다 (row,col,pol,map_theta)를 뽑는다 --
# theta_log만 새로 뽑을 뿐 알고리즘 자체는 §132에서 이미 검증된 것 그대로 재사용.
import sys

from bayes_filter_fixed_model import build_patch_events, run_bayes_filter_fixed
from rotation_estimate_model import build_transform_table

OUT_PATH = "tb/bayes_filter_uzh_vectors.txt"


def dump(x_center=112, y_center=87, n_events=400, eps_shift=8, alpha=2, out_path=OUT_PATH):
    table = build_transform_table(4)
    events = build_patch_events(x_center, y_center, 4)[:n_events]
    theta_log = []
    run_bayes_filter_fixed(events, table, eps_shift, alpha, theta_log=theta_log)
    with open(out_path, "w") as f:
        for (row, col, pol, _gt), map_theta in zip(events, theta_log):
            f.write(f"{row} {col} {pol} {map_theta}\n")
    print(f"{len(theta_log)} vectors -> {out_path}")


if __name__ == "__main__":
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 400
    dump(n_events=n)
