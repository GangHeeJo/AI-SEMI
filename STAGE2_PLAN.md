# Digital 2차 독립 진행 계획

## 0. 작업 원칙

- 작업 브랜치: `codex/ai-semi-stage2`
- 시작점: `ff9d5d2` (기존 Digital 2차 착수 전 마지막 1차 커밋)
- `main`의 파일, 커밋, 브랜치 상태는 사용자의 별도 지시 없이는 수정·병합·리베이스하지 않는다.
- 기존 2차 구현 결과는 설계 근거로 사용하지 않는다. 필요한 경우 나중에 독립 결과와 비교만 한다.
- 순서는 문제 정의 → 정답 모델 → 작은 RTL → 부하/PPA 측정 → 확장이다.

## 1. 권장 목표

> 차량 탑재 DVS에서 이벤트가 실제 발생했을 때의 자세를 보존하고, 외부에서 주어진 자세를 이용해 sensor-coordinate 이벤트를 안정된 reference/world-coordinate 이벤트 스트림으로 변환하는 RTL 전처리기를 만든다.

자동차는 검증 시나리오다. 회로의 외부 계약은 `event + occurrence pose tag + transform parameters -> reference-coordinate event`로 두어 CCTV, 드론, 이동 로봇에도 재사용할 수 있게 한다.

첫 연구 질문은 다음 하나로 제한한다.

> AER backlog가 있는 고속 운동에서 occurrence 시점의 pose를 보존하면, retire 시점 pose를 사용하는 방식보다 좌표 오차를 얼마나 줄일 수 있는가?

## 2. 첫 시나리오의 경계

### 포함

- 차량에 단단히 고정된 전방 DVS
- 알려진 카메라 내부·외부 보정값
- 외부 IMU/odometry가 제공하는 pose 또는 transform version
- ON/OFF polarity 이벤트
- 도로 평면 또는 알려진 평면 위 이벤트의 2D 기준좌표 변환
- 온라인 처리를 위한 rolling local world frame

### 제외

- full SLAM과 loop closure
- pose 자체의 최초 추정
- depth 추정
- unknown-depth 일반 3D point cloud
- 객체 검출과 주행 판단
- 전체 해상도 센서 어레이의 즉시 물리 구현
- 대형 플립플롭 world memory

임의의 3D 장면에서 translation까지 포함한 metric world point를 얻으려면 depth 또는 평면 가정이 필요하다. 따라서 첫 단계는 도로 평면으로 제한한다. 회전-only는 공식 과제 조건으로 가정하지 않으며, 단순 회전은 정답 모델의 기본 sanity test로만 사용한다.

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
- 고정 또는 설정 가능한 `tile_origin_x`, `tile_origin_y`

### Leaf 내부 FIFO record

각 source의 두 슬롯을 다음 record로 취급한다.

```text
{polarity, pose_version}
```

`pose_version`은 polarity와 동일한 push/pop 조건으로 저장한다.

### Leaf 출력 뒤 event adapter

row bitmap을 최대 8개의 독립 event record로 푼다.

```text
{valid, sensor_x, sensor_y, polarity, pose_version}
```

한 row packet의 네 column은 서로 다른 source FIFO에서 왔으므로 pose version도 column마다 독립적으로 출력해야 한다. lane 또는 packet당 pose tag 하나는 허용하지 않는다.

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

첫 target은 알려진 도로 평면에 대한 homography다. pure rotation은 identity, 90/180도 회전, pan/tilt synthetic vector를 검증하는 데 사용한다.

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

- road-plane 가정에서 응용 지표가 의미 없으면 memory RTL 전에 시나리오를 재정의한다.
- pose tag PPA가 허용되지 않으면 timestamp/pose encoding만 재검토하고 retire-pose로 되돌아가지 않는다.
- `K < 8`이 정상 부하에서 overflow를 만들면 FIFO만 계속 키우지 말고 K를 늘린다.
- full-resolution scaling에서 출력 링크가 병목이면 leaf 수를 더 늘리기 전에 상위 merge와 bandwidth 계약을 다시 정의한다.
- world memory가 전체 PPA를 지배하면 map 크기를 임의로 줄이지 말고 SRAM macro 또는 off-chip consumer 경계를 명시한다.

## 10. 바로 다음 작업

1. M0 회귀 명령과 결과표 작성
2. v1에서 event latency/source skew를 뽑는 측정 testbench 확정
3. pose-tag 폭 산정을 위한 `max in-flight time / pose update period` 계산
4. M1 좌표계 정의와 floating-point oracle 작성

M0와 M1 결과가 나오기 전에는 Stage-2 RTL을 추가하지 않는다.
