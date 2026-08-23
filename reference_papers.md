# 참고논문 리스트 — 전국 AI 반도체 회로 설계 경진대회

> 지도교수: 류현석(Hyunsurk Ryu, SNU), eric.ryu@snu.ac.kr
> Digital 트랙(AER 통신 + 좌표 변환) / Analog 트랙(DVS 픽셀 + 어레이) 각 1차·2차 과제 대비 문헌조사.
> 모든 항목은 WebSearch로 제목·저자·연도를 교차 확인했으며, 확정하지 못한 항목은 "미검증"으로 표시함.

---

## 📖 번호 체계 안내 (읽기 전에 먼저 볼 것)

이 문서의 논문 번호는 **"섹션 번호-그 섹션 안에서의 순번"** 형식이다. 예를 들어 **3-4**는 "3번 섹션(Analog 1차)의 4번째 논문"을 뜻한다. 섹션마다 번호가 1부터 다시 시작하므로, 문서 안에서 다른 논문을 가리킬 때도 항상 이 "섹션-순번" 형식을 그대로 쓴다 (예: "→ 4-3 참조"). 같은 논문이 여러 과제에 관련되는 경우, 그 논문이 **처음 등장하는 섹션**을 "원 소속"으로 보고 다른 섹션에서는 참조만 남긴다 (전문 반복 없음).

**섹션 목록**
| 섹션 | 이름 | 내용 |
|---|---|---|
| **0** | 공통 기초 문헌 | 신경형태공학/AER의 기원 (Mead, Mahowald, Sivilotti, Lazzaro) — 두 트랙 모두의 뿌리 |
| **0-A** | Carver Mead 논문 심층분석 | 0-1(Mead 1988)과 0-2(Mead 1990) 두 편을 원문 전체 정독해 섹션별로 분석한 부분. (A)=0-1 분석, (B)=0-2 분석 |
| **1** | Digital 1차 | 전통적 AER 통신 분석 + 개선 방향 |
| **2** | Digital 2차 | 좌표 변환 / 월드 메모리 매핑 |
| **3** | Analog 1차 | DVS 픽셀 설계 (저노이즈·전류모드·in-pixel memory) |
| **4** | Analog 2차 | 256×256 어레이 + AER 리드아웃 |
| **5** | 류현석 교수 관련 | 지도교수 공저 논문·특허, Neuroreality Vision 조사 |

### 전체 논문 한눈에 보기

| ID | 저자 (연도) | 제목(축약) | 한줄 요약 |
|---|---|---|---|
| 0-1 | Mead 1988 | A Silicon Model of Early Visual Processing | 최초의 아날로그 실리콘 망막 (AER 없음) |
| 0-2 | Mead 1990 | Neuromorphic Electronic Systems | "신경형태" 용어 정립 + 배선 스케일링 법칙 |
| 0-3 | Mahowald & Mead 1991 | The Silicon Retina | 0-1의 대중과학 버전 (Sci Am) |
| 0-4 | Mahowald 1992 (박사논문) | VLSI Analogs of Neuronal Visual Processing | **AER 개념 최초 정식화** |
| 0-5 | Sivilotti 1991 (박사논문) | Wiring Considerations in Analog VLSI | 배선 복잡도 이론 — "왜 전용배선이 불가능한가" |
| 0-6 | Lazzaro et al. 1993 | Silicon Auditory Processors as Computer Peripherals | 최초의 실용적 AER 프로토콜 |
| 1-1 | Boahen 2000 | Point-to-Point Connectivity Using Address-Events | AER 채널 설계 이론 정립 (대역폭/중재/큐잉) |
| 1-2 | Boahen 2004 | A Burst-Mode Word-Serial Address-Event Link | 행/열 순차 버스트 전송으로 패드 수 절반화 |
| 1-3 | Culurciello et al. 2003 | A Biomorphic Digital Image Sensor | self-timed 픽셀 판독으로 중재 병목 완화 |
| 1-4 | Park et al. 2017 | Hierarchical Address Event Routing (HiAER) | 계층적 라우팅으로 대규모 멀티코어 확장 |
| 1-5 | Qiao & Indiveri 2019 | A Bi-Directional Address-Event Transceiver | 저지연·고처리량 양방향 AER 트랜시버 |
| 1-6 | Wei et al. 2019 | Rotation Priority Tree Arbiter | 회전 우선순위 중재로 공정성 문제 해결 |
| 1-7 | Purohit & Manohar 2022 | Field-Programmable Encoding for AER | 워크로드별 유연한 주소 인코딩 |
| 1-8 | (미검증) 2024 | Scalable Area-Efficient Low-Delay AER | 듀얼레벨 마스크 AER, 원문 확인 필요 |
| 2-1 | Gallego et al. 2022 | Event-Based Vision: A Survey | 이벤트카메라 전반 서베이 (필수 배경) |
| 2-2 | Kim et al. 2014 | Simultaneous Mosaicing and Tracking | 회전 전용 카메라 파노라마 매핑 — **과제와 구조 동일** |
| 2-3 | Guo & Gallego 2024 | CMax-SLAM | 순수 회전 운동 전용 이벤트 SLAM |
| 2-4 | Xing et al. 2024 | EROAM | 구면 투영 기반 회전 전용 실시간 매핑 |
| 2-5 | Kim et al. 2016 | Real-Time 3D Reconstruction and 6-DoF Tracking | 일반 6자유도 사례 (참고용) |
| 2-6 | Rebecq et al. 2017 | EVO | 이벤트 기반 병렬 트래킹·매핑 |
| 2-7 | US Patent 9,934,557 | Image Representation for DVS | 변환행렬 기반 좌표 매핑 (류현석 공동발명) |
| 3-1 | Lichtsteiner et al. 2008 | 128×128 120dB DVS | 현대 DVS의 시초 회로 |
| 3-2 | Delbruck & Mead 1994 | Adaptive Logarithmic Photoreceptor | 모든 DVS 광수용체의 원형 |
| 3-3 | Posch et al. 2011 | QVGA 143dB PWM Sensor (ATIS) | 이벤트+절대밝기 동시 인코딩 |
| 3-4 | Yang et al. 2015 | 1% Temporal Contrast, In-Pixel Delta Modulator | threshold·in-pixel memory 요구사항에 가장 근접 |
| 3-5 | Graca & Delbruck 2021 | Intensity-Dependent DVS Pixel Noise | 노이즈-조도 역설 규명 |
| 3-6 | Graca et al. 2023 | Optimal Biasing and Physical Limits of DVS Noise | 바이어스 최적화 이론 |
| 3-7 | Graca et al. 2024 | SciDVS | 저조도 1.7% 민감도 달성 |
| 3-8 | Linares-Barranco & Serrano-Gotarredona 2003 | Femtoampere Current-Mode Circuits | 펨토암페어 전류모드 회로 설계 근거 |
| 3-9 | Brandli et al. 2014 | DAVIS Sensor | DVS+APS 픽셀 공유 구조 |
| 4-1 | Boahen 2000 | (=1-1) | 대규모 어레이 AER 통신의 이론적 기반 |
| 4-2 | Boahen 2004 | (=1-2) | 패드 수 절반화 — 256×256급 실질 참고 |
| 4-3 | Son et al. 2017 (Ryu 공저) | 640×480 9μm 300Meps DVS | 삼성 VGA급 DVS, 대규모 AER 판독 핵심 |
| 4-4 | Suh et al. 2020 (Ryu 공저) | 1280×960 4.95μm DVS | 삼성 1.3MP급 후속 DVS — **원문(12쪽 발표슬라이드) 확보·정독 완료(2026-08-19), paper_notes/P5 참고** |
| 4-5 | Finateu et al. 2020 | Sony/Prophesee IMX636 | 산업계 SOTA 스택형 이벤트 센서 |
| 4-6 | Aung et al. 2011 | Adaptive Priority Toggle Arbiter | 공정한 트리 중재기 설계 |
| 4-7 | Richter et al. 2023 | Speck (SynSense) | 2차원 비동기 판독 + 온칩 SNN |
| 4-8 | Culurciello et al. 2003 | (=1-3) | 초기 AER 판독 아키텍처 사례 |
| 5-1 | Lee et al. 2014 (Ryu 공저) | Real-Time Gesture Interface | 스테레오 DVS 실시간 제스처 인식 |
| 5-2 | Son et al. 2017 | (=4-3) | — |
| 5-3 | Suh et al. 2020 | (=4-4) | — |
| 5-4 | US Patent 9,934,557 | (=2-7) | — |
| 5-5 | US Patent App. 20180137647 | Object Detection Based on DVS | 재귀적 코히어런트 네트워크 객체 검출 |
| 5-6 | (미검증) Kim, Ryu et al. | HDR CMOS Image Sensor | venue/연도 미확정 |
| 5-7 | Ryu 2019 (발표자료) | Industrial DVS Design | CVPR 워크숍 슬라이드 (정식 논문 아님) |

