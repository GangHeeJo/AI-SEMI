# 뉴로모픽 방식 차용을 위한 문헌/오픈소스 조사 (2026-10-05)

읽은 정도: **[본문]** = 본문 전체를 읽고 정리, **[본문-요약]** = 본문을 가져와 정리된 요약으로 읽음(원문 전체 확인은 아님), **[목록]** = 제목/검색 요약만 확인(미정독).

## 1. Gehrig, Shrestha, Mouritzen, Scaramuzza, "Event-Based Angular Velocity Regression with Spiking Networks" (ICRA 2020) [본문]
PDF: https://rpg.ifi.uzh.ch/docs/ICRA20_Gehrig.pdf, 코드: https://github.com/uzh-rpg/snn_angular_velocity (GPL-3.0, 학습은 SLAYER PyTorch 필요)
- 문제: 회전하는 이벤트 카메라의 3축 각속도(tilt/pan/roll)를 SNN으로 **연속 시간**에 회귀. 입력은 이벤트를 전처리 없이 스파이크로 직접 입력, **극성은 픽셀당 2채널**.
- 뉴런: Spike Response Model(SRM). 입력 스파이크가 커널 eps(t) = (t/tau_s) e^(1 - t/tau_s)로 시간에 걸쳐 퍼지며 막전위에 누적, 임계 도달 시 발화 후 불응 커널 nu(t) = -2 theta e^(-t/tau_r). 이 시간 퍼짐이 **단기 기억**이라 두 스파이크가 시간상 가까울 때 상호작용 -> 움직임 추정이 가능.
- 구조: conv 5층(커널 3x3, 채널 16/32/64/128/256, 앞 4층 stride 2) + Global Average Spike Pooling(GASP) + 완전연결 3개 비스파이킹 출력 뉴런. 시정수는 깊을수록 증가(tau_s,tau_r = 2,1 / 2,1 / 4,4 / 4,4 / 4,4 / 8 ms).
- 학습: SLAYER(대리 기울기), 손실 = 예측-정답 각속도의 유클리드 거리 시간 적분(처음 50 ms 정착 시간 제외), ESIM 합성 데이터(Sun360 파노라마 1만 장, 500 ms 시퀀스 9000/500/500, 240x180, 순수 회전, 정답 각속도), Adam 1e-4, 24만 반복, 배치 16.
- 결과(합성 시험 세트): 상대 오차 중앙값 SNN-6 0.26, ANN-6 0.22, ResNet-50(누적 영상) 0.22, ResNet-50(복셀) 0.15; RMSE 66.3 / 59.0 / 66.8 / 36.8 deg/s(평균 예측 기준선 226.9). **roll이 tilt/pan보다 어려움**(이벤트가 주변부에서 생겨 시공간 패턴이 화면 전체에 퍼짐). 누적 영상은 타이밍을 버려 불리, 복셀 격자(시간 보존)가 유리.
- 한계: **실제 데이터 결과 없음**(합성만), 하드웨어(뉴로모픽 칩) 구현/전력 측정 없음, 정착 시간 약 50 ms, 학습 비용 큼.
- 우리와의 연결: (1) 극성을 별도 채널로 쓰는 것은 우리 극성 증거 결과와 같은 방향. (2) 시간 정보를 보존하는 표현이 중요. (3) 정확도(RMSE 약 66 deg/s)는 우리 UZH CMax 구현(검증 구간 RMS 약 40~60 deg/s)과 같은 자릿수이고 ECC에는 못 미침 -> SNN 회귀 자체가 우리 θ 추정을 개선한다는 근거는 아님.

