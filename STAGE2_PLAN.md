# Digital 2차 독립 진행 계획

## 0. 작업 원칙

- 작업 브랜치: `codex/ai-semi-stage2`
- 시작점: `ff9d5d2` (기존 Digital 2차 착수 전 마지막 1차 커밋)
- `main`의 파일, 커밋, 브랜치 상태는 사용자의 별도 지시 없이는 수정·병합·리베이스하지 않는다.
- 기존 2차 구현 결과는 설계 근거로 사용하지 않는다. 필요한 경우 나중에 독립 결과와 비교만 한다.
- 순서는 문제 정의 → 정답 모델 → 작은 RTL → 부하/PPA 측정 → 확장이다.

## 1. 권장 목표

> 광학 중심이 고정되고 pan/tilt/roll만 하는 DVS에서 이벤트가 실제
> 발생했을 때의 자세를 보존하고, 외부에서 주어진 자세로
> sensor-coordinate 이벤트를 구면 world-coordinate 스트림과 파노라마
> time surface로 변환하는 RTL 전처리기를 만든다.

회전 전용은 과제의 기하 조건이며, 일반 주행 자동차처럼 광학 중심이
이동하는 경우는 첫 목표가 아니다. 회로의 외부 계약은
`event + occurrence pose tag + transform parameters -> reference-coordinate
event`로 유지해, 나중에 depth/plane 변환기를 앞단에 붙일 수 있게 한다.

첫 연구 질문은 다음 하나로 제한한다.

> AER backlog가 있는 고속 운동에서 occurrence 시점의 pose를 보존하면, retire 시점 pose를 사용하는 방식보다 좌표 오차를 얼마나 줄일 수 있는가?

## 2. 첫 시나리오의 경계

### 포함

- 광학 중심이 고정된 pan/tilt/roll DVS
- 알려진 카메라 내부·외부 보정값
- 외부 IMU/odometry가 제공하는 pose 또는 transform version
- ON/OFF polarity 이벤트
- calibrated camera ray의 구면/equirectangular world-coordinate 변환
- occurrence timestamp 기반 파노라마 time surface

### 제외

- full SLAM과 loop closure
- pose 자체의 최초 추정
- depth 추정
- unknown-depth 일반 3D point cloud
- optical-center translation과 parallax
- 객체 검출과 주행 판단
- 전체 해상도 센서 어레이의 즉시 물리 구현
- 대형 플립플롭 world memory

광학 중심이 이동하면 metric world point를 얻기 위해 depth 또는 알려진
평면이 필요하다. 그 확장은 별도 문제로 남기고, 첫 단계는 depth 없이도
정확히 정의되는 rotation-only direction panorama로 제한한다.

## 3. 크기의 의미

- `4x4`: 16개 물리 픽셀 소스를 담당하는 AER leaf 검증 단위
- sensor resolution: 실제 카메라의 픽셀 수. 데이터셋의 native resolution을 따른다.
- world-grid size: 관측할 물리 영역과 cell resolution으로 결정한다.

4x4 leaf가 큰 영상을 돌아다니며 스캔하는 구조로 정의하지 않는다. 실제 큰 센서는 leaf를 공간적으로 복제하고 상위에서 병합한다.

초기 규모는 다음 순서를 따른다.

1. 4x4 leaf 하나로 기능과 시간 정확성 검증
2. 8x8, 즉 2x2 leaf로 tile 병합 검증
3. full-resolution trace replay와 PPA/대역폭 스케일 모델
4. 스케일 모델이 타당할 때만 더 큰 RTL 인스턴스화

## 4. 1차 AER 기준점

재사용 기준은 `aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity` v1이다.

현재 보장:

- 입력 `arrival[15:0]`, `polarity_in[15:0]`
- source별 depth-2 pending storage
- source 내부 FIFO 순서
- 두 개의 row/column-bitmap 출력 lane
- idle lane steal
- polarity와 주소의 정렬
- 명시적인 source별 `overrun`

현재 부족한 계약:

- occurrence timestamp 또는 pose version 없음
- 한 packet 안 column별 발생시각 구분 없음
- downstream `ready`와 output hold 없음
- polarity-aware 제품형 RX/unpacker 없음
- global event order 없음
- 큰 센서를 위한 tile coordinate와 상위 merge 없음