---

## 0. 공통 기초 문헌 (신경형태공학 / AER의 기원)

두 트랙 모두의 이론적 뿌리. Mead·Mahowald 사제가 "픽셀=뉴런"과 "AER 통신"을 동시에 정립했다.

0-1. **Mead, C. — "A Silicon Model of Early Visual Processing."** *Neural Networks*, 1(1), 91–97, 1988.
   Mead와 Mahowald가 처음 발표한 아날로그 실리콘 망막 회로. 빛의 공간/시간적 변화에 반응하는 적응형 광수용체를 온칩 UV 플로팅게이트로 구현. **Analog 1차**의 이론적 뿌리이자 픽셀=뉴런 개념의 출발점.

0-2. **Mead, C. — "Neuromorphic Electronic Systems."** *Proceedings of the IEEE*, 78(10), 1629–1636, 1990.
   "신경형태(neuromorphic)"라는 용어를 처음 정식 제안하고, 생물학적 신경계의 아날로그·병렬·저전력 연산을 실리콘으로 구현하는 설계 철학을 제시. 대회 전체 설계 사상의 근거 문헌.

0-3. **Mahowald, M., Mead, C. — "The Silicon Retina."** *Scientific American*, 264(5), 76–82, 1991.
   망막의 광수용체·수평세포·양극세포 회로를 아날로그 VLSI로 구현한 대중 과학 논문. 신경형태 접근을 대중에 알린 논문.

0-4. **Mahowald, M. — PhD Thesis, "VLSI Analogs of Neuronal Visual Processing: A Synthesis of Form and Function."** Caltech, 1992 (CaltechTHESIS:09122011-094355148).
   실리콘 망막, 스테레오 대응 칩, 그리고 **최초의 AER(Address-Event Representation) 인터페이스**를 통합 구현. AER 개념 자체가 여기서 처음 정식화됨 — **Digital 1차와 Analog 1차 모두의 공동 원전.**

0-5. **Sivilotti, M. A. — PhD Thesis, "Wiring Considerations in Analog VLSI Systems, with Application to Field-Programmable Networks."** Caltech, 1991.
   회로의 연결 복잡도와 배선(interconnect) 차원성의 관계를 이론적으로 모델링. "왜 뉴런마다 전용 배선을 놓을 수 없는가"에 대한 배선 복잡도 이론 근거 — **Digital 1차** 문제의식의 이론적 배경.

0-6. **Lazzaro, J., Wawrzynek, J., Mahowald, M., Sivilotti, M., Gillespie, D. — "Silicon Auditory Processors as Computer Peripherals."** *IEEE Transactions on Neural Networks*, 4(3), 523–528, 1993.
   실리콘 청각모델 칩 출력을 디지털 컴퓨터에 연결하기 위한 최초의 실용적 AER 프로토콜(주소-이벤트 버스 + 중재기) 제시. **Digital 1차**의 대표 원전.

---

## 0-A. 칼텍 교수(Carver Mead) 논문 심층분석

> 두 논문의 원문 PDF를 직접 확보하여(Neural Networks 1988: lab.semi.ac.cn 미러 / Proceedings of the IEEE 1990: Caltech Authors 저장소 authors.library.caltech.edu/records/j6gtc-ptx47) 전문을 정독하고 분석함. "The Silicon Retina" (Mahowald & Mead, *Scientific American*, 1991)는 Caltech 저장소에 저작권 embargo가 걸려 있어 원문 확보 실패 — 다만 내용상 아래 1988년 논문을 일반 대중 대상으로 재서술한 것이므로 핵심 내용은 중복.

### (A) Mead, C. A., Mahowald, M. A. — "A Silicon Model of Early Visual Processing." *Neural Networks*, 1(1), 91–97, 1988.

**1. 생물학적 배경 (RETINAL STRUCTURE)**
망막의 신호 경로: 광수용체(photoreceptor) → **triad synapse**(수평세포 H + 양극세포 IB/FB와 만나는 지점) → 양극세포 → 신경절세포(ganglion cell, 축삭이 시신경을 구성). Outer plexiform layer(광수용체 바로 아래)까지는 정보가 "부드럽게 변화하는 아날로그 신호"로 표현되고, 신경절세포 축삭에 이르러서야 비로소 **quasi-digital 펄스(진폭은 디지털, 시간은 아날로그)**로 인코딩된다는 점을 명시. 이 논문의 모델은 딱 광수용체~outer plexiform layer 구간, 즉 **아직 스파이크로 변환되기 이전의 아날로그 처리 단계**만을 다룸 — 다시 말해 이 1988년 칩 자체는 AER이 전혀 없는, 순수 아날로그 병렬 출력 어레이임 (AER은 이후 Mahowald 1992년 박사논문에서 별도로 정식화됨).

계산 원리를 3줄로 요약: ① 광수용체는 밝기의 로그를 취한다 ② 수평세포는 그 출력을 공간·시간적으로 평균낸다 ③ 양극세포는 광수용체 신호와 수평세포 신호의 **차이**에 비례하는 출력을 낸다.

**2. 광수용체 회로 (PHOTORECEPTOR)**
- 소자: CMOS 공정에서 자연 발생하는 vertical bipolar transistor를 포토디텍터로 사용 (광자 1개당 전자 약 100개 생성).
- 포토트랜지스터의 전류를 **직렬 연결된 diode-connected MOS 트랜지스터 2개**(subthreshold 영역에서 지수적 I-V 특성)에 흘려 전류→전압 로그 변환.
- **측정 결과 (Fig. 2)**: 광전류 약 10⁻¹⁴A(대략 달빛 수준, 초당 광자 10⁵개)부터 4~5 자릿수(order of magnitude)에 걸쳐 로그 응답이 선형적으로 유지됨을 실측으로 확인.
- 로그 응답의 시스템 차원 의의 두 가지: (1) 여러 자릿수의 밝기 범위를 다루기 쉬운 신호 레벨로 압축 (2) 두 지점 사이의 전압 차이가 절대 밝기와 무관하게 **명암비(contrast ratio)**에 비례하게 됨 — 이는 오늘날 모든 DVS 광수용체(Delbruck & Mead 1994 포함)가 그대로 계승한 핵심 원리.

**3. 수평 저항망 (HORIZONTAL RESISTIVE LAYER)**
- 생물학적 수평세포는 gap junction으로 서로 연결되어 전기적으로 연속인 네트워크를 이루며, 이는 전기긴장성 확산(electrotonic spread)으로 신호가 퍼지는 passive cable로 모델링됨(거리에 따라 지수적으로 감소하는 가중치).
- 실리콘 구현: 각 광수용체를 이웃 6개와 저항 소자로 연결한 **육각형(hexagonal) 저항망**(Fig. 3). CMOS 공정엔 고저항 소자가 없으므로 모든 R·C는 트랜지스터로 구현(Sivilotti 1987 인용).
- 이 저항 회로의 두 가지 장점을 논문이 명시: (1) 외부 입력으로 유효 저항을 조절 가능(생물에서 도파민이 수평세포의 전기긴장성 확산 범위를 조절하는 것과 유사) (2) 전압차가 작을 땐 선형이지만 ~100mV 이상에서는 **포화(saturate)**하는 비선형 특성 — 이는 회로의 견고성(robustness)을 높임: 한 픽셀이 고장나 out-of-range 출력을 내도 네트워크 전체 계산에 미치는 손상이 제한됨.
- 저항망의 기생 커패시턴스(각 노드의 실리콘 기판 커패시턴스)가 생물학적 수평세포 막 커패시턴스와 마찬가지로 **공간뿐 아니라 시간 평균(time-integration)**까지 자연스럽게 수행 — 즉 이 회로는 spatial-temporal low-pass filter 역할을 겸함.

**4. Outer Plexiform 연산 (핵심 수식)**
- Triad synapse의 실리콘 모델 = ① 광수용체가 저항망을 구동하는 컨덕턴스 G + ② 광수용체 전압과 저항망 전압의 차이를 취하는 증폭기.
- 최대 응답은 "광수용체 전위가 국소 이웃의 시공간 평균과 다를 때" 발생 — 즉 이미지가 공간 또는 시간적으로 **급격히 변화하는 지점**에서 신호가 커짐. 이것이 바로 오늘날 DVS의 "temporal contrast(밝기 변화량)" 검출 원리의 아날로그-공간(spatial) 버전.
- 출력은 이미지의 **2차 공간미분(Laplacian, difference-of-Gaussians로 근사 가능)**에 해당 — Marr(1982)의 컴퓨터비전 엣지 검출 필터와 수학적으로 동일한 형태가 "효율적인 물리적 구현의 자연스러운 부산물"로 등장한다는 점을 강조.

