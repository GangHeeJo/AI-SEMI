# Suh, Y., Choi, S., Ito, M., Kim, J., Lee, Y., Seo, J., Jung, H., Yeo, D.-H., Namgung, S., Bong, J., Yoo, S., Shin, S.-H., Kwon, D., Kang, P., Kim, S., Na, H., Hwang, K., Shin, C., Kim, J.-S., Park, P. K. J., Kim, J., **Ryu, H.**, Park, Y. (2020) — "A 1280×960 Dynamic Vision Sensor with a 4.95-μm Pixel Pitch and Motion Artifact Minimization"

*IEEE ISCAS(International Symposium on Circuits and Systems) 2020, Virtual, Oct 10-21 2020. Samsung Electronics, South Korea.*
*원문(12쪽 발표 슬라이드, IEEE Xplore 공식 세션 자료로 공개): https://confcats-event-sessions.s3.amazonaws.com/iscas20/slides/1303.pdf*

> **트랙**: Digital 1차(전통 AER의 구조적 문제 분석, 특히 5·6번 문제의 "실제 양산칩에서의 최종 해법") + Analog 1·2차(픽셀 회로) 공통 — reference_papers.md **4-4 / 5-3**, 지도교수(류현석) 공저. P4(2019 CVPRW 슬라이드)가 "Gen3(2018)에서 중재를 버리고 순차 스캔+global hold로 전환했다"고 개념적으로 서술한 그 해법을, **더 높은 해상도(1280×960)로 확장한 후속 칩에서 실측 사진·회로도·정량 비교표까지 갖춰 검증한 논문**.

## 🔰 완전 초보용 한 줄 요약

앞서 P4에서 "류현석 교수가 Gen3에서 중재(arbitration)를 버리고 순서대로 훑어읽기(순차 스캔)+한번에 딱 멈춰서 읽기(global hold)로 바꿨다"고 봤는데, 이 논문은 그 방식을 더 큰 센서(가로세로 픽셀 각각 2배 가까이)에 적용해서 실제로 "돌아가는 선풍기를 찍었을 때 색이 안 뭉개지는 사진"까지 보여주며 증명한 논문이다. 동시에 "가만히 오래 저장해두면 전하가 새서 가짜 이벤트가 생긴다"는 새로운 부작용을 회로로 막는 방법(GIDL 억제)도 새로 추가했다.

## 이 논문을 왜 읽는가

우리 팀은 §76에서 "진짜 Global Hold(주기적 스냅샷)를 RTL로 만들어 실측했더니 jitter/손실이 오히려 악화됐다"고 결론 내렸다. 그런데 류현석 교수 본인의 실제 양산급 칩은 정확히 이 Global Hold(+순차 스캔) 방식을 최종 해법으로 택해서 **성공적으로** 썼다. 이 모순처럼 보이는 지점을 이해하려면 이 논문을 직접 읽어야 한다 — 결론부터 말하면, 그의 칩과 우리 시스템은 "무엇을 자원으로 쓸 수 있는가"라는 전제 자체가 다르다(§4 참고).

## 1. Introduction — 무엇을 "해결됐다"고 주장하는가 (슬라이드 3)

> "Side effects from scaled-down technology and motion artifacts are solved."

**주의**: 이 문장이 이 논문에서 "solved"라는 단어가 등장하는 유일한 곳이다. 그런데 정작 발표 제목과 Summary(슬라이드 12)는 전부 **"Minimization"**(최소화)이지 "Elimination"(제거)이 아니다 — 즉 저자들 스스로도 "완벽히 없앴다"가 아니라 "실용적으로 충분히 줄였다"는 톤으로 결론을 낸다는 점이 중요하다.

## 2. 새로 추가된 회로 문제 — Global Hold를 실제로 쓰려면 반드시 풀어야 했던 부작용 (슬라이드 5-6)

P4(2019 CVPRW)는 "Global hold, Global reset, Column scan readout"을 Gen3의 핵심 기능으로만 짧게 언급했는데, 이 논문은 그 Global Hold를 **실제 회로로 장시간(10ms+) 유지**하려 했을 때 생기는 새 문제를 다룬다:

> "Leakage currents flowing into the floating node induces the periodic false event generation."
> "GIDL of M_RESET is the dominant source of the leakage currents and it is derived from large V_GS,P after reset operation finishes."

