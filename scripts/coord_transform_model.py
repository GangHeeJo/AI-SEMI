#!/usr/bin/env python3
# Digital 2차 1단계 좌표변환 소프트웨어 레퍼런스 모델(오라클).
# 4x4 로컬 센서(steal_buf_polarity 출력의 row+col_mask로 복원되는 (x,y))를
# 64x64 world memory로 옮기는 계산을 RTL과 똑같은 정수 고정소수점 산술로 재현한다.
# 이 파일이 만드는 cos/sin LUT(정수값)이 그대로 RTL ROM 내용이 되므로,
# 여기서 계산이 틀리면 RTL도 같이 틀려야 정상 -- RTL 검증 시 이 함수와 비트 단위로 비교한다.
#
# 통합 회전 모델(θ 하나로 pan/tilt 이동 + roll 회전을 동시에 표현):
#   world_center(θ) = (Wc + R*cosθ, Hc + R*sinθ)   -- 시야 중심이 반지름 R 원호를 따라 이동
#   local_rot(θ)     = Rot(θ) · (x_c, y_c)          -- 4x4 내부 좌표도 같은 θ만큼 회전
#   world(X,Y) = round(world_center(θ) + local_rot(θ))
# cos(θ)/sin(θ)를 한 번만 계산해서 두 항 모두에 재사용 -- 회로 관점에서 공짜 재사용.

import math

N = 64                  # world memory 한 변 크기 (6bit)
N_THETA = 256            # theta LUT 크기 (8bit index, 2π를 256등분)
FRAC_BITS = 14           # cos/sin 고정소수점 fractional bits (Q1.14)
SCALE = 1 << FRAC_BITS
R = 20                   # 시야 중심이 도는 원호 반지름 (grid cell 단위, world grid 안에 여유있게 들어가도록)
WC, HC = N // 2, N // 2  # world grid 중심

# cos/sin LUT: RTL ROM에 그대로 옮길 정수 테이블. 정수 반올림으로 한 번만 고정.
COS_LUT = [round(math.cos(2 * math.pi * i / N_THETA) * SCALE) for i in range(N_THETA)]
SIN_LUT = [round(math.sin(2 * math.pi * i / N_THETA) * SCALE) for i in range(N_THETA)]


def _round_div(n, d):
    """n/d를 0에서 먼 방향으로 반올림(정수만 사용, RTL에서 그대로 구현 가능한 형태)."""
    if n >= 0:
        return (n + d // 2) // d
    return -((-n + d // 2) // d)


def local_xy_from_row_col(row, col):
    """steal_buf_polarity의 row(0~3)+col_mask 비트 위치(0~3) -> 로컬 (x,y).
    x=col, y=row로 정의(4x4 그리드), 중심 기준 2배 스케일(xc2=2x-3)로 반정수 없이 정수만 씀."""
    xc2 = 2 * col - 3   # col 0,1,2,3 -> -3,-1,1,3
    yc2 = 2 * row - 3
    return xc2, yc2


def transform(xc2, yc2, theta_idx):
    """로컬(반정수 스케일 xc2,yc2) + theta_idx -> world 좌표(X,Y). RTL과 동일해야 하는 핵심 함수."""
    theta_idx &= (N_THETA - 1)
    c, s = COS_LUT[theta_idx], SIN_LUT[theta_idx]

    # local_rot는 xc2(=2*xc)를 썼으므로 결과도 실제값의 2배 * SCALE 단위.
    local_rot_x_fx = xc2 * c - yc2 * s
    local_rot_y_fx = xc2 * s + yc2 * c
    # offset(R*cosθ)과 grid 중심(WC/HC)도 같은 2*SCALE 단위로 맞춰서 전부 더한 뒤
    # "절대 좌표" 전체를 단 한 번만 반올림한다 -- WC를 나중에 더하면 offset이 음수일 때
    # 반올림 방향이 절대좌표의 부호가 아니라 offset의 부호를 따라가 버리는 버그가 생김.
    total_x_fx = local_rot_x_fx + 2 * (R * c) + 2 * SCALE * WC
    total_y_fx = local_rot_y_fx + 2 * (R * s) + 2 * SCALE * HC

    denom = 2 * SCALE
    X = _round_div(total_x_fx, denom)
    Y = _round_div(total_y_fx, denom)
    assert 0 <= X < N and 0 <= Y < N, f"world 좌표가 grid 밖으로 나감: ({X},{Y}) theta_idx={theta_idx}"
    return X, Y


def build_world_mem(events):
    """events: (row, col, theta_idx, polarity) 리스트 -> world_mem[Y][X]=polarity, 쓰기 로그 반환.
    같은 칸에 여러 이벤트가 겹치면 마지막 값으로 덮어씀(1단계는 충돌정책 미정, 오라클은 최신값 기준)."""
    world_mem = [[None] * N for _ in range(N)]
    writes = []
    for row, col, theta_idx, polarity in events:
        xc2, yc2 = local_xy_from_row_col(row, col)
        X, Y = transform(xc2, yc2, theta_idx)
        world_mem[Y][X] = polarity
        writes.append((X, Y, polarity))
    return world_mem, writes


def export_lut_hex(path_cos, path_sin):
    """RTL $readmemh용 16bit 2's complement hex 덤프."""
    def to_hex16(v):
        return format(v & 0xFFFF, "04x")

    with open(path_cos, "w") as f:
        f.write("\n".join(to_hex16(v) for v in COS_LUT) + "\n")
    with open(path_sin, "w") as f:
        f.write("\n".join(to_hex16(v) for v in SIN_LUT) + "\n")


def demo():
    # theta_idx=0(θ=0): cos=SCALE, sin=0 -> 중심이 (WC+R, HC) 근방, 로컬 회전 없음
    X, Y = transform(*local_xy_from_row_col(0, 0), 0)
    assert (X, Y) == (51, 31), (X, Y)  # xc=yc=-1.5: X=WC-1.5+R=50.5->51, Y=HC-1.5=30.5->31

    # theta_idx=N_THETA//4(θ=90°): cos≈0, sin≈1 -> 중심이 (WC, HC+R) 근방
    X, Y = transform(*local_xy_from_row_col(1, 2), N_THETA // 4)
    assert abs(X - WC) <= 2 and abs(Y - (HC + R)) <= 2, (X, Y)

    # 부동소수점 참조와 정수 고정소수점 결과가 반올림 오차(<=1칸) 내로 일치하는지 무작위 검증
    import random
    random.seed(0)
    for _ in range(2000):
        row, col = random.randrange(4), random.randrange(4)
        theta_idx = random.randrange(N_THETA)
        xc2, yc2 = local_xy_from_row_col(row, col)
        X, Y = transform(xc2, yc2, theta_idx)
        theta = 2 * math.pi * theta_idx / N_THETA
        xc, yc = xc2 / 2.0, yc2 / 2.0
        fx = WC + xc * math.cos(theta) - yc * math.sin(theta) + R * math.cos(theta)
        fy = HC + xc * math.sin(theta) + yc * math.cos(theta) + R * math.sin(theta)
        assert abs(X - fx) <= 1 and abs(Y - fy) <= 1, (row, col, theta_idx, X, Y, fx, fy)

    print("coord_transform_model self-check PASS (identity/quarter-turn + 2000 random vs float)")


if __name__ == "__main__":
    demo()