**5. 실험 검증 (EXPERIMENTAL RESULTS)**
- 48×48 픽셀 어레이 실측 데이터를 생물학적 데이터와 정량 비교:
  - Fig. 4: 서로 다른 크기의 test flash에 대한 시간 응답을 mudpuppy(Necturus maculosus) 양극세포 실측(Werblin 1974)과 비교 — 파형의 정성적 형태(초기 피크 후 지수적 감쇠, surround 크기에 따른 지연된 감소)가 일치.
  - Fig. 5: "curve shifting" — 배경 조도가 높아질수록 강도-응답 곡선이 우측(고강도 쪽)으로 이동하는 광순응(light adaptation) 현상을 실리콘 픽셀과 생물 양극세포 양쪽에서 재현.
  - Fig. 6, 7: 공간 edge에 대한 반응이 cat 신경절세포(Enroth-Cugell 1966)의 스파이크 발화율 패턴과 유사한 모양(edge 위치에서 peak/dip)을 보임 — Fig. 7은 그 발생 메커니즘을 도식으로 설명(edge 양쪽 광수용체가 반대편 저항망을 서로 끌어당겨 평균 강도가 실제 edge 위치에서 실제값과 어긋나며 그 차이가 픽셀 출력이 됨).

**6. DISCUSSION — 설계 철학**
- "망막의 기능은 그 구조와 분리해서 설명할 수 없다"는 전제 하에, 특정 목적(주파수 필터링/이득 제어/edge 강조/통계적 최적화 등) 논쟁보다 **진화된 단일 구조가 여러 목적을 동시에 수행한다**는 관점 제시.
- 48×48 어레이가 0.25cm²에 들어가고 100마이크로와트로 동작 — "실리콘의 배선 길이가 밀도를 제한한다"는 점이 생물학적 망막과 동일하다고 지적(이 대목이 1990년 논문의 SCALING LAWS 섹션으로 이어지는 복선).
- 마지막 문단: "우리는 신경계가 하는 계산의 시뮬레이션에서 첫걸음을 뗐을 뿐" — 실리콘 매체는 (1) 계산신경과학에 가설 검증 수단을 제공하고 (2) 특정 계산을 위한 실시간 집단 시스템을 설계하는 공학 분야를 개척하는 두 역할을 겸한다고 결론.

**→ 우리 대회와의 연결**: 이 논문 자체는 **AER이 없는 순수 아날로그 병렬 픽셀 어레이**다. 하지만 로그 광수용체 + 국소 평균 대비 차이 검출이라는 원리는 Analog 1차(DVS 픽셀)의 시조 회로이며, "빛의 변화에 반응"이라는 과제 요구사항의 물리적 원형이다. 다만 이 논문의 "변화"는 공간적 대비(spatial contrast)이고, 현대 DVS(Lichtsteiner 2008 등)의 "변화"는 시간적 대비(temporal contrast, 같은 픽셀의 과거 대비 현재 밝기 변화)라는 차이가 있음에 유의 — 두 원리 모두 "국소 기준값과의 차이만 증폭해서 내보낸다"는 동일한 철학을 공유.

---

### (B) Mead, C. A. — "Neuromorphic Electronic Systems." *Proceedings of the IEEE*, 78(10), 1629–1636, 1990.

**1. TWO TECHNOLOGIES — 에너지 효율 비교**
- 오늘날(1990년 기준) 마이크로프로세서: 초당 1000만 연산, 1W 소비 → 칩 레벨 약 10⁻⁷ J/연산. 보드 레벨까지 포함하면 10⁻⁵ J/연산(칩 자체보다 두 자릿수 더 비효율).
- 뇌: 시냅스 약 10¹⁶개, 평균 초당 10회 발화 → 약 10¹⁶ 복합연산/초, 소비전력 수 와트 → **연산당 약 10⁻¹⁶ J**. 뇌는 현재 디지털 기술보다 **10억 배**, 상상 가능한 최선의 디지털 기술과 비교해도 **1000만 배** 더 효율적.
- 트랜지스터 게이트를 0→1로 충전하는 데 드는 에너지(1990년 기준 약 10⁻¹³J, 10년 후 예측 약 10⁻¹⁵J)는 뇌의 시냅스 동작 효율에 근접 — 즉 **격차의 원인은 개별 소자 자체가 아니라 소자를 시스템에서 사용하는 방식**이라는 것이 핵심 논지.

**2. WHERE DID THE ENERGY GO — 디지털 낭비의 두 원인**
1. 게이트 커패시턴스가 노드 전체 커패시턴스 중 극히 일부에 불과 — 노드의 대부분은 배선(wire)이라 에너지 대부분이 배선 충전에 소모됨 (~100배 손실).
2. 디지털 "연산" 하나에 실제로는 약 1만 개의 트랜지스터가 스위칭됨 (~1만배 손실).
→ 총 100만 배의 에너지가 "연산"이라는 추상화 레이어를 만드는 데 낭비됨.

**3. COMPUTATION PRIMITIVES — 뉴로모픽의 대안**
- 생물 이온채널의 Boltzmann 분포 기반 지수적 전류-전압 특성과 서브threshold MOS 트랜지스터의 지수적 I-V 특성이 **놀랍도록 유사**함을 Fig. 1(4가지 곡선: Na/K 채널 컨덕턴스, 시냅스 신경전달물질 방출률, MOS 트랜지스터 포화전류)로 제시 — "정보를 비트가 아닌 아날로그 신호의 상대값으로 표현하고, 소자의 물리 그 자체(지수함수, Kirchhoff 법칙에 의한 무비용 덧셈, 커패시턴스에 의한 시간적분)를 연산 기본 요소로 삼자"는 뉴로모픽의 핵심 제안.
- Floating-gate 부동 게이트(EPROM/EEPROM에 이미 상용화된 기술)를 이용하면 아날로그 값을 반영구적으로 저장 가능 — 디지털 전용이 아닌 **아날로그 장기 기억(long-term analog memory)** 소자로 활용 가능하다는 통찰.

**4. RETINAL COMPUTATION / ADAPTIVE RETINA — (A) 논문의 재구성 + 확장**
- Mach(1868)의 lateral inhibition 방정식을 명시적으로 인용: **v = u − m(∂²u/∂x² + ∂²u/∂y²)** (u=조도, v=밝기 감각, m=상수) — (A) 논문의 회로가 정확히 이 수식을 물리적으로 구현한 것이라고 재확인.
- **Adaptive Retina (Fig. 3)**: Frank Werblin의 제안(저항망→광수용체로의 피드백)을 반영한 개선 회로. **자외선(UV)으로 프로그램 가능한 floating gate**를 저항망과 출력 풀업 트랜지스터 사이에 삽입하여, UV 조사 시 산화막의 누설전도가 생겨 floating gate 전하가 조정됨 → 트랜지스터 오프셋(개체차) 편차를 자동 보정하는 **최초의 실리콘 학습(learning)** 사례로 제시.
- **일반화된 신경 계산 패러다임 (Fig. 4)**: "모델이 입력을 예측 → 실제 입력과 비교 → 예측이 맞으면 상위 레벨로 아무 정보도 안 보냄 → 틀리면 그 차이(오차)만 상위로 전달 & 모델을 보정"하는 **예측-비교-보정 루프**. 이것이 이 논문 전체에서 가장 일반적이고 강력한 통찰: **"예측 가능한 반복 정보는 걸러내고, 예측 불가능한 차이(놀라움/사건)만 다음 단계로 전달한다"**는 원리 — 이는 사실상 오늘날 이벤트 기반(event-driven) 센서와 AER 통신이 작동하는 근본 이유의 이론적 원형이다: **"바뀐 것만 보낸다"**는 설계 철학이 여기서 정식화됨.

**5. NEURAL SILICON**
- 8년간 DARPA MOSIS로 제작한 수백 개 테스트칩·수십 개 시스템급 칩 나열: 제어 시스템, 모터 패턴 생성기, 밝은 점 추적 레티나, 자동 초점 레티나, 이득제어/모션감지/영상강조 레티나, 다중스케일 레티나, 스테레오비전 칩, 영상분할 칩, 청각 처리 칩(cochlea 모델), 양쪽귀 음원 방향 추정 칩, 시각→청각 변환(Seehear) 칩 등.
- (A)논문의 48×48 레티나는 약 10⁵개 소자, 초당 약 10⁸연산, ~10⁻³W 소비 → **연산당 약 10⁻¹¹J** (같은 공정의 디지털 설계 대비 10⁻⁷J보다 4자릿수 우수, 뇌의 10⁻¹⁶J에는 아직 5자릿수 못 미침).

