# Ryu, Hyunsurk Eric (2019) — "Industrial DVS Design: Key Features and Applications"

*2nd International Workshop on Event-based Vision, CVPR 2019 (Long Beach). Samsung Electronics, System LSI.*
*원문(전 27쪽 슬라이드): https://rpg.ifi.uzh.ch/docs/CVPR19workshop/CVPRW19_Eric_Ryu_Samsung.pdf*

> **트랙**: Digital 1차(전통 AER의 구조적 문제 분석) — reference_papers.md **5-7**, 지도교수(류현석) 본인 발표자료

## ⚠️ 원문 확보 관련 안내

이 파일의 핵심 근거인 CVPRW19 슬라이드(27쪽)는 `pdftotext -layout`으로 전문을 추출해 **직접 정독**했다 — 아래 인용문은 전부 원문 그대로다(짐작·의역 아님). 다만 이 슬라이드 앞뒤 시기(2012~2013년의 응용논문, 2020년 ISCAS 후속칩, 2021년 이후 연구)는 원문 PDF를 확보하지 못하고 **DBLP 서지정보 + 검색 스니펫만으로 확인**했다 — 해당 항목은 본문에 ⚠️로 표시했다. 정식 논문이 아닌 발표자료(정식 학술지 심사를 거치지 않음)라는 점도 인용 시 유의할 것.

## 🔰 완전 초보용 한 줄 요약

류현석 교수가 삼성 재직 시절 DVS 칩을 4세대(Gen1→Gen4)에 걸쳐 만들면서, "전통적인 AER이 왜 문제냐"에 대한 본인의 생각이 어떻게 바뀌었는지를 그 자신이 정리한 발표자료다. 처음엔 "너무 느리다(처리량 부족)"가 문제였는데, 그걸 고치고 나니 "빨라도 누구는 먼저 처리되고 누구는 늦게 처리된다(불공정)"가 보였고, 더 파보니 "늦게 처리된 이벤트는 실제 생긴 시각과 읽힌 시각이 어긋나서 영상 자체가 일그러진다(motion artifact)"는 더 근본적인 문제를 발견했다는 이야기다.

## 이 발표자료를 왜 읽는가

지도교수 본인이 "전통적 AER의 무엇이 문제였는가"를 커리어 순서대로 직접 정리해놓은 유일한 1차 자료다. 대회 과제(전통적 AER 통신의 문제점 분석 + 개선안 제시)의 심사 기준을 가늠하는 데 가장 직접적인 참고가 된다 — 우리가 "문제"라고 정의하는 축이 그가 실제로 문제라고 여겨온 축과 얼마나 겹치는지 스스로 점검할 수 있다.

## 1. 문제의식의 시간적 전개 (슬라이드 원문 기준)

### 1-A. Gen1(2014, R&D Ver.) — 출발점: 순수 픽셀 단위 중재의 낮은 처리량

640×480, 9μm 픽셀, **"Row Arbiter + Addr. Decoder"**와 **"Column Arbiter + Addr. Decoder"**로 구성된 전형적인 행·열 이중 중재 구조. **Max. event processing rate: 6.5 Meps**, 인터페이스는 20-bit Parallel. (슬라이드 3)

VGA급 해상도에서 픽셀 하나하나를 개별적으로 중재·인코딩하는 순수 AER 구조로는 6.5 Meps가 한계였다는 것이 이 세대의 출발 지점.

### 1-B. Gen2(2016, R&D Ver., ISSCC'17) — G-AER: 처리량 문제를 정면 돌파

**"Digitally synthesized G-AER(Group Address Event Representation) for high throughput"**, **Max. event processing rate: 300 Meps**(Gen1 대비 약 46배). 인터페이스는 MIPI 1Gbps 4-lane으로 확장. (슬라이드 4)

핵심 발상 전환은 슬라이드 12("AER induced latency")에 명시된 두 문장에 담겨 있다:

> "Original AER handles the individual pixel data with address, polarity, and event generation time."
> "Group addressing reduces the latency by the interface bandwidth limitation"

즉 "이벤트 하나마다 주소+극성+시각을 개별 전송한다"는 전통 AER의 기본 전제 자체를 문제의 근원으로 지목하고, 인접 픽셀들을 그룹으로 묶어(word-serial) 보내는 방식으로 **인터페이스 대역폭이 만드는 지연**을 줄인 것.

### 1-C. G-AER 이후, 새로 눈에 들어온 문제 — "빠른데 불공정하다"

처리량을 올리고 나자 다음 문제가 명시적으로 슬라이드 제목이 된다. 슬라이드 10 제목 그대로:

