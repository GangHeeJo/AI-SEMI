# 이벤트 카메라 월드맵·로봇·삼성 DVS 문헌 노트 (2026-10-05)

읽은 정도를 표시한다: **[본문]** = 본문 전체를 읽고 정리, **[발표]** = 슬라이드 27쪽을 직접 열어 봄, **[목록]** = 제목/요약만 확인(미정독, 정독 후 갱신 필요).

## 1. Ryu, "Industrial DVS Design; Key Features and Applications" (Samsung S.LSI, CVPR'19 workshop) [발표]
URL: https://rpg.ifi.uzh.ch/docs/CVPR19workshop/CVPRW19_Eric_Ryu_Samsung.pdf (PDF가 이미지 위주라 슬라이드를 렌더링해서 판독)
- 세대: Gen1(2014 R&D, 640x480, 9um, 90nm BSI CIS, 최대 6.5 Meps, 15 mW) / Gen2(2016, ISSCC'17, 최대 300 Meps, G-AER, MIPI 1Gbps 4lane, 80 mW) / **Gen3(2018 제품 버전, 유효 2000fps 이상, 전역 hold/reset, 열 순차 스캔 읽기, 65 mW)** / Gen4(R&D, 1280x960, 4.95um, 2-stack 웨이퍼 본딩, 1000fps, 140 mW, 안티플리커·노이즈 제거 블록).
- 10~13쪽: **불공정 중재(unfair arbitration)가 만드는 아티팩트와 지연**, AER이 만드는 지연과 움직임 왜곡, 열 순차 스캔으로 타임스탬프 오차를 줄임 -> 우리 1차(공정 중재, 영구 기아 해결)와 같은 문제 의식.
- 응용: 스마트홈 사람 감지(엣지 Exynos 7570 92 ms, 재현율 92~99%, 오탐 1%, CIS 대비 네트워크 11.4배 빠름, 프라이버시), DVS-SLAM(100 Hz 6-DoF, CIS 대비 마지막 위치 오차 3.2 cm vs 130 cm, 드리프트 0.28% vs 13.6%), DVS+CIS 혼합 SLAM.
- 남은 과제(27쪽): 높은 이벤트율/해상도를 위한 **대역폭 최소화**, 어두운 조도에서 응답 개선, **SLAM 정보와 결합한 고수준 정보 처리**.
- 한계: 2019년 R&D 시점 자료. 납품처/판매량은 이 자료에 없음.

## 2. Reinbacher, Munda, Pock, "Real-Time Panoramic Tracking for Event Cameras" (ICCP 2017) [본문]
URL: https://arxiv.org/abs/1703.05161
- 문제: 3자유도 회전만 있는 이벤트 카메라의 파노라마 추적. 우리 과제와 가장 가까움.
- 방법: 이벤트를 원통 파노라마 맵에 투영(phi(x, theta) = [px(1 + atan(Xx/Xz)/pi), py(1 + Xy/sqrt(Xz^2 + Xx^2))]), 맵 M = O/N(발생 횟수 / 카메라 경로 길이로 정규화), 비용 = 1 - M(phi) 제곱합 + 시간 정칙화 alpha/2 ||theta - theta_prev||^2, Gauss-Newton + Nesterov 가속. **이벤트 위치만 사용, 극성 폐기**, 타임스탬프는 패킷 분할에만 사용.
- 가정: 순수 회전, 깊이 불필요, 정적 장면, 내부 보정 필요. 속도: GTX 780 Ti에서 패킷당 추적 0.38~1.05 ms, 약 170 pose/s(1500 이벤트/패킷, 10회 반복).
- 데이터/결과: DAVIS240, UZH 데이터셋 중 poster/boxes/shapes/dynamic(우리가 쓴 shapes_rotation과 같은 계열), 정답 200 Hz, 평균 각도 오차 5도 미만(직접 비교 대상 없음). 동적 장면에서 추적 품질이 떨어졌다가 회복. **매우 빠른 움직임에서 움직임을 과소추정**.
- 우리와의 연결: (1) 같은 데이터에서 5도 미만 vs 우리 ECC 1초 구간 오차 약 4도(정의가 달라 직접 비교 불가). (2) 극성 폐기는 우리 극성 실험(진행 중)의 기준점. (3) 과소추정은 우리 합성에서 시차가 있을 때 ECC/CMax가 과소추정한 것과 같은 방향. (4) 이들은 순수 회전이라 시차(깊이)를 다루지 않음 -> 우리 깊이 층 처리가 차별점.

## 3. "Real-Time Grasping Strategies Using Event Camera" (arXiv 2107.07200) [본문]
URL: https://arxiv.org/abs/2107.07200
- 설정: UR10 6-DoF 팔 + Barrett 손, **DAVIS346(346x260, 140 dB, 10 mW)을 손목(eye-in-hand)에 장착**.
- 역할: 다중 객체 이벤트 mean-shift 분할(MEMS, 12.9 ms vs 프레임 기반 755 ms, 약 58배), EMVS 3D 복원, 이벤트 기반 시각 서보잉(EVS). 이벤트당 처리 시간 약 1 us(다운샘플 시).
- 결과: 모델 없는 파지 15회 위치 오차 1.479 cm, 방향 오차 2.41도, 성공률 93.3%; 모델 기반 15회 위치 0.705 cm, 방향 4.16도, 성공률 100%. 저조도에서도 유사(분산 증가).
- 한계/가정: 낮은 해상도, 단순 다중 객체 장면, 가려짐 미해결, 모델 기반은 알려진 물체만. **로봇-카메라 시간 동기화 프로토콜은 명시되지 않음**, EMVS는 알려진 카메라 궤적이 필요(로봇 자세 활용).
- 우리와의 연결: 손목 카메라 + 로봇 자세 활용 시나리오가 우리 타겟(로봇팔)과 같음. 자세를 로봇에서 얻는다는 가정이 실제로 쓰이는 사례. 시간 동기화는 우리가 합성으로 허용 오차를 재 볼 항목.

## 4. 미정독 후보 [목록]
- (이미 정독됨: `D2_01_Kim2014_BMVC_SimultaneousMosaicingTracking.md`, `D2_02_Guo2024_CMaxSLAM.md`) Kim et al. 2014 모자이크+추적, CMax-SLAM은 앞선 노트를 참조. 이 문서의 목록에서는 중복이라 제외.
- "Event-Based Mosaicing Bundle Adjustment" (ECCV 2024): 모자이크 번들 조정 -> 우리 θ 정밀화(합성에서만 개선)와 직접 비교할 대상. https://link.springer.com/chapter/10.1007/978-3-031-72624-8_27
- Gallego et al., "A Unifying Contrast Maximization Framework" (CVPR 2018) https://arxiv.org/pdf/1804.01306 / Gallego-Scaramuzza "Accurate Angular Velocity Estimation With an Event Camera" (RA-L 2017)
- Eventor: FPGA 이벤트 단안 다중시점 스테레오 가속기 https://arxiv.org/pdf/2203.15439
- Event Vision Sensor: A Review https://arxiv.org/pdf/2502.06116 / Event-based SLAM: A Comprehensive Survey https://arxiv.org/pdf/2304.09793
- 4.1 "A 640x480 DVS with a 9um pixel and 300Meps AER" (ISSCC 2017, Samsung) -> 1차 AER 설계의 직접 참고, 유료 접근일 수 있음.
- 자동차 안전/인증: ISO 26262, SOTIF 관련 https://arxiv.org/pdf/2605.21500