**6. SCALING LAWS — Digital 1차 과제의 핵심 이론적 근거 ★★★**
이 섹션이 우리 대회의 Digital 1차(AER이 왜 필요한가)에 대한 **가장 직접적이고 정량적인 이론적 근거**다. Mead는 다음과 같이 배선(wire) 스케일링을 수식으로 도출한다:

- 2D 평면(전체 한 변 길이 L_max)에 뉴런이 단위 면적당 1개씩 빽빽이 채워져 있다고 가정. 길이 L인 배선의 폭을 W, 길이가 [L, L+dL] 구간에 속할 확률밀도를 p(L)이라 하면, 한 뉴런이 차지하는 배선 면적의 기댓값은:
  **∫₁^Lmax W·L·p(L) dL = A** (A = 뉴런 1개당 할당 면적)
- 질문: L_max가 커져도(=뉴런 수가 늘어나도) A가 폭발적으로 증가하지 않으려면 p(L)의 형태에 어떤 제약이 필요한가?
- **답: p(L) = 1/L² 이면 A는 L_max의 로그(log)에 비례해서만 증가** — 매우 합리적. p(L)이 이보다 느리게 감소하면(즉 긴 배선이 상대적으로 더 많이 존재하면) 배선이 계산 회로 면적을 압도해버림.
- **결론: 신경계는 배선의 개수가 배선 길이의 역제곱(inverse square)보다 느리게 감소하지 않도록 조직되어 있다.** 즉 뉴런 대부분은 아주 짧은 배선(가까운 이웃)만 갖고, 먼 거리 배선은 매우 드물어야 한다 — **"국소(local) 연결이 압도적으로 많고, 원거리 연결은 희소해야 한다"**는 것이 스케일링 법칙에서 유도된 필연적 요구사항.
- 이 논증을 3차원 구조에도 그대로 반복 적용 — **∫₁^Lmax S·L·p(L) dL = V** (부피 버전)로도 동일한 스케일링 법칙이 유도됨. 즉 3차원으로 확장해도(더 많은 뉴런과 접촉은 가능해지지만) 배선 길이별 배선 개수가 줄어드는 근본 법칙 자체는 2D든 3D든 동일하게 적용된다 — **"3차원이 2차원보다 근본적으로 유리하지 않다"**는 결론.
- 실증: 인간 대뇌피질을 펼치면 한 변 약 1m, 두께 1mm — 그 중 절반(백질)이 배선, 절반(회백질)이 연산 회로. 쥐나 박쥐 뇌 대비 배선 자원 사용 효율이 크게 떨어지지 않는 것도 이 국소성 전략 덕분이라고 설명. 대뇌피질이 3차원 대신 (얇지만) 2차원적 구조로 진화한 것은 **진화 가능성(evolvability)** 때문(새로운 피질 영역이 평면에서 쉽게 추가·확장 가능)이라고 해석.

**→ 우리 대회와의 연결 (매우 중요)**: 이 스케일링 법칙은 Sivilotti(1991) 박사논문의 결론("왜 뉴런마다 전용 배선을 놓을 수 없는가")을 뒷받침하는 **정량적·수학적 증명**이다. Digital 1차 과제의 "전통적 AER 방식을 분석하고 문제점 도출" 리포트에서, "왜 AER(공유 통신 매체)이 불가피한가"를 설명할 때 이 스케일링 법칙을 직접 인용하면 논증이 훨씬 탄탄해진다 — 단순히 "핀 개수가 부족해서"가 아니라, **"뉴런 수 N이 커질 때 전용 배선 방식은 배선 개수가 N²(모든 쌍 연결) 스케일로 늘어나는데, 물리적으로 실현 가능한 회로는 배선 개수가 길이의 역제곱 이하로 감소해야 하므로, 필연적으로 시분할·주소지정(AER) 방식의 공유 채널이 요구된다"**는 형태로 문제를 정식화할 수 있다. 또한 "예측-비교-차이전달"(Fig. 4) 패러다임은 Digital 2차(좌표 변환/월드 메모리) 설계에서 "매 프레임 전체를 다시 보내지 않고 변화(이벤트)만 좌표 태깅해서 누적한다"는 아키텍처 철학의 근거로도 활용 가능하다.

**7. CONCLUSION 핵심 수치**
- 적응형 아날로그 시스템은 실리콘 면적 사용에서 디지털 대비 약 **100배** 효율적, 전력 소비는 약 **10,000배** 효율적이라고 결론(1990년 시점 실측 기반 추정치).
- 실리콘 기술의 "2차원 제약"이 뉴로모픽 시스템의 잠재력을 활용하는 데 있어 심각한 제약이 아니라고 주장 — 웨이퍼 스케일 집적(wafer-scale integration)에 대한 낙관적 전망으로 마무리(디지털 웨이퍼스케일은 결함 민감성과 발열 문제로 계속 실패해온 반면, 저전력·오류에 강건한 적응형 아날로그는 웨이퍼 스케일에 적합하다는 논지).

---

## 1. Digital 트랙 — 1차: 전통적 AER 분석 및 개선 방향

**과제**: Bio-mimic Neuron을 위한 AER 통신 방식 분석 → 문제점 도출 → 개선된 AER 설계 방향 제시.

1-1. **Boahen, K. A. — "Point-to-Point Connectivity Between Neuromorphic Chips Using Address Events."** *IEEE TCAS-II*, 47(5), 416–434, 2000.
   log₂N 비트 주소-이벤트를 랜덤 액세스 시분할 채널로 전송하는 구조를 정식화. 대역폭 할당·중재(arbitration)·큐잉 간 트레이드오프를 정량 분석. **전통적 AER의 문제점(대역폭 병목, 중재 지연)을 분석하는 데 가장 핵심적인 논문.**

1-2. **Boahen, K. A. — "A Burst-Mode Word-Serial Address-Event Link" (Part I: Transmitter, Part II: Receiver, Part III: Analysis and Test Results).** *IEEE TCAS-I*, 51(7), 1269–1291, 2004.
   행(row) 주소를 먼저 전송 후 활성 열(column) 주소들을 순차 버스트 전송해 배선(패드) 수를 절반으로 줄이면서 집적도에 비례해 대역폭이 확장되는 개선 AER 링크. **"개선된 AER 설계 방향" 제안의 직접적 근거 — Digital 2차의 좌표 매핑 회로에도 참고 가치.**

1-3. **Culurciello, E., Etienne-Cummings, R., Boahen, K. A. — "A Biomorphic Digital Image Sensor."** *IEEE JSSC*, 38(2), 281–294, 2003.
   80×60 픽셀에서 각 픽셀이 스스로 판독을 요청하는 self-timed 방식으로 밝은 픽셀에 대역폭을 더 배분. 180dB 다이나믹레인지. 중재 병목 완화 방향의 초기 사례.

1-4. **Park, J. H. (Jaewook), Yu, T., Joshi, S., Maier, C., Cauwenberghs, G. — "Hierarchical Address Event Routing for Reconfigurable Large-Scale Neuromorphic Systems."** *IEEE TNNLS*, 28(10), 2408–2422, 2017.
   계층적(HiAER) 주소-이벤트 라우팅으로 대규모 멀티코어 칩 간 스파이크 통신을 확장 가능하게 함. 단일 버스 중재의 병목을 계층/NoC 구조로 완화 — **개선된 AER 아키텍처 제안의 좋은 사례.**

1-5. **Qiao, N., Indiveri, G. — "A Bi-Directional Address-Event Transceiver Block for Low-Latency Inter-Chip Communication in Neuromorphic Systems."** arXiv:1908.07413, 2018/2019.
   28nm FDSOI 공정에서 초당 최대 28.6M 이벤트, 이벤트당 11pJ의 저지연 양방향 AER 트랜시버. 저지연·고처리량 AER 개선의 구체적 회로 사례.

1-6. **Wei, J. 외 — "An Asynchronous AER Circuits with Rotation Priority Tree Arbiter for Neuromorphic Hardware with Analog Neuron."** IEEE ISCAS, 2019.
   고정 우선순위 중재기가 특정 뉴런에 자원을 편중시키는 "고정 잡음" 문제를 회전 우선순위 트리 중재기로 해결. SMIC 180nm, 64채널 143M events/s. **중재 공정성 문제와 개선안의 구체적 사례.**

1-7. **Purohit, P., Manohar, R. — "Field-Programmable Encoding for Address-Event Representation."** *Frontiers in Neuroscience*, 2022 (Yale).
   AER 인코딩 방식을 필드-프로그래머블하게 구성해 워크로드별 주소 인코딩 전략을 유연화. 최신 AER 개선 다양화 사례.

1-8. *(미검증, 참고용)* **"A Scalable Area-Efficient Low-Delay Asynchronous AER Circuits Design for Neuromorphic Chips."** IEEE TBCAS, DOI 10.1109/TBCAS.2024.3384758.
   듀얼레벨 마스크 AER 구조로 면적 48%, 지연 17–39% 절감(제목·초록만 확인, 저자명 미확정 — 인용 시 원문 직접 확인 필요).