이벤트를 저장해두는 floating node에 reset 트랜지스터의 GIDL(Gate-Induced Drain Leakage) 전류가 새어 들어가서, **아무 일도 없었는데 저절로 가짜 이벤트가 주기적으로 발생**한다는 것. 해법은 **GIDL-suppressed reset switch**(reset 전압을 픽셀별·시점별로 적응적으로 샘플링해서 reset 직후 V_GS,P를 0으로 만듦) — 실측 결과, 이 스위치가 "false event 발생 주기가 1초 미만인 픽셀 비율"을 기존 대비 대폭 줄임(누적분포그래프, conventional은 10%에서 이미 대다수 픽셀이 걸리는 반면 GIDL-suppressed는 1% 근처).

**의미**: Global Hold는 "그냥 값을 붙잡아두면 된다"는 단순한 아이디어가 아니라, **그 자체로 새로운 아날로그 신뢰성 문제(누설전류)를 만들고, 그걸 막는 전용 회로가 따로 필요했다**는 것. 우리가 §76에서 만든 "real Global Hold" RTL은 디지털 레지스터로 값을 그냥 붙잡아두는 모델이라 이 문제 자체가 존재하지 않는다 — 즉 류 교수의 real Global Hold가 극복해야 했던 진짜 난관은 우리 문제(동기 클럭 중재 지연)와는 **다른 층위(아날로그 회로 신뢰성)**의 것이었다.

## 3. Motion Artifact Minimization — 핵심 대조 (슬라이드 7-8)

### 3-A. 중재 vs 순차 스캔 (슬라이드 7)

슬라이드에 실린 그림은 P4에서 언급한 "Fair Arbiter" 트리 구조(우리 arbiter4_tree/arbiter2와 정확히 같은 형태의 이진 트리 다이어그램!)와 "Sequential Column Selection"(DTAG→Column Driver, "No Column Requests"라고 명시 — 즉 **요청 자체를 아예 안 받고 그냥 순서대로 훑는다**)을 나란히 비교한다.

> column# vs time 그래프: arbitration 방식은 지그재그(랜덤 순서)로 열을 고르고, sequential 방식은 단조증가(1→2→3...→8)로 고른다.

**실측 사진(회전하는 선풍기)**: arbitration 방식은 빨강/초록 날개 궤적이 특정 구간(원으로 표시)에서 서로 뒤섞여 뭉개지고("motion artifact"라고 직접 라벨링됨), sequential readout은 궤적이 깔끔하게 분리된다.

### 3-B. Global Event-Holding (슬라이드 8)

> "Global Event-Holding Function is implemented to avoid a jello effect."
> "The cascaded structure of the in-pixel storage secures the sampled event voltage from the channel leakage."

Global Hold 없이 찍으면("w/o global event-holding") 날개 끝부분이 휘어지는 "jello effect"(롤링셔터 카메라에서 흔히 보이는, 헬리콥터 프로펠러가 휘어 보이는 그 현상과 같은 종류)가 나타나고, 있으면("w/ global event-holding") 사라진다 — 두 사진 다 실측.

## 4. Performance Comparison — 왜 이게 우리 시스템과 전제가 다른지 (슬라이드 11)

이 표가 이 논문에서 가장 중요한 정량적 근거다:

| | This work(2020) | ISSCC 2017(Gen2) | VLSI 2019 |
|---|---|---|---|
| Resolution | 1280×960 | 640×480 | 132×104 |
| **Readout** | **Sequential** | Arbitration | Sequential |
| **Max Event Rate** | **1.3 Geps** | 300 Meps | 180 Meps |
| In-Pixel Storage | Yes | No | Yes |
| Interface | MIPI (2.5-Gbps 4-lane) | MIPI | Parallel |

> "The highest resolution and the highest event rate were achieved."
> "2.5-Gbps 4-lane MIPI is integrated to transfer 1.3 × 10⁹ events in a second."

