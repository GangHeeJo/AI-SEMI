# 월드 지도가 쌓이는 과정 영상 (roll)
- 만든 방법: 서버 `~/redred_gate_ext/video/make_snaps.py`(= `selfcal/video_make_snaps.py`)가 칩 S와 비트 일치하는 정수 기준 모델
  (`job24_est.EstS` 추정기 + `job24_world.py` 월드 규칙: 8 px 셀, 4비트 Morris 카운터, LFSR16)로 roll 전체(프레임 1~2060)를 재생하며
  4프레임마다 월드 메모리와 센서 이벤트를 저장(`snaps_roll.npz`, 12 MB, 저장소에는 올리지 않음). `selfcal/video_render.py`가 mp4로 그림.
- 칩 RTL이나 게이트 시뮬을 직접 찍은 영상이 아니라 **기준 모델 재생**이다(RTL 시뮬과의 비트 일치는 별도로 확인됨, progress.md §218 이후).
- 설정: roll 피벗 (480,352), 초기 자세는 ECC 기준. 결과 영상: `submission/월드지도_쌓이는과정_roll.mp4`.
- pan은 서버에 `pan_ecc_0915.npy`가 없어 아직 만들지 못함.