---

## 2. Digital 트랙 — 2차: 좌표 변환 / 월드 메모리 매핑

**과제**: n×m 시각 뉴런 정보를 N×M 월드 메모리로 매핑. 센서는 고정 위치에서 **방향(회전)만** 바뀜 — pixel coordinate → world coordinate 변환.

> 문제 설정이 "고정된 위치에서 회전만 하는 카메라가 로컬 픽셀 좌표를 전역 파노라마 좌표에 누적"하는 이벤트카메라 로보틱스 연구와 정확히 일치한다.

2-1. **Gallego, G., Delbruck, T., Orchard, G., Bartolozzi, C., Taba, B., Censi, A., et al. — "Event-Based Vision: A Survey."** *IEEE TPAMI*, 44(1), 154–180, 2022.
   이벤트카메라 원리, 이벤트 표현, 모션보상, SLAM/오도메트리에서의 좌표계 처리 전반을 총망라. **2차 과제 전반의 필수 배경 문헌.**

2-2. **Kim, H., Handa, A., Benosman, R., Ieng, S.-H., Davison, A. J. — "Simultaneous Mosaicing and Tracking with an Event Camera."** BMVC, 2014.
   **고정 위치, 회전만 하는 이벤트카메라**의 스트림에서 카메라 자세(회전)를 실시간 추정하며 동시에 파노라마 그래디언트 맵(모자이크)을 구축. **2차 과제와 문제 구조가 사실상 동일 — 가장 직접적으로 참고할 논문.**

2-3. **Guo, S., Gallego, G. — "CMax-SLAM: Event-Based Rotational-Motion Bundle Adjustment and SLAM System Using Contrast Maximization."** *IEEE T-RO*, 40, 2442–2461, 2024.
   **순수 회전 운동 전용**의 최초 이벤트 기반 번들 조정/SLAM. Contrast Maximization으로 회전 궤적을 최적화해 파노라마 지도 생성. **문제 정의(고정 위치, 회전만)가 2차 과제와 정확히 일치하는 최신 논문.**

2-4. **Xing, W. 외 — "EROAM: Event-Based Camera Rotational Odometry and Mapping in Real-Time."** arXiv:2411.11004, 2024.
   이벤트를 구면(unit sphere)에 투영, Event Spherical ICP로 회전 전용 카메라의 실시간 오도메트리·매핑. k-d tree 맵 관리로 고각속도에서도 강건. **회전 전용 센서의 월드 메모리 누적 문제와 가장 유사한 최신 연구.**

2-5. **Kim, H., Leutenegger, S., Davison, A. J. — "Real-Time 3D Reconstruction and 6-DoF Tracking with an Event Camera."** ECCV, 349–364, 2016.
   6자유도(회전+이동)까지 포함한 일반 사례이지만, 로컬 이벤트 좌표를 전역 참조 프레임으로 정합시키는 필터링 기법이 좌표 변환 로직 설계에 참고 가치.

2-6. **Rebecq, H., Horstschäfer, T., Gallego, G., Scaramuzza, D. — "EVO: A Geometric Approach to Event-Based 6-DOF Parallel Tracking and Mapping in Real-Time."** *IEEE RA-L*, 2(2), 593–600, 2017.
   이벤트 스트림 기반 병렬 트래킹·매핑으로 카메라 자세를 실시간 추정. 로컬→월드 좌표 매핑을 위한 자세 추정 참고 문헌.

2-7. **US Patent 9,934,557 — "Method and Apparatus of Image Representation and Processing for Dynamic Vision Sensor."** Ji, Z., Lee, K., Zhang, Q., Wang, Y. M., **Ryu, H. S.**, Ovsiannikov, I. (Samsung Electronics), 2018.
   DVS 이벤트 스트림을 프레임 형태로 표현/처리하는 방법. 서로 다른 이미지 간 좌표 대응을 위한 **변환행렬(transformation matrix)/신뢰도맵** 개념 포함. **로컬 센서 좌표 → 변환행렬 → 월드 좌표 매핑과 개념적으로 가장 밀접한 특허(지도교수 공동발명).**

---

## 3. Analog 트랙 — 1차: DVS 픽셀 설계 (저노이즈·저임계값·전류모드·in-pixel memory)

**과제**: 빛의 변화에 반응하는 DVS 픽셀, 잡음 최소화, minimum sensitivity threshold 최소화, in-pixel event memory. 커런트 모드, 수 펨토암페어 수준 동작.

3-1. **Lichtsteiner, P., Posch, C., Delbruck, T. — "A 128×128 120 dB 15 μs Latency Asynchronous Temporal Contrast Vision Sensor."** *IEEE JSSC*, 43(2), 566–576, 2008.
   현대 DVS의 시초. 각 픽셀이 독립적으로 연속시간에서 국소 광량 변화(temporal contrast)를 감지해 비동기 이벤트 출력. **1차 설계의 핵심 topology 참고 회로.**

3-2. **Delbruck, T., Mead, C. — "Analog VLSI Adaptive Logarithmic Wide-Dynamic-Range Photoreceptor."** *Proc. IEEE ISCAS*, 339–342, 1994.
   이후 모든 DVS 광수용체 회로의 원형이 되는 연속시간·적응형 로그 광수용체. 서브threshold MOSFET 기반으로 피코~펨토암페어급 광전류에서도 동작 가능한 트랜스임피던스 구조. **펨토암페어급 전류모드 동작의 회로 원형.**

3-3. **Posch, C., Matolin, D., Wohlgenannt, R. — "A QVGA 143 dB Dynamic Range Frame-Free PWM Image Sensor With Lossless Pixel-Level Video Compression and Time-Domain CDS."** *IEEE JSSC*, 46(1), 259–275, 2011. (ATIS 센서)
   변화 검출 회로와 노출 측정 회로를 결합, 이벤트뿐 아니라 절대 밝기까지 픽셀 단위 인코딩. 143dB 초고 다이나믹레인지. 민감도/노이즈 최소화 설계 참고.

3-4. **Yang, M., Liu, S.-C., Delbruck, T. — "A Dynamic Vision Sensor With 1% Temporal Contrast Sensitivity and In-Pixel Asynchronous Delta Modulator for Event Encoding."** *IEEE JSSC*, 50(9), 2149–2160, 2015.
   픽셀 내 비동기 델타 변조기로 최소 감지 가능한 밝기 변화율(temporal contrast threshold)을 1%까지 낮춤. **"Minimum sensitivity threshold 최소화"와 "In-pixel event memory" 요구사항 모두에 가장 직접적으로 대응하는 논문.**

3-5. **Graca, R., Delbruck, T. — "Unraveling the Paradox of Intensity-Dependent DVS Pixel Noise."** IISW 2021 (arXiv:2109.08640).
   DVS 픽셀 노이즈가 조도에 따라 역설적으로 변화하는 현상을 광수용체 대역폭·바이어스 관점에서 규명. **"잡음 최소화" 요구사항에 직접 연관.**

3-6. **Graca, R., McReynolds, B., Delbruck, T. — "Optimal Biasing and Physical Limits of DVS Event Noise."** IISW 2023 (arXiv:2304.04019).
   DVS 광수용체가 이론적으로 광자 샷노이즈의 2배까지 근접 가능함을 보이고, 바이어스 전류 최적화로 노이즈-대역폭 트레이드오프 정량화. 노이즈·민감도 설계 지침.

3-7. **Graca, R., Zhou, S., McReynolds, B., Delbruck, T. — "SciDVS: A Scientific Event Camera with 1.7% Temporal Contrast Sensitivity at 0.7 lux."** IEEE ESSERC 2024 (arXiv:2409.09648).
   180nm CIS 공정, 0.7 lux 저조도에서 1.7% 민감도 달성. 저조도·저전류 조건 민감도 최소화의 최신 참고자료.

3-8. **Linares-Barranco, B., Serrano-Gotarredona, T. — "On the Design and Characterization of Femtoampere Current-Mode Circuits."** *IEEE JSSC*, 38(8), 1353–1363, 2003.
   펨토암페어 수준 전류모드 신호처리를 위한 로그 전류 분배기, 특정전류 추출기, 온칩 톱니파 발진기. **"펨토암페어급 전류 모드 동작" 요구사항에 가장 직접적인 회로 설계 참고자료.**

3-9. **Brandli, C., Berner, R., Yang, M., Liu, S.-C., Delbruck, T. — "A 240×180 130 dB 3 μs Latency Global Shutter Spatiotemporal Vision Sensor."** *IEEE JSSC*, 49(10), 2333–2341, 2014. (DAVIS 센서)
   DVS 회로와 APS 회로가 하나의 포토다이오드를 공유하여 이벤트+프레임 동시 출력. 픽셀 구조 확장 아이디어 참고.

