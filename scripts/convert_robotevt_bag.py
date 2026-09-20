#!/usr/bin/env python3
# RobotEvt(Liu/Parra/Chin, CVPR 2021, github.com/liudaqikk/RobotEvt) PureRot 시퀀스를 UZH
# shapes_rotation과 정확히 같은 파일 포맷(events.txt: "t x y polarity", groundtruth.txt:
# "t tx ty tz qx qy qz qw")으로 변환한다 -- 이렇게 하면 build_uzh_eventmeta_nxn.py/
# build_uzh_pose_theta.py를 한 줄도 안 고치고 그대로 재사용할 수 있다.
#
# 입력: rosbag(.bag, dvs_msgs/EventArray 토픽)+GT 텍스트(t r11..r33 t1 t2 t3, UR5 로봇
# 기구학에서 직접 나온 값). 이벤트는 240x180 DAVIS240C -- UZH와 센서가 같아 패치 추출
# 스크립트도 그대로 맞음.
import math
import sys

from rosbags.highlevel import AnyReader
from pathlib import Path


def mat_to_quat(r11, r12, r13, r21, r22, r23, r31, r32, r33):
    """3x3 회전행렬(행 우선) -> (qx,qy,qz,qw). 표준 trace 기반 변환."""
    trace = r11 + r22 + r33
    if trace > 0:
        s = 0.5 / math.sqrt(trace + 1.0)
        qw = 0.25 / s
        qx = (r32 - r23) * s
        qy = (r13 - r31) * s
        qz = (r21 - r12) * s
    elif r11 > r22 and r11 > r33:
        s = 2.0 * math.sqrt(1.0 + r11 - r22 - r33)
        qw = (r32 - r23) / s
        qx = 0.25 * s
        qy = (r12 + r21) / s
        qz = (r13 + r31) / s
    elif r22 > r33:
        s = 2.0 * math.sqrt(1.0 + r22 - r11 - r33)
        qw = (r13 - r31) / s
        qx = (r12 + r21) / s
        qy = 0.25 * s
        qz = (r23 + r32) / s
    else:
        s = 2.0 * math.sqrt(1.0 + r33 - r11 - r22)
        qw = (r21 - r12) / s
        qx = (r13 + r31) / s
        qy = (r23 + r32) / s
        qz = 0.25 * s
    return qx, qy, qz, qw


def convert(bag_path, gt_path, out_events, out_groundtruth):
    n_events = 0
    with AnyReader([Path(bag_path)]) as reader, open(out_events, "w") as f:
        conns = [c for c in reader.connections if c.topic == "dvs/events"]
        events = []
        for conn, _ts, rawdata in reader.messages(connections=conns):
            msg = reader.deserialize(rawdata, conn.msgtype)
            for e in msg.events:
                t = e.ts.sec + e.ts.nanosec * 1e-9
                events.append((t, e.x, e.y, 1 if e.polarity else 0))
        events.sort(key=lambda e: e[0])  # 메시지 경계에서 살짝 뒤섞일 수 있어 안전하게 정렬
        for t, x, y, p in events:
            f.write(f"{t:.9f} {x} {y} {p}\n")
            n_events += 1

    n_poses = 0
    with open(gt_path) as fin, open(out_groundtruth, "w") as fout:
        for line in fin:
            parts = line.split()
            if len(parts) < 13:
                continue
            t = float(parts[0])
            r11, r12, r13, r21, r22, r23, r31, r32, r33 = (float(x) for x in parts[1:10])
            tx, ty, tz = (float(x) for x in parts[10:13])
            qx, qy, qz, qw = mat_to_quat(r11, r12, r13, r21, r22, r23, r31, r32, r33)
            fout.write(f"{t:.9f} {tx:.6f} {ty:.6f} {tz:.6f} {qx:.6f} {qy:.6f} {qz:.6f} {qw:.6f}\n")
            n_poses += 1

    print(f"events={n_events} -> {out_events}")
    print(f"poses={n_poses} -> {out_groundtruth}")


if __name__ == "__main__":
    if len(sys.argv) != 5:
        raise SystemExit("usage: convert_robotevt_bag.py <in.bag> <in_GT.txt> <out_events.txt> <out_groundtruth.txt>")
    convert(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])
