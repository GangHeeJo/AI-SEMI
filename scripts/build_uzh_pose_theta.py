#!/usr/bin/env python3
# UZH shapes_rotation 원본 groundtruth pose(모션캡처 실측, "timestamp tx ty tz qx qy qz qw" 형식)를
# 읽어서, 1단계 좌표변환에 쓸 단일 회전각 theta(t)를 만든다.
#
# 우리 1단계 모델은 회전을 각 하나(theta)로 통합해서 다루므로(coord_transform_model.py),
# 실제 3D 자세(quaternion)를 그대로 쓰지 않고 "시작 자세 대비 지금까지 회전한 각도 크기"
# 하나로 축약한다: relative_q = q(t0)^-1 * q(t), theta(t) = 2*acos(|relative_q.w|).
# 이건 회전축이 뭐든 상관없이 "얼마나 돌았는지"만 재는 값이라, V1의 "회전 1축" 단순화와
# 정확히 대응된다(축이 여러 개 섞여도 magnitude 하나로 정직하게 뭉뚱그린다는 걸 명시).
import bisect
import math
import sys

N_THETA = 256  # coord_transform_model.py와 반드시 같은 값이어야 함


def load_groundtruth(path):
    """timestamp(sec, float) tx ty tz qx qy qz qw 형식 텍스트 -> (ts_ns 리스트, quat 리스트)."""
    ts_ns, quats = [], []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) < 8:
                continue
            t = float(parts[0])
            qx, qy, qz, qw = (float(x) for x in parts[4:8])
            ts_ns.append(round(t * 1e9))
            quats.append((qx, qy, qz, qw))
    if not ts_ns:
        raise SystemExit(f"groundtruth 파싱 결과가 비어있음: {path} -- 포맷이 예상과 다른지 확인 필요")
    return ts_ns, quats


def quat_conj(q):
    x, y, z, w = q
    return (-x, -y, -z, w)


def quat_mul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
        aw * bw - ax * bx - ay * by - az * bz,
    )


def relative_angle(q0, q):
    """q0 -> q로 가는 회전의 각도 크기(0~2pi, magnitude만이라 항상 양수)."""
    rel = quat_mul(quat_conj(q0), q)
    w = max(-1.0, min(1.0, abs(rel[3])))  # 부호 모호성(q, -q가 같은 회전) 제거
    return 2.0 * math.acos(w)


def build_theta_lookup(gt_ts_ns, gt_quats):
    """groundtruth 샘플마다 시작 자세 대비 회전각 theta(rad)를 계산, (ts_ns, theta) 정렬 리스트 반환."""
    q0 = gt_quats[0]
    return list(zip(gt_ts_ns, (relative_angle(q0, q) for q in gt_quats)))


def theta_at(theta_lookup, ts_ns_list, query_ns):
    """query_ns 시각의 theta를 선형보간. groundtruth 표본 간격(모션캡처, 보통 수백Hz)이
    이벤트 간격보다 촘촘하다는 전제 -- 벗어나면 양끝값으로 clamp."""
    i = bisect.bisect_left(ts_ns_list, query_ns)
    if i <= 0:
        return theta_lookup[0][1]
    if i >= len(ts_ns_list):
        return theta_lookup[-1][1]
    t0, th0 = theta_lookup[i - 1]
    t1, th1 = theta_lookup[i]
    if t1 == t0:
        return th0
    frac = (query_ns - t0) / (t1 - t0)
    return th0 + frac * (th1 - th0)


def theta_to_idx(theta_rad):
    idx = round(theta_rad / (2 * math.pi) * N_THETA)
    return idx % N_THETA


def export_cycle_theta(groundtruth_path, out_path, max_cyc, bin_s=0.001):
    """통합 파이프라인 검증용: convert_uzh_to_cyclemask.py와 같은 cyc<->시간 매핑(1cyc=1ms)으로
    사이클 0~max_cyc마다 살아있는 theta_idx 한 줄씩 덤프("cyc theta_idx"). steal_buf_polarity의
    버퍼링 때문에 이벤트가 발생 사이클보다 늦게 배출될 수 있어서, 통합 TB는 "배출되는 그 사이클의
    살아있는 theta"를 쓴다(이벤트 자체의 theta_idx 컬럼이 아니라) -- 이게 1단계 설계의 실제 동작."""
    gt_ts_ns, gt_quats = load_groundtruth(groundtruth_path)
    theta_lookup = build_theta_lookup(gt_ts_ns, gt_quats)
    ts_only = [t for t, _ in theta_lookup]
    with open(out_path, "w") as out:
        for cyc in range(max_cyc + 1):
            query_ns = round(cyc * bin_s * 1e9)
            theta = theta_at(theta_lookup, ts_only, query_ns)
            out.write(f"{cyc} {theta_to_idx(theta)}\n")
    print(f"cycle theta exported: 0..{max_cyc} -> {out_path}")


def augment_eventmeta(eventmeta_path, groundtruth_path, out_path):
    gt_ts_ns, gt_quats = load_groundtruth(groundtruth_path)
    theta_lookup = build_theta_lookup(gt_ts_ns, gt_quats)
    ts_only = [t for t, _ in theta_lookup]

    with open(eventmeta_path) as f, open(out_path, "w") as out:
        header = f.readline().rstrip("\n")
        out.write(header + "\ttheta_idx\n")
        n = 0
        for line in f:
            line = line.rstrip("\n")
            occurrence_ts_ns = int(line.split("\t")[-1])
            theta = theta_at(theta_lookup, ts_only, occurrence_ts_ns)
            out.write(f"{line}\t{theta_to_idx(theta)}\n")
            n += 1
    print(f"augmented {n} events -> {out_path}")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit("usage: build_uzh_pose_theta.py <eventmeta.tsv> <groundtruth.txt> <out.tsv>")
    augment_eventmeta(sys.argv[1], sys.argv[2], sys.argv[3])