---

## 4. Analog 트랙 — 2차: 256×256 어레이 + AER 리드아웃

**과제**: 256×256 픽셀 어레이 설계, readout 효율 향상을 위한 AER 방식 설계 및 적용.

4-1. **Boahen, K. A. — "Point-to-Point Connectivity Between Neuromorphic Chips Using Address Events."** (1-1 참조) — 대규모 어레이 AER 통신의 이론적 기반.

4-2. **Boahen, K. A. — "A Burst-Mode Word-Serial Address-Event Link" I/II/III.** (1-2 참조) — 행/열 순차 전송으로 패드 수 절반화. 256×256급 어레이에서 패드 제약 해결에 실질적 참고.

4-3. **Son, B., Suh, Y., Kim, S., 외 (**Ryu, H.** 포함) — "A 640×480 Dynamic Vision Sensor with a 9μm Pixel and 300Meps Address-Event Representation."** ISSCC 2017, Session 4.1.
   삼성 Gen2 VGA DVS. 기존 pixel-by-pixel AER의 interface-bandwidth-induced latency를 줄이기 위해 digitally synthesized Group-AER(G-AER)를 적용하여 300 Meps 처리율을 달성. 단순 throughput 개선뿐 아니라 이후 arbitration-induced latency 및 timestamp distortion 문제를 분석하는 출발점이 된 설계. **지도교수 공저 — 대규모 어레이 AER 판독 구조의 핵심 참고 논문.** (5-A 참고)

4-4. **Suh, Y., Choi, S., 외 (**Ryu, H.** 포함) — "A 1280×960 Dynamic Vision Sensor with a 4.95-μm Pixel Pitch and Motion Artifact Minimization."** IEEE ISCAS 2020. **원문(12쪽 발표슬라이드) 확보·정독 완료(2026-08-19) — paper_notes/P5 참고.**
   1.3MP급 후속 DVS. Cu-Cu 픽셀 접합, 순차 컬럼 선택 및 글로벌 이벤트 홀딩으로 모션 아티팩트 최소화. 특히 이전 Gen2의 arbiter 기반 word-serial AER에서 나타난 event generation time–readout time mismatch 문제를 해결하기 위해 arbitrary arbitration 대신 sequential column scan을 채택한 후속 구조라는 점에서 중요. **지도교수 공저 — 대형 어레이 스캔 방식에 직접 참고.** 성능비교표 실측: 이 세대(1.3 Geps)가 arbitration 방식(Gen2, 300Meps)보다 오히려 빠른데, 그 이유는 인코딩 최적화가 아니라 **2.5Gbps 4-lane MIPI라는 압도적 인터페이스 대역폭으로 순차 스캔의 비효율 자체를 무의미하게 만들었기 때문** — 논문 전체에서 주소 오버헤드/비트 효율은 단 한 번도 언급되지 않음. (5-A 참고)

4-5. **Finateu, T., Niwa, A., Matolin, D., 외 — "A 1280×720 Back-Illuminated Stacked Temporal Contrast Event-Based Vision Sensor with 4.86μm Pixels, 1.066GEPS Readout, Programmable Event-Rate Controller and Compressive Data-Formatting Pipeline."** ISSCC 2020, Session 5.10. (Sony/Prophesee, IMX636)
   산업계 최고 성능급 스택형 이벤트 센서. 1.06 Geps 판독 속도, 프로그래머블 이벤트율 제어기. **효율적 AER 판독 아키텍처의 최신 SOTA 참고.**

4-6. **Aung, M. T., Do, A. T., Chen, S. — "Adaptive Priority Toggle Asynchronous Tree Arbiter for AER-based Image Sensor."** IEEE/IFIP VLSI-SoC, 66–71, 2011.
   동시 다발 요청 시 우선순위를 토글링해 타이밍 오류를 줄이고 픽셀 간 공정한 버스 자원 할당을 달성하는 트리 중재기. 공정한 arbitration 스킴 설계에 직접 연관.

4-7. **Richter, O., 외 (SynSense) — "Speck: A Smart Event-based Vision Sensor with a Low Latency 327K Neuron Convolutional Neuronal Network Processing Pipeline."** arXiv:2304.06793, 2023.
   128×128 이벤트 센서에 2차원 비동기 판독(행·열 각 arbiter tree)과 온칩 스파이킹 CNN 결합. 대규모 어레이 AER 판독 + 후단 처리 통합 설계의 최신 SOTA.

4-8. **Culurciello, E., Etienne-Cummings, R., Boahen, K. A. — "A Biomorphic Digital Image Sensor."** (1-3 참조) — 초기 AER 판독 아키텍처 사례.

---

## 5. 류현석(Hyunsurk Ryu) 교수 관련 문헌 · 특허 · Neuroreality Vision 조사

**확인된 사실**: Google Scholar 프로필 확인됨(인용 2,000회 이상), 서울대 전기·정보공학부 Visiting Professor로 등재, IEEE CASS 프로필 존재. 삼성전자 종합기술원/DS부문 재직 시절 다수의 DVS 칩·특허에 공저자로 참여.

5-1. **Lee, J. H., Delbruck, T., Pfeiffer, M., Park, P. K. J., Shin, C.-W., Ryu, H., Kang, B. C. — "Real-Time Gesture Interface Based on Event-Driven Processing from Stereo Silicon Retinas."** *IEEE TNNLS*, 2014.
   스테레오 DVS 쌍 + 신경모방 이벤트-구동 후처리로 실시간 손동작 인식. AER 출력의 실용 사례.

5-2. **Son, B. 외 (Ryu, H. E. 포함) — ISSCC 2017 "9μm Pixel, 300Meps AER"** (위 4-3 참조)

5-3. **Suh, Y. 외 (Ryu, H. 포함) — ISCAS 2020 "4.95μm Pixel Pitch, Motion Artifact Minimization"** (위 4-4 참조)

5-4. **US Patent 9,934,557** (위 2-7 참조) — 좌표 변환행렬 기반 DVS 이미지 표현 방법. 지도교수 공동발명.

5-5. **US Patent Application 20180137647 — "Object Detection Method and Apparatus Based on Dynamic Vision Sensor."** Samsung Electronics, 2017 출원, Ryu, H. E. 포함.
   DVS 프레임에서 재귀적 코히어런트 네트워크로 객체 바운딩박스 검출. 이벤트 데이터의 좌표 기반 객체/영역 처리에 부분 관련.

5-6. *(미검증)* **Kim, J.-S., Ryu, H., Park, P. K. J., Kim, J., Park, Y. — "A High Dynamic Range CMOS Image Sensor Using Programmable Linear-Logarithmic Counter for Low Light Imaging Applications."** venue/연도 미확정(ISCAS 계열로 추정) — 인용 전 원문 확인 필요.

5-7. *(정식 논문 아님, 참고자료)* **Ryu, H. E. — "Industrial DVS Design: Key Features and Applications."** CVPR 2019 Workshop on Event-based Vision 발표자료 (rpg.ifi.uzh.ch 게시). 산업용 DVS 설계 원칙을 실전 관점에서 정리한 슬라이드 — 인용 시 정식 논문이 아님을 명시. **원문 전체 확보·정독 완료, 심층분석은 `paper_notes/P4_Ryu2019_TraditionalAER_ProblemTimeline.md` 참고** — Gen1~Gen3에 걸쳐 "전통적 AER의 문제"가 **throughput bottleneck → bandwidth-induced latency → unfair arbitration → timestamp/motion artifact → deterministic scan readout**으로 재정의되는 시간적 흐름을 원문 인용 기반으로 재구성함.

### 5-A. 류현석 교수의 AER 설계 발전 과정 — Throughput에서 Temporal Fidelity로

류현석의 DVS/AER 연구는 단순히 AER 전송 속도를 높이는 방향으로만 발전한 것이 아니라, 실제 산업용 고해상도 DVS에서 발생하는 대역폭 병목, arbitration 지연, timestamp 오차, motion artifact를 순차적으로 해결하는 방향으로 변화했다. 특히 삼성전자 System LSI 재직 당시 발표한 5-7의 *Industrial DVS Design* 자료는 2014년 Gen1부터 2018년 Gen3, 2020년 Gen4까지의 설계 변화를 직접 설명하고 있어 그의 문제 인식을 추적하기에 가장 좋은 1차 자료다(원문 전체 확보·정독 완료 — 아래 인용은 전부 슬라이드 원문 그대로).