**결정적 관찰**: 이 표에서 **가장 빠른 칩(1.3 Geps)이 오히려 arbitration이 아니라 sequential 방식**이다. 우리가 §76에서 (동기 클럭+고정 처리용량이라는 우리 시스템의 전제 아래) "sequential/global-hold류는 처리량·지연 면에서 arbitration보다 불리하다"고 실측한 것과 정면으로 배치되는 것처럼 보인다. 그런데 그 이유는 R열의 **"2.5-Gbps 4-lane MIPI"**에 있다 — 이 칩은 **순차 스캔이 만드는 "이벤트 없는 칸까지 다 훑어야 하는 낭비"를 감당하고도 남을 만큼 압도적인 직렬 인터페이스 대역폭을 그냥 하드웨어로 더 태워 넣었다.** 즉 그의 해법은 "인코딩을 더 똑똑하게 한다"가 아니라 **"순차 스캔의 비효율을 대역폭으로 밀어붙여서 무의미하게 만든다"**는, 우리가 §69~79에서 추구해온 "비트당 정보이론적 최적화" 축과는 **완전히 다른 축의 해법**이다. 이 논문 12쪽 전체에서 "bit", "address overhead", "encoding efficiency" 같은 단어는 **단 한 번도 등장하지 않는다** — 그의 관심사는 오직 event rate(처리량)과 motion artifact(화질)뿐이었다.

## 5. 우리 대회 설계와의 연결

- **§76(real Global Hold RTL 실측)의 "실패"를 재해석**: 우리 결과("jitter/손실 악화")는 틀린 게 아니라, **"고정된 사이클당 처리용량 + 순수 디지털 동기 시스템"이라는 우리가 세운 전제 안에서는 참**이다. 류 교수의 real Global Hold가 성공한 건 그 전제(고정 처리용량) 자체를 대역폭으로 깨버렸기 때문 — 우리 대회 환경(정해진 게이트/핀 수, 특정 클럭)에서 이 정도 규모의 인터페이스 대역폭 확장이 허용되는지가 관건.
- **"1번(주소오버헤드)을 완벽히 해결한다"는 게 류 교수의 실제 최종 답이 아니었다**: 그가 실제로 양산까지 간 칩은 주소 인코딩을 정보이론적으로 최적화하는 방향(우리가 §69~79에서 판 bitmap/EF/entropy-bound 방향)을 아예 택하지 않았다. 대신 **문제의 정의 자체를 바꿔서("주소를 아껴 쓰자"가 아니라 "주소가 필요없게 만들자"+"그래도 남는 낭비는 대역폭으로 흡수하자") 우회**했다. 이건 우리에게 두 가지 시사점을 준다: (1) 우리의 entropy-bound 접근은 류 교수가 실제로 걸어간 길이 아니므로 "그가 못 푼 걸 우리가 풀었다"는 주장은 성립 안 함 — 오히려 그가 아예 시도조차 안 한 다른 축; (2) 반대로 이게 강점이 될 수도 있음 — 그가 대역폭을 무제한처럼 쓸 수 있는 실리콘/공정 자원이 있었기에 가능했던 해법이라면, **자원 제약이 훨씬 빡빡한 우리 대회 환경에서는 오히려 "비트를 아끼는" 방향이 더 적합한 답일 수 있음**(대회가 "칩 하나를 양산하는 게 아니라 제한된 게이트로 설계하는" 맥락이라면).

## 초보자를 위한 용어 미니 사전

- **GIDL(Gate-Induced Drain Leakage)**: 트랜지스터를 끈 상태(off)에서도 게이트-드레인 사이 강한 전계 때문에 아주 작은 전류가 계속 새는 현상. 값을 오래 저장해야 하는 회로(예: Global Hold의 저장 노드)에서는 이 미세한 전류가 누적돼 저장된 값을 왜곡시킬 수 있다.
- **Jello effect(젤로 효과)**: 롤링셔터 카메라나 시간차를 두고 읽어내는 센서에서, 빠르게 움직이는 물체(헬리콥터 프로펠러 등)가 마치 젤리처럼 휘어 보이는 왜곡 현상. 화면의 위쪽과 아래쪽을 서로 다른 시각에 읽어서 생긴다.
- **Cu-Cu wafer bonding(구리-구리 웨이퍼 본딩)**: 픽셀 회로가 있는 웨이퍼와 나머지 회로(로직)가 있는 웨이퍼를 각각 따로 만든 뒤 구리 패드로 정밀하게 붙이는 3차원 집적 기술. 픽셀 하나에 다 넣기 어려운 회로를 아래쪽 웨이퍼로 옮겨서 픽셀 피치를 더 줄일 수 있게 해준다.
- **MIPI**: 모바일 기기(스마트폰 카메라 등)에서 표준으로 쓰는 고속 직렬 인터페이스 규격. 여러 레인(lane)을 병렬로 묶어 대역폭을 늘릴 수 있다(이 논문은 4-lane, 레인당 2.5Gbps급).
