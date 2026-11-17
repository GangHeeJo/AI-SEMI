# 서버 결과 보관 (2026-11-16~17)
서버 `~/redred_gate_ext/` 의 소용량 결과 사본. 대용량(SDF.X, 파형)은 서버에만 있음.
- `trans/`: 병진 과소측정 실험(§244~§248). `log_*.txt` 실행 로그, `obs_*.json` 정수 3-DOF 관측(dt=32/16/64/128, K1~K4), `h3k1.py`·`xcomp.py` 일회성 분석.
- `ecc/`: ECC 정답 재생성(§241). `roll_ecc.npy`, `register_roll.py`, `decode_dvs.py`, `register.log`.
- `gate_ext/`: 새 칩 추가 게이트 시뮬(§239~§240). roll_r1 MAX, pan_r1 MIN/MAX의 SUMMARY·CLOCK·SHA256·sdf.log·tb_run.sv.
기존 결과(`~/selfcal_20261115`, `~/hyunsu_round2`, `~/redred_gate_final` 등)는 수정하지 않음.