> **"Artifacts and delay by unfair arbitration"**

column arbiter가 동시에 들어온 여러 열 요청 중 하나를 고를 때, 그 선택이 "unfair arbitration"(슬라이드 내 라벨)이라는 것 — 즉 어떤 이벤트는 곧바로 처리되고 어떤 이벤트는 여러 차례 밀려서 처리되는, **이벤트별로 균일하지 않은 지연**이 문제로 재정의된다.

### 1-D. 더 근본적인 재정의 — "느린 게 문제가 아니라, 시각 자체가 왜곡된다"

슬라이드 13, 제목 **"AER induced motion artifact"**:

> "Image artifact could be induced by the mismatch between event generation time and readout time under high event rate condition"

같은 슬라이드에서 "Word-serial AER using Arbiter"(비순차 중재)와 "Sequential Column Selection"(순차 스캔) 두 방식의 **Timestamp Error(Latency) vs Average Event Rate** 그래프를 나란히 놓고, 이벤트율이 올라갈수록 중재 기반 방식의 타임스탬프 오차가 순차 스캔 방식보다 훨씬 빠르게 커짐을 보여준다. 즉 "불공정한 지연"이 단순히 사용자 체감 지연 문제가 아니라, **이벤트가 실제로 발생한 시각과 센서가 그걸 읽어낸 시각이 어긋나면서 재구성된 영상 자체가 일그러지는(motion artifact) 문제**로 이어진다는 것을 정량적으로 논증한다.

### 1-E. Gen3(2018, Product Ver.) — 역설적 해법: 중재를 버리고 순차 스캔으로

**"Global hold, Global reset, Column scan readout"**이 핵심 기능. (슬라이드 5)

> "Motion image artifact minimized by using global hold and global reset"
> "Timestamp error minimized by applying sequential column scan readout"

즉 Gen2에서 "빠르게 하기 위해" 쓴 중재(arbitration) 구조를, Gen3에서는 **"시간 정합성을 지키기 위해" 임의 순서(arbitrary column selection) 대신 순차 순서(sequential column selection)로 되돌린다** — 슬라이드 13의 비교 그림에 "Arbitration" vs "Sequential Scanning"이라는 대비되는 두 구조가 나란히 그려져 있다. 처리량 극대화(G-AER, 중재)에서 시간적 충실도(global hold + sequential scan)로 설계 우선순위가 이동한 세대.

### 1-F. 마지막 슬라이드 — 그럼에도 여전히 대역폭이 첫 번째 과제

슬라이드 27, "Remaining issues and research topics"의 첫 항목:

> "bandwidth minimization for higher event rate and spatial resolution"

Gen2에서 G-AER로 300 Meps까지 올렸음에도, 2019년 시점에 그는 이걸 "해결된 문제"로 적지 않고 **해상도·이벤트율이 계속 커지는 한 구조적으로 계속 따라오는 미해결 과제**로 정리했다. 즉 그의 관점에서 "처리량"과 "시간적 충실도"는 하나를 풀었다고 다른 하나가 사라지는 관계가 아니라, 계속 같이 안고 가야 하는 두 축으로 보인다.

## 2. 시간적으로 확장한 앞뒤 맥락 (⚠️ 서지정보/스니펫 수준, 원문 미확보)

### 2-A. 발표자료 이전(2012~2013) — 회로 설계자이기 전, 이벤트의 "소비자"

DBLP 서지정보 기준, Delbrück·Park 등과 손짓 UI(ICIP 2012), 제스처 인식(ICPR 2012), 스테레오 DVS 원격제어 라이브 데모(ISCAS 2012, Best Live Demo 수상), 양이 소리위치추정(EMBC 2013) 논문에 참여. 이 시기엔 남이 만든 DVS 센서의 이벤트 출력을 응용 알고리즘에 활용하는 입장이었다 — 자신이 회로를 설계하기 전에, 먼저 "이벤트 기반 처리가 왜 유리한가"를 응용 레벨에서 확립해둔 단계로 읽힌다. ⚠️ 서지정보만 확인, 원문 미확보.

### 2-B. Gen4(2020, R&D Ver., ISCAS'20) — Gen3 해법의 고해상도 확장 (2026-08-19 원문 확보·검증 완료)

슬라이드 6(CVPRW19 자료 내 포함, 이 부분은 직접 확인됨): 1280×960, 4.95μm 픽셀(Gen1~3의 9μm 대비 픽셀피치 축소), two-stack wafer bonding, **">1,000 fps(MIPI)"**, 140mW.