**① Gen1, 2014 — 전통적인 row/column arbitration.** 640×480 VGA 어레이에서 Column Arbiter + Address Decoder / Row Arbiter + Address Decoder를 사용한 전통적인 AER 구조. 최대 이벤트 처리율 6.5 Meps, 20-bit parallel interface. 픽셀 이벤트가 개별적으로 arbitration을 거쳐 주소화되므로, 픽셀 수와 동시 발생 이벤트 수가 늘수록 arbiter와 인터페이스가 병목이 된다 — *High Event Rate → Arbitration/Interface Bottleneck → Long Readout Latency*.

**② Gen2, 2016 / ISSCC 2017 — G-AER로 throughput 문제 해결.** Group Address Event Representation(G-AER) 도입, 300 Meps 달성(Gen1 대비 약 46배). 원문: *"Original AER handles the individual pixel data with address, polarity, and event generation time."* / *"Group addressing reduces the latency by the interface bandwidth limitation."* 즉 문제 정의는 **개별 이벤트 단위 AER → address overhead 증가 → interface bandwidth 제한 → latency 증가**이며, G-AER는 "빠른 AER"라기보다 이벤트마다 주소를 독립 전송하는 전통 AER의 구조적 오버헤드를 줄이기 위한 group-based readout으로 이해하는 것이 정확하다.

**③ G-AER 이후 발견된 문제 — throughput만으로 해결되지 않는 arbitration fairness.** 슬라이드 제목 그대로 *"Artifacts and delay by unfair arbitration"* — column arbiter가 동시 활성 column 중 하나를 고르는 과정에서 특정 column이 항상 먼저 서비스되고 다른 column은 밀리는 편향이 생길 수 있다. 즉 arbitration은 이벤트를 잃지 않아도 이벤트 간 **상대적 시간 정보**를 왜곡할 수 있다 — "처리량이 낮다"보다 "공유 자원을 arbitration으로 배분하기 때문에 event traffic이 높아질수록 queueing delay와 service-order-dependent latency가 발생한다"고 정의하는 것이 정확하다.

**④ 핵심 문제의 재정의 — event generation time과 readout time의 불일치.** 슬라이드 제목 *"AER induced motion artifact"*, 원문: *"Image artifact could be induced by the mismatch between event generation time and readout time under high event rate condition."* 실제 이벤트 발생시각 대비 AER 판독시각의 편차(Δt_AER)가 이벤트율·arbiter 상태·column 위치·트래픽에 따라 일정하지 않다 — 즉 높은 이벤트율에서는 AER가 센서 자체의 시간 해상도보다 더 큰 timing uncertainty를 만들 수 있다. 이 관점에서 전통적 AER의 가장 본질적인 문제는 "속도" 자체보다 **temporal fidelity의 손상**이라고 볼 수 있다.

**⑤ Gen3, 2018 — arbiter를 더 빠르게 만드는 대신 sequential scanning으로 전환.** 핵심 기능은 *"Global hold, Global reset, Column scan readout"*, 원문: *"Timestamp error minimized by applying sequential column scan readout."* 구조가 *event → arbiter → arbitrary column selection*에서 *event → pixel event storage → sequential column selection*으로 이동 — "더 빠른 arbiter"가 아니라 arbiter의 **비결정적 선택 자체를 제거**하는 방향. 슬라이드의 비교 그래프도 "Word-serial AER using Arbiter" vs "Sequential Column Selection"의 timestamp error를 event rate에 따라 직접 비교해 이를 뒷받침한다.

**⑥ 표현상 주의 — "synchronous로 바꿨다"는 부정확.** Gen3의 sequential scan을 "AER를 asynchronous에서 synchronous로 바꿨다"고 쓰면 부정확하다. DVS pixel의 event generation 자체는 여전히 비동기(event-driven) — 빛 변화가 threshold를 넘으면 즉시 event 상태가 된다. 바뀐 건 **event readout scheduling**뿐이다. 정확한 표현: "asynchronous event generation은 유지하면서, arbitration-based asynchronous readout을 event storage + deterministic sequential scan readout으로 변경" — *asynchronous sensing + deterministic scanning readout*의 hybrid 구조.

**⑦ Global Hold — scan만으로는 부족함.** Gen3는 픽셀마다 event storage를 두고 Global Hold를 적용한다. 원문(슬라이드 14): *"Global hold is implemented with an event storage in each pixel and its global control signal."* 이는 "읽는 동안에도 scene이 계속 변해서 column마다 서로 다른 시간 상태를 나타내는 문제"를 줄이기 위한 것으로, 일종의 **event-domain global shutter**에 가까운 역할이다. 즉 Gen3 설계는 *Event detection → Event storage/Global Hold → Sequential Column Read*로 볼 수 있다.

**⑧ Gen4 / ISCAS 2020 — 고해상도에서도 이 철학을 유지, 그러나 "해결"의 정체가 정보이론적 최적화가 아니라 대역폭 하드웨어임이 원문으로 확인됨(2026-08-19).** 4-4/5-3의 Suh et al. 2020(1280×960, 4.95μm pixel pitch) 원문(12쪽)을 확보해 정독한 결과(paper_notes/P5), sequential column selection과 global event holding을 그대로 이용해 motion artifact를 줄인 건 맞지만(Gen2: throughput 개선 → Gen3: temporal consistency 개선 → Gen4: 고해상도로 확장이라는 계보), 두 가지가 새로 확인됨: (a) Global Hold를 실제로 오래(10ms+) 유지하려면 GIDL 누설전류로 인한 "주기적 가짜 이벤트"라는 새 아날로그 회로 문제가 따라오고, 전용 회로(GIDL-suppressed reset switch)가 별도로 필요했다 — Gen3(2019 슬라이드)엔 없던 디테일. (b) 성능비교표(슬라이드 11)에서 **이 세대(1.3 Geps)가 arbitration 방식(Gen2, 300Meps)보다 더 빠른데, 그 이유는 "2.5Gbps 4-lane MIPI"라는 압도적 인터페이스 대역폭으로 순차 스캔의 비효율 자체를 무의미하게 만들었기 때문**이다. 논문 12쪽 전체에서 "주소 오버헤드/비트 효율" 관련 단어는 단 한 번도 등장하지 않는다 — 즉 류 교수의 실제 최종·양산 해법은 **"인코딩을 정보이론적으로 최적화한다"는 축을 아예 택하지 않았고**, 대신 문제를 "주소가 덜 필요하게 만들기(sequential, 요청 자체를 없앰) + 남는 비효율은 하드웨어 대역폭으로 흡수"라는 다른 축으로 우회했다.

### 5-B. 류현석 연구에서 도출할 수 있는 "전통적 AER의 문제점"

Digital 1차 과제와 직접 연결하면 다음 여섯 가지로 정리할 수 있다.

1. **Per-event address overhead** — 이벤트마다 주소를 독립적으로 처리하므로 발생률이 높아질수록 address/polarity/timestamp 전송량이 빠르게 증가한다. G-AER의 group addressing이 이에 대한 해법.
2. **Shared-channel bandwidth bottleneck** — 다수 pixel이 하나의 통신 자원을 공유하므로 해상도·event rate가 증가하면 interface bandwidth가 병목이 된다. Gen2의 300 Meps G-AER가 이를 직접 겨냥.
3. **Arbitration latency** — 동시 발생 이벤트 중 하나를 선택하는 과정에서 대기시간 발생, event traffic이 높아질수록 커진다("AER-induced latency").
4. **Arbitration fairness** — 고정/구조적 arbitration 순서에 따라 pixel/column별 서비스 지연이 달라진다("unfair arbitration").
5. **Timestamp distortion** — 실제 event generation time과 AER readout time이 어긋나 timestamp가 물리적 사건 시각을 정확히 반영하지 못할 수 있다.
6. **Motion artifact** — 비균일 latency가 공간적으로 나타나면 움직이는 edge/물체 형상이 왜곡된다("AER-induced motion artifact").

한 문장으로: **전통적인 AER는 개별 이벤트를 공유 통신 채널에서 arbitration하여 전송하기 때문에, event rate와 array size가 증가할수록 bandwidth와 arbitration이 병목이 되고, 그 결과 발생하는 비균일 readout latency가 event timestamp와 공간적 motion information을 왜곡할 수 있다.** 설계 개선 방향은 자연히 **bandwidth efficiency / fairness / bounded latency / temporal fidelity** 네 축으로 정리된다.

**"Neuroreality Vision" 조사 — 확인 실패**: 영문/한글 다수 표기로 검색했으나 회사·제품·특허·팀에 대한 신뢰할 수 있는 공개 자료를 찾지 못함. 스타트업 DB, 뉴스, 학술 데이터베이스 어디에도 등장하지 않음. 초기 단계 비공개 기업이거나 표기가 다를 가능성 — **지도교수님께 정확한 회사명(영문 철자 포함)을 직접 확인 권장.**

---

## 6. Bio-mimic 심화 조사 — 인간 시각적 주의(attention) 메커니즘 (RTL 차별화 아이디어용)