현재 `aer_tx64_cluster2_tree4`는 상위 tile arbiter가 아니다. 주소-only leaf 네 개를 독립 복제하고 8개 lane을 그대로 출력한다. 재사용 가능한 증거는 독립 leaf 복제의 선형 스케일링뿐이다.

## 5. 제안 데이터 계약

### Leaf 입력

- `arrival[15:0]`
- `polarity[15:0]`
- 같은 입력 사이클의 `pose_version`
- 같은 입력 사이클의 `occurrence_timestamp`
- 고정 또는 설정 가능한 `tile_origin_x`, `tile_origin_y`

### Leaf 내부 FIFO record

각 source의 두 슬롯을 다음 record로 취급한다.

```text
{polarity, pose_version, occurrence_timestamp}
```

`pose_version`과 `occurrence_timestamp`는 polarity와 동일한 push/pop 조건으로 저장한다.

### Leaf 출력 뒤 event adapter

row bitmap을 최대 8개의 독립 event record로 푼다.

```text
{valid, sensor_x, sensor_y, polarity, pose_version, occurrence_timestamp}
```

한 row packet의 네 column은 서로 다른 source FIFO에서 왔으므로 pose version과 timestamp도 column마다 독립적으로 출력해야 한다. lane 또는 packet당 tag 하나는 허용하지 않는다.

### 좌표변환 출력

```text
{valid, world_x, world_y, polarity, occurrence_tag, status}
```

`status`는 최소한 정상 변환, 투영 불가, map 범위 밖, downstream overflow를 구분한다. 이벤트가 조용히 사라지는 경로는 허용하지 않는다.

## 6. 좌표변환 정의

정답 모델에서는 외부에서 주어진 transform을 사용한다.

1. pixel `(u, v)`와 calibration으로 sensor ray 또는 plane coordinate를 계산한다.
2. `pose_version`에 해당하는 transform을 적용한다.
3. world-grid cell로 양자화한다.
4. 투영 불가와 범위 밖을 별도 상태로 보고한다.

첫 target은 calibrated sensor ray에 외부 회전을 적용한 뒤 구면
direction grid에 투영하는 것이다. 4x4 leaf에서는 이 비선형 투영을
local affine로 근사하며, full sensor에서는 tile마다 다른 calibration
계수가 필요하다. identity, 90/180도 회전과 실제 measured pose를 함께
검증한다.

RTL 연산 구조는 정답 모델과 workload 분석 뒤 다음 후보만 비교한다.

- 직접 고정소수점 transform
- 작은 calibration LUT + rigid transform
- event lane 수를 줄인 time-multiplexed transform + FIFO

측정 전에 CORDIC이나 대형 pose/pixel LUT를 선채택하지 않는다.

## 7. 단계와 종료 조건

### M0. 기준선 재현

할 일:

- 최종 v1의 random, real trace, conservation, polarity 회귀 실행
- latency의 평균뿐 아니라 p99, 최대, source 간 skew 측정
- downstream ready 부재를 인터페이스 계약에 명시

종료 조건:

- 기존 1차 결과가 독립 작업 폴더에서 재현됨
- pose tag 폭과 pose-history 보존 기간을 계산할 입력 수치 확보

### M1. 문제 정의와 정답 모델

할 일:

- sensor, vehicle, road/world frame을 그림과 식으로 고정
- floating-point oracle 작성
- 동일 수식의 fixed-point oracle 작성
- identity, 경계좌표, 회전, translation, pose 변경 중 backlog vector 생성

종료 조건:

- 좌표계 방향과 단위에 모호함 없음
- fixed-point 최대 오차가 0.5 world cell 이하
- overflow, rounding, saturation 규칙 확정

### M2. 응용 허용오차 결정

할 일:

- 실제 trace에 0.1%, 0.5%, 1%, 5%, 10% event loss 주입
- pose를 1, 2, 4, 8 AER cycle 늦춰 적용
- map overlap, edge contrast, feature 유지율 중 최소 한 지표 측정
- 평균 event rate뿐 아니라 burst 길이와 공간 집중도를 측정

종료 조건:

- 정상 동작 부하 envelope 확정
- 허용 loss, p99 latency, 최대 pose quantization error 확정
- 'accepted event 100% 정확'과 '입력 event 무손실'을 구분한 주장 확정

### M3. Pose-tagged 4x4 AER

할 일:

- polarity FIFO record에 pose version 추가
- column별 pose tag 출력 추가
- bitmap-to-event adapter 작성
- pose version wrap과 pose-history overwrite 방지 규칙 추가

필수 directed test:

- backlog 중 pose 변경
- 같은 row에 서로 다른 pose version 이벤트 합류
- depth-2 full과 grant 동시 발생
- pose version wrap 직전·직후
- reset과 drain

종료 조건:

- `generated = delivered + explicit_overrun`
- phantom, duplicate, source-order violation, polarity mismatch, pose-tag mismatch 모두 0
- accepted event는 반드시 occurrence pose를 참조

### M4. World-coordinate event stream

할 일:

- pose-history lookup
- 고정소수점 좌표변환
- world-address event 출력
- world memory 없이 oracle과 직접 비교

종료 조건:

- 모든 accepted event가 fixed-point oracle과 bit-exact
- floating-point 대비 오차가 0.5 cell 이하
- out-of-range와 invalid projection accounting 일치

### M5. 처리량/PPA 선택

할 일:

- transform lane 수 `K = 1, 2, 4, 8` 비교
- 작은 input FIFO 깊이 sweep
- 실제 trace와 synthetic hotspot/burst를 동일 조건으로 실행
- 45nm Genus에서 tag storage, adapter, transform을 분리 계측

종료 조건:

- 정상 부하 envelope에서 downstream drop 0인 가장 작은 K 선택
- p99/max latency와 PPA Pareto 표 확보
- 8 events/cycle 완전 병렬이 실제로 필요할 때만 채택

### M6. World memory

할 일:

- coordinate stream으로 binary occupancy, signed accumulator, timestamp surface를 소프트웨어 비교
- 응용 지표를 만족하는 가장 작은 cell format 하나만 선택
- 동일 cell 동시 write를 merge 또는 serialize
- SRAM/BRAM interface와 writer를 분리

종료 조건:

- memory update가 oracle과 일치
- 같은 cell 충돌 결과가 입력 순서에 의존하지 않거나 timestamp 규칙으로 결정적임
- memory macro 용량과 standard-cell writer PPA를 분리 보고

### M7. 8x8 tile merge

할 일:

- 최종 4x4 leaf 네 개 사용
- `global_x = 4*tile_x + local_col`, `global_y = 4*tile_y + local_row`
- tile별 buffering과 ready-aware upper merge 구현
- upper arbiter 상태는 실제 `valid && ready` 수락 때만 진행

종료 조건:

- tile별 starvation-free bound 검증
- tile ID와 global sensor coordinate round-trip 100%
- cross-tile skew, p99 latency, loss, link bandwidth 측정

### M8. 선택적 feedback

M0~M7 완료 뒤에만 진행한다.

- 외부 IMU pose를 초기값으로 사용
- 작은 yaw/translation 후보만 map alignment로 채점
- full bundle adjustment나 full SLAM은 구현하지 않는다.

## 8. 공통 평가 지표

### 정확성

- accepted-event coordinate/polarity/pose-tag mismatch: 0
- phantom/duplicate: 0
- fixed-point geometric error: 최대 0.5 world cell
- map update mismatch: 0

### 용량과 시간

- generated, accepted, AER overrun, transform overflow, out-of-map을 분리 집계
- events/cycle과 bits/event
- 평균, p50, p99, 최대 latency
- source/tile 간 최대 skew
- 정상 부하 envelope 안의 loss

### 구현 가능성

- area, power, critical path
- pose tag 추가분과 transform 추가분 분리
- P&R 가능하면 setup, hold, DRC, antenna 확인
- 대형 memory는 macro와 주변 로직을 분리 보고

## 9. 중단·재설계 조건

- rotation-only panorama 지표가 의미 없으면 memory RTL 전에 시나리오를 재정의한다.
- pose tag PPA가 허용되지 않으면 timestamp/pose encoding만 재검토하고 retire-pose로 되돌아가지 않는다.
- `K < 8`이 정상 부하에서 overflow를 만들면 FIFO만 계속 키우지 말고 K를 늘린다.
- full-resolution scaling에서 출력 링크가 병목이면 leaf 수를 더 늘리기 전에 상위 merge와 bandwidth 계약을 다시 정의한다.
- world memory가 전체 PPA를 지배하면 map 크기를 임의로 줄이지 말고 SRAM macro 또는 off-chip consumer 경계를 명시한다.

## 10. 현재 구현 상태와 다음 작업

2026-09-11 독립 브랜치 기준:

- M0: official full50, UZH, random conservation과 latency/skew 재현 완료
- M1: supplied-pose 구면 오라클, local affine fixed-point contract,
  8,503-event RTL bit-exact 및 240x180 sampled 4x4/8x8 region sweep 완료
