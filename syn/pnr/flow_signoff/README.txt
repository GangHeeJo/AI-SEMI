현수(hyunsu)의 results/job7_flow 사본(genus/innovus/quantus/signoff/sim 흐름). 원본은 수정하지 않았고, 이 폴더의 genus.tcl에서만 SDC를 팀 공통 조건으로 바꿈:
입출력 지연 0.2*T -> 0.250 ns, clock uncertainty 0.05 -> 0.100 ns (준영 P&R과 같은 조건, constraints_5ns.sdc와 동일).
사용: bash run_flow.sh <workdir> <TOP> <PER_ns> <UTIL> <rtl...> ; bash run_signoff.sh <workdir> <TOP> ; bash run_sim.sh <workdir> <TOP> <tb.sv> <rtl...>