> Digital 1차에서 만든 "Foveated AER(FAER)" 아이디어를 더 인간답게 만들 방법을 찾다가, "한 번 본 곳은 주의가 옮겨간다"는 Inhibition of Return(IOR, 복귀 억제) 및 습관화(habituation)를 조사. Klein(2000) 원문 PDF는 여러 미러(wexler.free.fr, scholarpedia)가 이 환경에서 네트워크 차단(ECONNREFUSED)으로 확보 실패했으나, **Klein 본인이 공저한 2013년 계산모델 논문(6-2, arXiv 원문 전체 확보·정독)**과 PMC 신경과학 논문(6-3, 전체 정독)으로 대체 확인함. 저자 동일인이 쓴 더 최신·더 구체적인(수식 포함) 논문이라 원 논문보다 오히려 우리 RTL 설계에 직접 참고 가치가 높음.

6-1. **Itti, L., Koch, C., Niebur, E. — "A Model of Saliency-Based Visual Attention for Rapid Scene Analysis."** *IEEE TPAMI*, 20(11), 1254-1259, 1998.
   (원문 PDF 확보 실패 — 대신 강의 슬라이드 요약본(cse.psu.edu 강의자료)으로 구조 확인, 2차 출처임에 유의) intensity/color/orientation 세 채널을 다중 스케일 Gaussian 피라미드에서 center-surround difference로 뽑아 saliency map을 만들고, **leaky 2D integrate-and-fire 뉴런망으로 구현된 winner-take-all(WTA)**이 최댓값 위치를 선택 → 그 위치 근방의 "전하(charge)"를 방전시켜 다음 순번엔 다른 곳이 선택되게 하는 방식으로 inhibition of return을 구현. 핵심 통찰: WTA가 매번 절대 같은 곳만 고르지 않도록 "누른 뒤 놓아준다(leaky)"는 게 다음 6-2의 DS 이론과 구조적으로 동일한 발상.

6-2. **Satel, J., Story, R., Hilchey, M. D., Wang, Z., Klein, R. M. — "Using a Dynamic Neural Field Model to Explore a Direct Collicular Inhibition Account of Inhibition of Return."** arXiv:1307.5684, 2013. (원문 전체 정독 완료)
   **IOR을 두 개의 독립된 성분으로 분해하는 핵심 논문**:
   - **STD(short-term depression, 조기 감각 순응)**: 큐가 있었던 위치로 들어오는 새 입력의 "크기(magnitude)"를 자극 후 경과시간에 비례해 줄임 — 이게 원래 우리가 "2번(habituation)"이라 부르던 것과 동일한 메커니즘.
   - **DS(direct suppression, 직접 억제)**: 입력 크기와 무관하게, 큐 발생 **약 600ms 후부터** 시작되는 별도의 지연된 억제 신호가 해당 위치의 **baseline 활동 자체**를 낮춤.
   - **핵심 결론(논문이 직접 검증)**: STD 단독으로는 중심 화살표(central arrow) 자극에서의 IOR을 설명 못 하고, DS 단독으로는 짧은 SOA에서의 억제를 설명 못 함 — **둘을 합친 hybrid(STD+DS) 모델만이 실제 행동데이터 전체를 재현**. 즉 **"1번(IOR) 따로, 2번(habituation) 따로"가 아니라 원래 하나의 이중-시간축 메커니즘**이었음이 이 논문에서 실측·수식으로 증명됨.
   - **정량적 시간 파라미터**: IOR은 SOA(자극 간 간격) > 300ms에서 뚜렷하게 나타나고(50ms부터도 검출 가능), 지속시간은 문헌상 약 3초(Vaughan 1984, Samuel & Kat 2003 인용). DS 성분은 큐 이후 약 450~1050ms 구간에서 나타나기 시작(Hilchey et al. 미출판 데이터 기반 추정).
   - **동적 신경장(DNF) 모델 수식** (superior colliculus 중간층(iSC)을 1차원 뉴런장으로 모델링):
     - 근거리 흥분/원거리 억제 가중치: `w_ij = a·exp(-(Δx)²/2σa²) - b·exp(-(Δx)²/2σb²) - c` (a=72, b=24, c=6.4, σa=0.6mm, σb=1.8mm)
     - Leaky 적분 뉴런: `τ·du_i/dt = -u_i + Σ_j w_ij·r_j·Δx + I_i(t) + u0`
     - Sigmoid 발화율: `r_j = 1/(1+exp(-β·u_j+θ))` (β=0.07)
     - DS 억제 입력: 큐 위치 중심 Gaussian, 강도 d=0.5, **큐 발생 600ms 후부터** 인가.
   - **신경 기전**: superior colliculus 중간층(iSC)이 핵심 부위. 원숭이 단일세포기록, SC 병변 환자, 심지어 피질이 거의 없는 궁상어(archerfish)에서도 IOR 관찰돼 "피질 없이도 가능한 원시적 회로"임을 시사.

6-3. **(6-2에서 인용된 관련 신경과학 실측)** PMC 논문 "Neural correlates of spatial orienting in the human superior colliculus" (전체 정독) — SC가 attentional capture(빠른 촉진)와 IOR(느린 억제) 신호를 모두 매개함을 fMRI로 확인. ISI(자극간격) 0~50ms에서는 같은 위치 응답이 더 빠르고(촉진), 200ms 이상부터 더 느려짐(IOR), 400ms에서 억제 최대. 방향 예측성(75% 반대쪽 조건)이 강할수록 같은 위치 불이익이 19ms→42ms로 커짐 — **"예측 가능성이 클수록 순응/억제 효과가 강해진다"**는, Mead 1990의 "예측-비교-오차전달" 원리(0-A(B) 4번 참조)와 개념적으로 정확히 연결되는 결과.

**→ 우리 설계와의 연결 (매우 중요, 방향 전환 포함)**: 생물학적 IOR/habituation의 **기능적 목적은 "이미 본 곳을 그만 보고 새 곳을 탐색"**(foraging/visual search 효율화)으로, **우리 adaptive FAER의 목적("지금 바쁜 곳=물체가 있는 곳을 계속 우선시해서 추적")과 정반대 방향**이다. 따라서 그대로 이식하면 안 되고, "무엇을 위해 쓸지"를 재정의해야 함 — 다만 우리가 이미 실측으로 찾아둔 **미해결 약점(hot이 계속 이겨서 cold 쪽 최악지연이 악화되는 트레이드오프, progress.md 5-9)**을 겨냥한다면 유효하다: "아무리 활동량이 높아도 최근에 이미 많이 서비스받았으면 일정 시간(생물학의 DS처럼 지연된) 강제로 순위를 낮춘다"는 **aging/anti-starvation 메커니즘**을, STD(빠른 크기 감쇠, 이미 v2의 decay_cnt 구조와 유사)와 DS(느린 지연 후 강제 억제, 아직 없음)의 **이중 시간축 조합**으로 설계하면 생물학적 근거가 탄탄하면서도 실용적 개선(최악지연 개선)을 동시에 잡을 수 있음.

## 요약 코멘트

- **Digital 1차**: Boahen(2000)의 대역폭/중재 트레이드오프 분석 + burst-mode word-serial 링크(Boahen 2004)가 "문제 정의 → 개선안 제시" 구조의 뼈대. 여기에 계층적 라우팅(Park 2017), 회전 우선순위 중재(Wei 2019) 등 최신 개선 사례를 더하면 좋음.
- **Digital 2차**: Kim/Handa/Davison(BMVC 2014)과 Guo/Gallego(CMax-SLAM, T-RO 2024)가 "고정 위치, 회전만 하는 카메라 → 파노라마 월드 좌표 누적"이라는 문제 설정이 과제와 사실상 동일 — 가장 강력한 이론적 근거. 삼성/류현석 특허(US9934557, 변환행렬 기반 좌표 매핑)로 회로 구현 관점 보강.
- **Analog 1차**: Delbruck & Mead(1994)의 로그 광수용체가 회로 원형, Yang et al.(2015)의 in-pixel delta modulator가 threshold/in-pixel memory 요구사항에 가장 근접, Graca et al.(2021, 2023, 2024) 시리즈가 노이즈/민감도 최적화의 최신 이론적 근거, Linares-Barranco(2003)가 펨토암페어 전류모드 회로 설계 근거.
- **Analog 2차**: 류현석 교수 공저 Samsung DVS 칩 2편(ISSCC 2017, ISCAS 2020)이 실제 산업 구현 사례로 가장 실전적, Sony/Prophesee(ISSCC 2020)와 SynSense Speck(2023)이 최신 SOTA 판독 아키텍처 벤치마크.
- **Neuroreality Vision**은 공개 정보로 확인 불가 — 지도교수님께 직접 확인 필요.