## 2. Risi, Aimar, Donati, Solinas, Indiveri, "A Spike-Based Neuromorphic Architecture of Stereo Vision" (Frontiers in Neurorobotics 2020) [본문-요약]
URL: https://www.frontiersin.org/articles/10.3389/fnbot.2020.568283/full
- 구조: 망막(2x256 뉴런, 240x180 -> 16x16 다운샘플) -> **일치 검출기(coincidence detector, 16x16x4)**: 좌우 같은 위치의 이벤트가 시간적으로 가깝게 도착할 때만 발화(NMDA 같은 비선형 시냅스; 시간 창은 NMDA 문턱으로 조절) -> **시차 검출기(disparity detector, 16x16x4)**: 일치 검출기들의 응답을 모음. 시차 검출기는 (1) 맞는 시차의 일치 검출기에서 전방 흥분, (2) 같은 cyclopean 위치의 다른 일치 검출기에서 전방 억제, (3) 같은 시선(line of sight)의 다른 시차 검출기에서 **재귀 억제**를 받음 = 한 시선에 하나의 깊이만 남기는 승자독식(WTA)/유일성 제약.
- 하드웨어: DYNAP 칩 3개(0.18 um CMOS), 실리콘 뉴런 3,072개, 시냅스 62,562개, 적응 지수 IF 뉴런, FPGA(Kintex-7)가 센서 인터페이스(핸드셰이크, 메타안정성 동기화, AER 변환).
- 결과: 합성(두 에지가 반대 방향으로 이동, 일부러 모호하게 동기화) 올바른 대응 비율(PCM) 일치 검출기 0.57 -> 시차 검출기 0.88(모호성 해소), 거짓 목표 증폭 0.08/참 목표 증폭 0.45. 실제 DAVIS240C 스테레오 기록에서도 모든 층에서 시차 검출기 PCM > 일치 검출기 PCM.
- 한계: **극성 분리는 이론적 모델에 있으나 구현은 한 극성만 사용**, 평면 위 운동(일정 시차)만 검증(깊이 방향 운동 미검증), 시냅스 가소성 없음 -> 자극 통계에 맞춘 오프라인 보정 필요, 소자 불일치 영향 미평가, 속도가 느리면 억제가 실패, 코드 공개 없음(저자 문의).
- 우리와의 연결: **"일치 검출 + 같은 시선에서 서로 다른 깊이끼리 경쟁(유일성) + 이웃 흥분(연속성)"** 은 협동 알고리즘(Marr-Poggio)의 스파이킹 구현이며, 우리 깊이 층 선택의 모호성 해소 단계와 직접 대응. 단 이 가정(불투명 표면, 한 시선에 한 깊이)은 우리 합성(투명하게 겹친 깊이 평면)에는 맞지 않았음(깊이 평활 제약이 합성에서 악화된 이유와 같음).

## 3. 그 밖의 후보 [목록]
- Kreiser et al. 2018, "A Neuromorphic Approach to Path Integration: A Head-Direction SNN with Vision-driven Reset" (링 어트랙터가 각속도를 적분하고 이벤트 카메라 시각 입력으로 오차를 재설정): https://www.researchgate.net/publication/324958575
- Osswald et al. 2017, "A spiking neural network model of 3D perception for event-based neuromorphic stereo vision systems" (Sci Rep): https://www.nature.com/articles/srep40703 (접근 제한으로 본문 미확인)
- Paredes-Valles, Hagenaars, de Croon, "Self-Supervised Learning of Event-Based Optical Flow with Spiking Neural Networks" (NeurIPS 2021): https://arxiv.org/pdf/2106.01862, 코드 https://github.com/tudelft/event_flow (MIT)
- "Fully neuromorphic vision and control for autonomous drone flight" (Loihi, 2023): https://arxiv.org/pdf/2303.08778
- "Fully Asynchronous Neuromorphic Perception for Mobile Robot Dodging with Loihi Chips": https://arxiv.org/pdf/2410.10601
- "Neuromorphic Spiking Ring Attractor for Proprioceptive Joint-State Estimation": https://arxiv.org/pdf/2604.14021 (로봇 관절 상태, 엔코더와 연결 가능)
- "Estimating orientation in natural scenes: A spiking neural network model of the insect central complex" (PLOS Comput Biol 2024): https://journals.plos.org/ploscompbiol/article?id=10.1371%2Fjournal.pcbi.1011913

## 4. 오픈소스 (GitHub API로 확인한 라이선스/갱신일)
| 저장소 | 라이선스 | 별 | 최근 갱신 | 용도 |
|---|---|---:|---|---|
| uzh-rpg/snn_angular_velocity | GPL-3.0 | 116 | 2022-04 | 각속도 SNN(위 논문), SLAYER 필요 |
| tudelft/event_flow | MIT | 104 | 2023-10 | SNN 자기지도 광류 |
| lava-nc/lava, lava-dl | NOASSERTION / BSD-3-Clause | 741 / 183 | 2026-05 | Intel Loihi 소프트웨어 프레임워크 |
| synsense/sinabs | Apache-2.0 | 127 | 2026-02 | SNN 라이브러리(SynSense 칩용) |
| synsense/rockpool | AGPL-3.0 | 92 | 2026-07 | SNN 라이브러리 |
| jeshraghian/snntorch | MIT | 2063 | 2026-10 | PyTorch 기반 SNN 학습 |
| fangwei123456/spikingjelly | Apache-2.0 | 2151 | 2026-10 | SNN 프레임워크 |
| BindsNET/bindsnet | AGPL-3.0 | 1703 | 2026-10 | SNN 시뮬레이션 |
| nengo/nengo | NOASSERTION | 950 | 2026-08 | 대규모 뇌 모델/뉴로모픽 매핑 |
| neuromorphs/tonic | GPL-3.0 | 297 | 2026-10 | 이벤트 데이터셋/변환 |
재사용 가능성: MIT/Apache/BSD(snnTorch, SpikingJelly, Sinabs, lava-dl, event_flow)는 코드 활용 가능, GPL/AGPL(snn_angular_velocity, rockpool, bindsnet, tonic)은 전염성 라이선스라 제출물에 코드를 섞지 말고 참고만.
스테레오 SNN(Osswald/Risi)의 코드는 공개돼 있지 않음.