**이전에 ⚠️ 미확보였던 ISCAS 2020 논문 자체(12쪽 발표 슬라이드) 원문을 확보해 정독 완료** — 별도 파일 **[[P5_Suh2020_ISCAS_MotionArtifactMinimization]]** 참고. 결론은 예상대로 **Gen3의 "순차 스캔 + global hold" 해법을 그대로, 더 높은 해상도(1280×960, 1.3 Geps)로 확장**한 것이지만, 원문에서 새로 확인된 중요한 점 두 가지: (1) Global Hold를 실제로 오래(10ms+) 유지하려면 GIDL 누설전류로 인한 "주기적 가짜 이벤트"라는 새 회로 문제가 생기고, 이를 막는 전용 회로(GIDL-suppressed reset switch)가 별도로 필요했다 — Gen3 슬라이드(2019)엔 없던 디테일. (2) 전체 12쪽에 걸쳐 "주소 오버헤드/비트 효율"이라는 단어가 **단 한 번도 등장하지 않는다** — 류 교수의 실제 최종 해법은 정보이론적 인코딩 최적화가 아니라 "순차 스캔의 비효율을 압도적 인터페이스 대역폭(2.5Gbps MIPI 4-lane)으로 흡수"하는, 완전히 다른 축의 해법이었다.

### 2-C. 2021년 이후 — 이벤트 희소성을 시스템 전력 절감으로 활용

DBLP 서지정보 기준, 프레임-이벤트 보간(2021), 초경량 얼굴활성화(2022)를 거쳐 최근(2023~2025)엔 DVS-CIS 센서 융합 + event-based NPU triggering 감시시스템 연구로 이어진다. 스니펫 기준 요지: "DVS 기반 ROI 검출기가 트리거 역할을 하고, 그 신호로만 NPU(객체탐지)를 구동 — 24시간 기준 에너지 31.5% 절감." 2014년(TNNLS, P2 참고) 시절 주장했던 "이벤트 방식=저전력·저지연"이라는 응용 레벨 명제가, 10년 뒤 시스템 차원의 전력 게이팅 신호로 구체화된 형태로 볼 수 있다. ⚠️ 서지정보/초록 스니펫만 확인, 원문 미확보.

## 3. 문제의식의 흐름 요약 (원문 근거 기반)

```
개별 픽셀 단위 처리 → 처리량 한계(6.5 Meps)              [Gen1, 2014]
        ↓
그룹 단위(G-AER) 전송으로 대역폭·지연 완화 → 300 Meps      [Gen2, 2016/ISSCC'17]
        ↓
처리량은 풀렸지만 "unfair arbitration"이 이벤트별 지연 편차를 만듦   [슬라이드 10]
        ↓
그 지연 편차가 event generation time ≠ readout time을 유발 → motion artifact  [슬라이드 12-13]
        ↓
해법: 중재(arbitration)를 버리고 순차 스캔(sequential column scan) + global hold로 회귀  [Gen3, 2018]
        ↓
그럼에도 해상도·이벤트율이 계속 커지는 한 "bandwidth minimization"은 여전히 미해결 과제  [2019 결론]
```

## 초보자를 위한 용어 미니 사전

- **G-AER(Group Address-Event Representation)**: 픽셀 하나마다 개별 주소를 실어 보내는 대신, 인접한 여러 픽셀을 그룹으로 묶어 한 번에(word-serial) 전송하는 방식. 이벤트당 오버헤드(주소/타이밍 정보)를 줄여 처리량을 높인다.
- **Column Arbiter / unfair arbitration**: 여러 열(column)에서 동시에 이벤트 요청이 들어올 때 하나씩 순서를 정해 처리하는 회로. "unfair"는 이 순서 결정이 매번 균일하지 않아서, 어떤 열은 항상 먼저 어떤 열은 항상 나중에 처리되는 편향이 생길 수 있다는 뜻.
- **Global hold / Global reset**: 배열 전체 픽셀의 이벤트를 한 순간에 동시에 "고정(hold)"해서 읽어내는 방식. 픽셀마다 다른 시각에 읽으면 생기는 시간 왜곡을 막기 위한 기법.
- **Sequential column scan**: 중재기가 매번 다른 순서로 열을 고르는 대신, 항상 정해진 순서(0열→1열→2열…)로 훑어 읽는 방식. 순서가 결정적(deterministic)이라 타임스탬프 오차의 패턴을 예측·관리하기 쉬워진다.
- **Motion artifact(모션 아티팩트)**: 같은 순간에 발생한 이벤트들이 실제로는 서로 다른 시각에 읽혀서, 재구성한 영상에서 움직이는 물체의 윤곽이 휘거나 끊기거나 왜곡되어 보이는 현상.