- M3: column별 pose/timestamp를 보존하는 4x4 AER와 pose overwrite guard 완료
- M4: 8-parallel transform 4x4 top 및 ready/valid coordinate stream 완료
- M5 기능 endpoint: 4x4 K=1/2/4/8과 8x8 K=1 top,
  synthetic·backpressure·1 ms-bin UZH burst stress 및 기존 6개 Genus PPA 완료; 새 K=4
  banked-map 주변로직 PPA는 미측정
- M6 기능 prototype: 작은 reference surface, 외부 SRAM/BRAM handshake
  writer와 주소 기반 4-bank K=4 폐루프 완료. 실제 eventmeta ns timestamp를
  5 ns cycle로 양자화한 중앙 4x4 8,503-event replay도 완료했고, added
  read-response wait 0/2/8/32 cycle에서 모두 무손실이며 commit p99는
  7/9/15/39 cycle이다. memory macro PPA는 환경상 미측정
- M7 기능 prototype: 네 4x4 leaf의 tile coordinate, FIFO, upper merge,
  single transform 통합 완료. 네 leaf가 공유하는 8x8 coefficient region은
  measured-pose 전체센서 sweep의 오차 gate를 통과했다. 240x180의 690개
  region을 순서대로 갱신한 뒤 pose version을 원자적으로 publish하는
  controller와 두 개의 실제 tx64 region을 연결한 16x8 proof도 완료.
  두 인접 region의 전 픽셀을 두 measured pose에서 검사한 256-event
  physical-coefficient replay도 RTL bit-exact로 완료. 이어서 SHA가 고정된
  원본 240x180/23,126,288-event stream을 분석한 결과, 200 MHz 5 ns bin의
  동시 event 최대는 8이고 II=8 공유 server도 다음 timestamp batch와
  겹치지 않았다. 따라서 690개 local transform 복제가 아니라 중앙
  double-buffer coefficient table + shared K=1 transform을 다음 대상으로
  채택했다. 두 epoch 690x112-bit table, global count guard, shared lane과
  이미 직렬화된 sensor stream용 240x180 endpoint까지 RTL로 완료했다.
  shared lane의 관측 II는 2 cycle이다. 이어서 네 8x8 raw region을 실제
  Stage-1 leaf로 구성해 16x16 pulse aperture -> fair merge -> depth-8 shared
  FIFO -> 중앙 table/shared lane까지 닫았다. 6,164개 pulse의 blocked/AER
  overrun/leaf overflow/world 보존식과 두 pose의 old-slot 재사용을 검증했고,
  별도 16-input two-level merge도 4,782개 random token 보존과 fairness를
  통과했다. 이는 한 recording과 소규모 구조 proof이며 범용 보장은 아니다.

다음 순서는 다음과 같다.

1. 서버에서 K=4 banked-map 주변로직 PPA를 얻고 기존 단일-port/K 후보와
   공정하게 비교한다.
2. 완료: parallel-pixel 제품 경계의 raw 8x8 region과 네 region(16x16)
   merge/FIFO/중앙 table/shared lane을 구현했다. AER overrun은 admission
   제외, leaf-FIFO drop과 affine capture는 pose별 retire로 정확히 한 번
   반영한다.
3. 진행: 16x16 proof의 world stream을 기존 4-bank SRAM surface에 연결해
   configuration update, event burst, memory backpressure가 겹칠 때의
   완전한 보존식을 검증한다. 690-region tree는 이 소규모 proof 다음이다.
4. full-resolution 원 timestamp stream으로 region merge와 world-bank skew,
   downstream stall을 replay해 K=1/depth-8 채택을 재검증한다. 한 recording의
   무손실 결과를 다른 센서·장면으로 외삽하지 않는다. 직렬 endpoint는
   `upstream_epoch_empty`로 인터페이스 밖 old-tag backlog까지 table write
   barrier에 포함했으며, 실제 upstream과 연결해 이 계약도 검증한다.
5. supplied-pose map이 닫힌 뒤에만 frozen-map residual pose correction을
   원 timestamp 순서와 input SHA receipt가 보존된 recording-level held-out
   split에서 constant/IMU-only baseline보다 먼저 이긴 뒤 소프트웨어
   float→fixed 동일 metric을 통과시킨다. 그 전 estimator RTL은 HOLD한다.
