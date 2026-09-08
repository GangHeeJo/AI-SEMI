#!/usr/bin/env python3
# 좌표변환 CORDIC 대안 -- coord_transform_model.py(직접 행렬곱 baseline)과 같은 결과를
# 곱셈기 없이(shift+add만) 내는지 검증하는 소프트웨어 오라클.
#
# 핵심 대수적 단순화: world = (Wc,Hc) + Rot(theta)*(R,0) + Rot(theta)*(xc,yc)
#                          = (Wc,Hc) + Rot(theta)*(xc+R, yc)
# 회전은 선형이라 두 항을 미리 합친 벡터 하나만 회전하면 됨(원래 baseline은 이 단순화를
# 안 쓰고 두 곱셈을 따로 했었음 -- CORDIC/RMCM에서는 이 단순화로 회전을 1회만 하면 됨).
#
# CORDIC(회전모드): 임의 각도를 象限(quadrant) 4등분으로 먼저 꺾어(0~90도 안으로) 넣고,
# 그 안에서 atan(2^-i) 각도들의 합으로 근사 -- 매 반복 shift+add만 씀, 곱셈기 불필요
# (게인 보정 1회만 예외, 그것도 고정 상수라 합성 시 shift+add로 최적화됨 -- RMCM과 같은 원리).
import math
from coord_transform_model import N, N_THETA, FRAC_BITS, SCALE, R, WC, HC, local_xy_from_row_col

N_ITER = 6  # CORDIC 반복 횟수 -- 4x4x256 전수 스윕(3~10회)으로 찾은 최소값(<=1칸 오차 만족하는 하한, 5회는 80/4096 실패)

# atan(2^-i)를 theta_idx와 같은 단위(정수 계산 위해 별도로 고정소수점화)로 미리 계산.
# 여기서는 CORDIC z 누산기를 "라디안 x SCALE(Q1.14)"로 두고 진행 -- theta_idx -> 라디안 변환은
# 처음 한 번만(상수곱, 그마저도 2*pi/256이라는 고정비율이라 RTL에서도 shift+add로 대체 가능).
ATAN_TABLE = [round(math.atan(2 ** -i) * SCALE) for i in range(N_ITER)]

# CORDIC 게인(반복 늘어날수록 1.646760258...에 수렴) 보정 -- 입력을 미리 1/K로 줄여둠.
_K = 1.0
for _i in range(N_ITER):
    _K *= math.sqrt(1 + 2 ** (-2 * _i))
INV_K_FX = round((1.0 / _K) * SCALE)  # 고정 상수 -- 곱셈기 아니라 상수곱(shift+add화 가능)


def _cordic_rotate_fx(x0, y0, z0_fx):
    """x0,y0(정수, xc+R/yc 스케일) 벡터를 z0_fx(Q1.14 라디안) 각도만큼 회전.
    반환은 (x,y) 정수, SCALE배 스케일(나중에 >>FRAC_BITS 필요)."""
    # 입력을 게인 보정(1/K)만큼 미리 줄임 -- 상수곱이라 shift+add로 대체 가능(RMCM과 동일 원리).
    x = (x0 * INV_K_FX)  # SCALE배 스케일
    y = (y0 * INV_K_FX)
    z = z0_fx
    for i in range(N_ITER):
        dx = y >> i
        dy = x >> i
        if z >= 0:
            x, y, z = x - dx, y + dy, z - ATAN_TABLE[i]
        else:
            x, y, z = x + dx, y - dy, z + ATAN_TABLE[i]
    return x, y  # SCALE배 스케일


def _round_div_pow2(n, shift):
    d = 1 << shift
    if n >= 0:
        return (n + d // 2) >> shift
    return -((-n + d // 2) >> shift)


def transform_cordic(xc2, yc2, theta_idx):
    """coord_transform_model.transform()과 같은 입출력 계약, CORDIC으로 계산."""
    theta_idx &= (N_THETA - 1)

    # 象限 折疊(quadrant folding): 상위 2bit로 90도 단위 사전회전(곱셈기 불필요, swap/negate만),
    # 하위 6bit(0~63 -> 0~63/256*360=약 88.6도, CORDIC 수렴범위 안)만 CORDIC이 처리.
    quadrant = (theta_idx >> 6) & 0x3
    residual = theta_idx & 0x3F

    # xc2,yc2는 2배 스케일(xc2=2*xc)이므로 R도 2배로 맞춰서 더함(정수만 사용).
    x0, y0 = xc2 + 2 * R, yc2
    if quadrant == 0:
        qx, qy = x0, y0
    elif quadrant == 1:
        qx, qy = -y0, x0
    elif quadrant == 2:
        qx, qy = -x0, -y0
    else:
        qx, qy = y0, -x0

    theta_res_rad = 2 * math.pi * residual / N_THETA
    z0_fx = round(theta_res_rad * SCALE)

    rx_fx, ry_fx = _cordic_rotate_fx(qx, qy, z0_fx)
    # rx_fx = SCALE * [Rot(theta)*(x0,y0)]_x 인데 x0=xc2+2R=2*(xc+R)로 이미 2배 스케일이 들어있으므로
    # (게인보정에서 곱한 SCALE은 CORDIC 자체 게인 K와 상쇄돼 결과엔 SCALE 한 번만 남음),
    # 최종 절대좌표로 만들려면 2*SCALE로만 나누면 됨 -- 반올림 1회.
    denom_shift = FRAC_BITS + 1  # 2*SCALE = 2^(14+1)
    dx = _round_div_pow2(rx_fx, denom_shift)
    dy = _round_div_pow2(ry_fx, denom_shift)

    X, Y = WC + dx, HC + dy
    return X, Y


def export_exhaustive_vectors(path):
    """coord_transform_model.export_exhaustive_vectors()와 같은 포맷, CORDIC 오라클 기준값."""
    with open(path, "w") as f:
        for row in range(4):
            for col in range(4):
                xc2, yc2 = local_xy_from_row_col(row, col)
                for theta_idx in range(N_THETA):
                    X, Y = transform_cordic(xc2, yc2, theta_idx)
                    f.write(f"{row} {col} {theta_idx} {X} {Y}\n")


def demo():
    from coord_transform_model import transform
    import random
    random.seed(1)
    max_err = 0
    mismatches_gt1 = 0
    for row in range(4):
        for col in range(4):
            xc2, yc2 = local_xy_from_row_col(row, col)
            for theta_idx in range(N_THETA):
                X0, Y0 = transform(xc2, yc2, theta_idx)
                Xc, Yc = transform_cordic(xc2, yc2, theta_idx)
                err = max(abs(X0 - Xc), abs(Y0 - Yc))
                max_err = max(max_err, err)
                if err > 1:
                    mismatches_gt1 += 1
    print(f"N_ITER={N_ITER} max_err(vs direct-multiply baseline)={max_err} cells, "
          f"mismatches>1cell={mismatches_gt1}/{4*4*N_THETA}")
    assert mismatches_gt1 == 0, "CORDIC이 baseline과 1칸 넘게 벌어지는 경우가 있음 -- N_ITER 늘리거나 원인 확인 필요"
    print("coord_transform_cordic_model self-check PASS (exhaustive vs baseline, <=1 cell)")


if __name__ == "__main__":
    demo()
