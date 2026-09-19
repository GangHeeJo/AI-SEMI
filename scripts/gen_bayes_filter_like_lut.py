#!/usr/bin/env python3
# rtl/bayes_filter.v용 우도 LUT(case문 콤비네이셔널 ROM) 생성. make_like_lut()(이미 §131/132에서
# 검증에 쓴 바로 그 함수, bayes_filter_fixed_model.py)를 그대로 재사용해 RTL과 오라클의 우도값이
# 한 비트도 안 틀리게 만든다 -- coord_transform LUT들의 export_lut_verilog_case()와 같은 관례
# (case문 콤비네이셔널 함수, $readmemh 안 씀).
import sys
sys.path.insert(0, "scripts")
from bayes_filter_fixed_model import make_like_lut, CNT_MAX

FUNC_NAME = "bayes_filter_like_lut"
OUT_PATH = "rtl/bayes_filter_like_lut.vh"


def export(alpha, path=OUT_PATH):
    lut = make_like_lut(alpha)
    lines = [f"function automatic [7:0] {FUNC_NAME}(input [3:0] n_on, input [3:0] n_off, input pol);",
             "  reg [8:0] key;", "  begin", "    key = {n_on, n_off, pol};", "    case (key)"]
    for (n_on, n_off, pol), val in lut.items():
        key = (n_on << 5) | (n_off << 1) | pol
        lines.append(f"      9'd{key}: {FUNC_NAME} = 8'd{val};")
    lines.append(f"      default: {FUNC_NAME} = 8'd0;")
    lines.append("    endcase")
    lines.append("  end")
    lines.append("endfunction")
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"CNT_MAX={CNT_MAX} alpha={alpha} -> {path} ({len(lut)} entries)")


if __name__ == "__main__":
    export(alpha=2)
