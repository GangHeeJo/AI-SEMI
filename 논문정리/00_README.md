# 논문 정리 — 읽는 순서 안내

각 파일은 논문 1편을 약 1페이지 분량으로 정리한 것. 초보자를 위한 용어 설명을 중간중간 넣었고, 별 개수(★)는 대회 논증에서의 중요도.

## 공통 기초 (칼텍 Carver Mead 계열 — 먼저 읽을 것)

| 중요도 | 파일 | 저자(연도) | 한줄 요약 |
|---|---|---|---|
| ★★★ | [01_Mead1990_NeuromorphicSystems.md](01_Mead1990_NeuromorphicSystems.md) | Mead (1990) | "신경형태" 용어 정립 + 배선 스케일링 법칙 — Digital 1차의 핵심 이론적 근거 |
| ★★★ | [02_Mahowald1992_Thesis.md](02_Mahowald1992_Thesis.md) | Mahowald 박사논문 (1992) | **AER(주소-이벤트 통신) 개념이 최초로 정식화된 원전** |
| ★★☆ | [00_Mead1988_SiliconModel.md](00_Mead1988_SiliconModel.md) | Mead & Mahowald (1988) | 최초의 실리콘 망막 회로 — Analog 1차(DVS 픽셀)의 원형 |

**추천 순서**: Mead 1988 → Mahowald 1992(AER 탄생) → Mead 1990(이론적 근거). 시간 순서로 읽으면 "왜 AER이 필요했는지"가 자연스럽게 이어진다.

## Digital 1차 — 전통적 AER 분석 및 개선 방향

| 파일 | 저자(연도) | 한줄 요약 |
|---|---|---|
| [D1_01_Boahen2000.md](D1_01_Boahen2000.md) | Boahen (2000) | AER 채널 설계 이론 정립 — 대역폭·중재·큐잉 트레이드오프 |
| [D1_02_Boahen2004.md](D1_02_Boahen2004.md) | Boahen (2004) | 행 단위 병렬 판독 + 순차 주소 전송으로 핀 수 절반화 |
| [D1_03_Park2017_HiAER.md](D1_03_Park2017_HiAER.md) | Park et al. (2017) | 계층적 라우팅(HiAER)으로 단일 버스의 한계 돌파 ⚠️원문 미확보, 후속 공개논문 기반 |
| [D1_04_Wei2019_RotationArbiter.md](D1_04_Wei2019_RotationArbiter.md) | Wei et al. (2019) | 회전 우선순위 중재기로 "고정 잡음" 공정성 문제 해결 ⚠️초록 기반 |

## 지도교수(류현석) 관련 논문·특허

| 중요도 | 파일 | 저자(연도) | 한줄 요약 |
|---|---|---|---|
| ★★★ | [P1_Patent9934557_CoordTransform.md](P1_Patent9934557_CoordTransform.md) | US Patent 9,934,557 (2018) | 변환행렬 T로 이벤트 정합 — Digital 2차 좌표변환과 문제 설정이 거의 동일 |
| ★★☆ | [P2_Lee2014_GestureInterface.md](P2_Lee2014_GestureInterface.md) | Lee et al. (2014) | 스테레오 DVS 기반 실시간 제스처 인식 — AER의 실전 응용 사례 ⚠️초록 기반 |
| ★★☆ | [P3_Son2017_DVS_AER.md](P3_Son2017_DVS_AER.md) | Son et al. (2017, ISSCC) | 640×480, 9μm 픽셀, 300Meps AER — 공유픽셀+TDM으로 대역폭 절감 ⚠️초록도 미확보, 관련 특허 기반 |

---

**⚠️ 표시된 파일**: 유료 학회지라 원문 PDF를 구하지 못해 초록·서지정보 또는 관련 공개논문/특허 기반으로 작성함. 정식 인용 전 원문 확인 권장.

**다음 계획(미착수)**: Digital 2차(좌표변환/월드메모리), Analog 1차(DVS 픽셀), Analog 2차(어레이+AER 리드아웃) 트랙 자체 논문 조사는 아직 진행 안 함(단, 지도교수 특허 P1이 Digital 2차와 상당 부분 겹침).
