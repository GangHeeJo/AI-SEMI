#!/usr/bin/env python3
"""생체 모방 후보 2: 희소 부호화 / 해마의 지연 할당 -- 월드 메모리의 '쓰인 행'만 저장 공간을 갖는다(행 포인터 + K행 풀).

월드 메모리 1024x1024는 면적의 70% 이상이다. 실제 이벤트가 건드리는 행/칸이 드물다면 K행 풀과 행 포인터(행당 10비트)로 줄일 수 있다.
이 스크립트는 실제 이벤트(UZH shapes_rotation 전체, RobotEvt PureRot 전체)를 정답 자세(θ)로 월드 1024x1024에 옮겨
건드려진 행/칸 비율을 센다(센서 240x180 전체를 로컬 좌표로 사용, 시야 중심 궤도 반지름 R=352로 패치가 격자 안에 들어가게 함).

*** 사전 등록 기준(실행 전에 정함) ***
  B1. 건드려진 행 수가 1024의 50% 이하 -- UZH와 RobotEvt 둘 다. (행 풀로 면적을 절반 이하로 만들 수 있는 최소 조건)
  B2. 건드려진 칸이 전체의 25% 이하 -- 둘 다. (행 안이 거의 차 있으면 행 단위 할당은 의미가 작음)
  둘 다 통과해야 RTL(행 포인터 풀)로 넘어간다. 하나라도 실패하면 기각.
사용: (프로젝트 루트에서) python scripts/sparse_rows_test.py
"""
import math
import sys

import numpy as np
import pandas as pd
from scipy.spatial.transform import Rotation as Rot

N, N_THETA, WC = 1024, 1024, 512
R_ORBIT = 352
SENSOR_W, SENSOR_H = 240, 180


def world_cells(events_path, gt_path, name):
    ev = pd.read_csv(events_path, sep=" ", header=None, names=["t", "x", "y", "p"], dtype={"t": np.float64, "x": np.int16, "y": np.int16, "p": np.int8}).values
    g = np.loadtxt(gt_path)
    q0 = Rot.from_quat(g[0, 4:8])
    ang = np.array([2 * math.acos(min(1.0, abs((q0.inv() * Rot.from_quat(q)).as_quat()[3]))) for q in g[:, 4:8]])  # 시작 자세 대비 회전 크기(rad)
    t = ev[:, 0]
    keep = (t >= g[0, 0]) & (t <= g[-1, 0]); ev = ev[keep]; t = ev[:, 0]
    th = np.interp(t, g[:, 0], ang)
    idx = np.round(th / (2 * math.pi) * N_THETA).astype(np.int64) % N_THETA
    thq = idx * 2 * math.pi / N_THETA
    c, s = np.cos(thq), np.sin(thq)
    xc = ev[:, 1] - (SENSOR_W - 1) / 2.0; yc = ev[:, 2] - (SENSOR_H - 1) / 2.0
    X = np.rint(WC + R_ORBIT * c + xc * c - yc * s).astype(np.int64)
    Y = np.rint(WC + R_ORBIT * s + xc * s + yc * c).astype(np.int64)
    ok = (X >= 0) & (X < N) & (Y >= 0) & (Y < N)
    print(f"{name}: 이벤트 {len(ev):,}  θ 범위 {np.degrees(th.min()):.1f}~{np.degrees(th.max()):.1f}°  격자 밖 {100 * (1 - ok.mean()):.2f}%", flush=True)
    return X[ok], Y[ok]


def stats(X, Y):
    cells = np.unique(Y * N + X)
    rows = np.unique(Y)
    blocks = np.unique((Y // 16) * (N // 16) + X // 16)
    return len(rows) / N, len(cells) / (N * N), len(blocks) / ((N // 16) ** 2), len(rows)


if __name__ == "__main__":
    sets = [("UZH shapes_rotation", "shapes_rotation/events.txt", "shapes_rotation/groundtruth.txt"),
            ("RobotEvt PureRot", "common_traces_robotevt/robotevt_pureRot_slow_off.events.txt", "common_traces_robotevt/robotevt_pureRot_slow_off.groundtruth.txt")]
    ok_all = True
    for name, e, g in sets:
        X, Y = world_cells(e, g, name)
        fr, fc, fb, nr = stats(X, Y)
        b1, b2 = fr <= 0.5, fc <= 0.25
        print(f"  건드려진 행 {nr}/{N} = {fr * 100:.1f}%  칸 {fc * 100:.2f}%  16x16 블록 {fb * 100:.1f}%   B1(행<=50%) {b1}  B2(칸<=25%) {b2}", flush=True)
        ok_all &= b1 and b2
    print("결과:", "통과(RTL 후보)" if ok_all else "기각")
