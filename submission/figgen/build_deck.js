// 2차 결과 발표자료 생성 스크립트. 사용: node build_deck.js <출력.pptx> <이미지폴더(results_delta)>
const pptxgen = require("pptxgenjs");
const path = require("path");
const OUT = process.argv[2];
const IMG = process.argv[3];
const img = (f) => path.join(IMG, f);
const FIG = process.argv[4];
const fs = require("fs");
const fig = (f) => path.join(FIG, f);
const hasFig = (f) => fs.existsSync(fig(f));

const INK = "1D1D1F", TEAL = "0066CC", AMBER = "0066CC", LIGHT = "F5F5F7", MID = "7A7A7A", RED = "1D1D1F", GREEN = "0066CC", WHITE = "FFFFFF", PALE = "F5F5F7";
const BLUE_D = "2997FF", DARK = "272729", HAIR = "E0E0E0", MUTED_D = "CCCCCC";
const FONT = "나눔스퀘어 네오 Regular";

const pres = new pptxgen();
pres.layout = "LAYOUT_WIDE"; // 13.33 x 7.5
pres.title = "회전 이벤트 카메라용 월드 좌표 변환·월드 메모리 회로 (2차 결과)";
pres.author = "REDRED";
pres.theme = { headFontFace: FONT, bodyFontFace: FONT };

["CONTENT", "PARCH"].forEach((nm) => pres.defineSlideMaster({
  title: nm, background: { color: nm === "CONTENT" ? WHITE : LIGHT },
  objects: [
    { text: { text: "팀 REDRED · Digital 2차", options: { x: 0.6, y: 7.08, w: 5, h: 0.3, fontFace: FONT, fontSize: 10, color: MID, margin: 0 } } },
  ],
  slideNumber: { x: 12.2, y: 7.08, w: 0.6, h: 0.3, fontFace: FONT, fontSize: 10, color: MID, align: "right" },
  margin: [0.5, 0.6, 0.5, 0.6],
}));
pres.defineSlideMaster({ title: "DARK", background: { color: DARK } });

let n = 0;
function content(title, notes) {
  const s = pres.addSlide({ masterName: n % 2 ? "PARCH" : "CONTENT" });
  s.addText(title, { x: 0.6, y: 0.35, w: 12.1, h: 0.95, fontFace: FONT, fontSize: 26, bold: true, color: INK, valign: "middle", margin: 0, isTextBox: true, fit: "shrink" });
  if (notes) s.addNotes(notes);
  n++;
  return s;
}
const T = (s, text, o) => s.addText(text, Object.assign({ fontFace: FONT, color: INK, fontSize: 15, margin: 0, isTextBox: true, valign: "top" }, o));
function card(s, x, y, w, h, head, body, o = {}) {
  s.addShape(pres.ShapeType.roundRect, { x, y, w, h, fill: { color: o.fill || WHITE }, line: { color: HAIR, width: 0.75 }, rectRadius: 0.12 });
  T(s, head, { x: x + 0.2, y: y + 0.15, w: w - 0.4, h: 0.4, fontSize: 16, bold: true, color: o.headColor || TEAL });
  T(s, body, { x: x + 0.2, y: y + 0.6, w: w - 0.4, h: h - 0.75, fontSize: o.size || 14, color: INK });
}
function bullets(items, o = {}) {
  return items.map((t, i) => ({ text: t, options: { bullet: true, breakLine: i < items.length - 1, paraSpaceAfter: o.gap === undefined ? 6 : o.gap } }));
}
function table(s, rows, x, y, w, colW, o = {}) {
  const body = rows.map((r, ri) => r.map((c) => {
    const isH = ri === 0;
    const cell = typeof c === "object" ? c : { text: String(c) };
    return { text: cell.text, options: Object.assign({ fontFace: FONT, fontSize: o.size || 13, color: INK, bold: isH || !!cell.bold, fill: { color: isH ? LIGHT : WHITE }, valign: "middle", margin: [0.04, 0.08, 0.04, 0.08], border: { type: "solid", pt: 0.5, color: HAIR } }, cell.options || {}) };
  }));
  s.addTable(body, { x, y, w, colW, rowH: o.rowH || 0.42, autoPage: false });
}
const chartBase = (title, colors) => ({
  showTitle: true, title, titleFontFace: FONT, titleFontSize: 14, titleColor: INK,
  chartColors: colors, showLegend: false, showValue: true, dataLabelPosition: "outEnd", dataLabelFontFace: FONT, dataLabelFontSize: 12, dataLabelColor: INK,
  catAxisLabelFontFace: FONT, catAxisLabelFontSize: 12, catAxisLabelColor: INK, valAxisLabelFontFace: FONT, valAxisLabelFontSize: 11, valAxisLabelColor: MID,
  valGridLine: { color: "E8E8ED", size: 0.5 }, catGridLine: { style: "none" }, barGapWidthPct: 60,
});

// ---------- 1. 표지
{
  const s = pres.addSlide({ masterName: "DARK" });
  T(s, "2026 전국 대학생 AI 반도체 회로 설계 경진대회 · Digital 트랙 2차 결과", { x: 0.8, y: 1.0, w: 11.7, h: 0.4, fontSize: 16, color: MUTED_D });
  T(s, "회전하는 이벤트 카메라를\n하나의 월드 지도로 옮기는 저전력 회로", { x: 0.8, y: 1.9, w: 11.7, h: 2.2, fontSize: 40, bold: true, color: WHITE, valign: "top" });
  T(s, "Event camera world-coordinate transform & world memory (RTL, P&R)", { x: 0.8, y: 4.3, w: 11.7, h: 0.5, fontSize: 18, color: BLUE_D });
  T(s, "팀 REDRED", { x: 0.8, y: 6.3, w: 11.7, h: 0.4, fontSize: 16, color: MUTED_D });
  s.addNotes("안녕하세요, 팀 REDRED입니다. 이번 2차 과제에서 저희는 회전하는 이벤트 카메라가 내보내는 이벤트를 하나의 월드 메모리에 정확히, 그리고 가장 적은 전력으로 쌓는 회로를 설계했습니다. 10분 동안 문제 정의, 설계, 검증 결과, 그리고 한계까지 말씀드리겠습니다.");
  n++;
}

// ---------- 2. 문제 정의
{
  const s = content("문제 정의: 센서가 돌아도 지도는 제자리에 있어야 한다",
    "이벤트 카메라는 밝기가 변한 픽셀의 주소와 극성만 내보냅니다. 카메라가 회전하면 같은 물체가 센서 위의 다른 픽셀에서 발화하므로, 이벤트를 그대로 쌓으면 소용돌이처럼 번집니다. 교수님 Q&A에서 확인된 전제는 회전 180도 이내, 평행 이동 없음입니다. 우리가 푸는 문제는 회전각 세타를 이용해 이벤트마다 센서 좌표를 월드 좌표로 바꿔 월드 메모리에 쓰는 회로입니다. 평가는 문제 정의, 해결의 설득력, 구현 가능한 회로, 안정성 논증이라는 네 가지로 이해했고, 그 기준으로 발표를 구성했습니다.");
  card(s, 0.6, 1.55, 3.9, 1.95, "입력", "센서 960×720\n이벤트 = 주소 (x, y) + 극성\n회전각 θ (외부 공급 또는 추정)", { size: 15 });
  card(s, 4.72, 1.55, 3.9, 1.95, "제약 (교수 Q&A 확정)", "회전 180° 이내\n평행 이동 없음 (미세하게만)\n표면만 보는 2차원 월드 메모리", { size: 15 });
  card(s, 8.84, 1.55, 3.9, 1.95, "출력", "월드 메모리\n칸마다 이벤트 유무 + 극성\n호스트용 읽기 포트", { size: 15 });
  s.addImage({ path: img("worldmap_uncorrected_vs_omega_only.png"), x: 0.6, y: 3.7, w: 3.2, h: 3.2 });
  T(s, "회전을 보정하지 않고 쌓으면(위) 소용돌이로 번지고, 회전각으로 좌표를 바꿔 쌓으면(아래) 방의 구조가 보인다. (실제 DELTA 센서 영상, 소프트웨어 모델)", { x: 4.05, y: 3.9, w: 3.7, h: 2.5, fontSize: 15, color: MID });
  s.addShape(pres.ShapeType.roundRect, { x: 8.0, y: 3.7, w: 4.74, h: 3.2, fill: { color: DARK }, line: { color: DARK }, rectRadius: 0.12 });
  T(s, "우리가 정한 평가 관점", { x: 8.25, y: 3.9, w: 4.3, h: 0.4, fontSize: 17, bold: true, color: BLUE_D });
  T(s, bullets(["이벤트를 잃지 않고 정확한 칸에 쓰는가", "구현 가능한 면적·전력인가", "회로가 실제 데이터에서 안정적인가", "한계를 스스로 설명할 수 있는가"], { gap: 4 }), { x: 8.25, y: 4.5, w: 4.3, h: 2.2, fontSize: 16, color: WHITE });
}

// ---------- 3. 타겟 시나리오와 크기
{
  const s = content("타겟은 로봇팔 손목 카메라, 크기는 이유와 함께 제안한다",
    "월드 메모리 크기는 교수님이 지정하지 않고 참가자가 이유를 설명하라고 하신 항목입니다. 저희는 시나리오를 bin-picking과 표면 검사를 하는 로봇팔 손목 카메라로 정했습니다. 국소 영역을 회전하며 훑는 동작이라 회전만 있고 이동이 없다는 전제와 맞습니다. 자율주행은 이동이 지배적이라 이 전제가 깨져서 제외했습니다. 제안 크기는 패치 256 곱하기 256, 월드 1024 곱하기 1024, 회전각 1024단계입니다. 다만 RTL 검증은 이보다 작은 크기에서 했고, 이 부분은 뒤에서 한계로 다시 말씀드립니다.");
  table(s, [
    ["항목", "RTL로 검증한 크기", "로봇팔 목표(제안)", "근거"],
    ["센서 패치", "4×4", "256×256", "30~50 cm 근접 작업에서 부품 디테일 인식 필요"],
    ["월드 메모리", "1024×1024 (좌표 변환·추정기)\n64×64 (쓰기 경로+메모리 통합)", "1024×1024", "회전 180° 이내라 파노라마처럼 무한히 커지지 않음, 패치의 2~4배면 충분"],
    ["회전각 단계", "1024 (좌표 변환·추정기)\n256 (통합)", "1024", "약 0.18°/단계(180°/1024), 그립 정밀도"],
  ], 0.6, 1.6, 12.1, [1.7, 3.5, 1.9, 5.0], { size: 14, rowH: 0.78 });
  card(s, 0.6, 4.75, 5.9, 2.1, "왜 로봇팔인가", "회전만 하고 이동이 없다는 전제와 국소 스캔 동작이 일치한다. 센서 스펙(960×720, 6 mm 렌즈)도 3차 Q&A로 확정됐다.", { size: 16 });
  card(s, 6.8, 4.75, 5.9, 2.1, "제외한 시나리오", "자율주행: 이동이 지배적이라 전제가 깨짐\nPTZ·산업 스캐너: 해상도 확장이 가장 어려워 후순위", { size: 16, headColor: RED });
}

// ---------- 4. 전체 구조
{
  const s = content("구조: 1차 송신부 위에 좌표 변환과 월드 메모리를 얹었다",
    "전체 구조입니다. 1차에서 만든 AER 송신부가 사이클당 최대 8개 이벤트를 병렬로 뽑아냅니다. 그 이벤트마다 레인별 좌표 변환 회로가 세타를 이용해 월드 좌표를 계산하고, 월드 메모리 쓰기 모듈이 8개 레인의 경합을 하나의 쓰기 포트로 직렬화합니다. 메모리는 행 단위로 클록을 끄는 구조이고, 입력이 오래 없으면 코어 전체의 클록을 끄는 blink 기능을 넣었습니다. 회전각은 외부에서 주어지거나 아래쪽의 추정기가 공급합니다.");
  const bx = (x, y, w, h, t, sub, fill, tc) => {
    s.addShape(pres.ShapeType.roundRect, { x, y, w, h, fill: { color: fill }, line: { color: (fill === LIGHT || fill === WHITE || fill === PALE) ? HAIR : fill }, rectRadius: 0.12 });
    T(s, t, { x: x + 0.1, y: y + 0.12, w: w - 0.2, h: 0.5, fontSize: 15, bold: true, color: tc, align: "center", valign: "middle" });
    T(s, sub, { x: x + 0.1, y: y + 0.65, w: w - 0.2, h: h - 0.7, fontSize: 13, color: tc, align: "center" });
  };
  const y = 1.9, h = 1.9;
  bx(0.5, y, 1.9, h, "DVS 센서", "주소 + 극성\n(x, y, pol)", WHITE, INK);
  bx(2.85, y, 2.3, h, "AER 송신부 (1차)", "행 비트맵 + 훔치기 버퍼\n사이클당 최대 8 이벤트\nUZH 실측 손실 0.47%", WHITE, INK);
  bx(5.6, y, 2.3, h, "좌표 변환 ×8 레인", "RMCM: 4096가지\n표 하나로 대체\n곱셈기 없음", TEAL, WHITE);
  bx(8.35, y, 2.2, h, "월드 메모리 쓰기", "레인별 FIFO + 중재\n단일 쓰기 포트", WHITE, INK);
  bx(11.0, y, 1.85, h, "월드 메모리", "행 클록 게이팅\n읽기 포트", TEAL, WHITE);
  const arrow = (x1, x2) => s.addShape(pres.ShapeType.line, { x: x1, y: y + h / 2, w: x2 - x1, h: 0, line: { color: INK, width: 2, endArrowType: "triangle" } });
  arrow(2.4, 2.85); arrow(5.15, 5.6); arrow(7.9, 8.35); arrow(10.55, 11.0);
  bx(5.6, 4.35, 2.3, 1.5, "회전각 θ", "외부 공급 또는\n추정기(Bayes/CMax)", DARK, WHITE);
  s.addShape(pres.ShapeType.line, { x: 6.75, y: 3.8, w: 0, h: 0.55, flipV: true, line: { color: INK, width: 2, endArrowType: "triangle" } });
  s.addShape(pres.ShapeType.roundRect, { x: 8.35, y: 4.35, w: 4.5, h: 1.5, fill: { color: WHITE }, line: { color: TEAL, width: 1.5, dashType: "dash" }, rectRadius: 0.12 });
  T(s, "Blink: 입력이 없으면 코어 클록 차단", { x: 8.55, y: 4.5, w: 4.1, h: 0.4, fontSize: 15, bold: true, color: TEAL });
  T(s, "메모리는 자체 행 게이팅으로 항상 읽기 가능", { x: 8.55, y: 5.0, w: 4.1, h: 0.7, fontSize: 13, color: INK });
  T(s, "핵심 선택 3가지: ① 계산 대신 표 ② 쓰기 포트 하나로 직렬화 ③ 메모리를 지배적 비용으로 보고 클록을 끄는 구조", { x: 0.6, y: 6.15, w: 12.1, h: 0.7, fontSize: 15, bold: true, color: INK });
}

// ---------- 5. 좌표 변환 3종 비교
{
  const s = content("좌표 변환: 256각도에서는 계산 대신 표가 이겼다",
    "좌표 변환을 세 가지로 구현해 같은 조건에서 합성했습니다. 직접 행렬 곱, CORDIC, 그리고 RMCM입니다. CORDIC은 곱셈기를 없애니 더 작을 것이라 예상했지만 오히려 면적이 네 배 이상 커졌습니다. 우리 문제는 로컬 좌표가 4가지, 각도 후보가 256가지뿐이라 입력 공간 전체가 4096가지입니다. 그래서 전체를 표 하나로 만든 RMCM이 면적 2.5분의 1, 전력 4.8분의 1로 압승했고 근사 오차도 없습니다. 이 결론은 입력 공간이 좁을 때에 한정됩니다. 각도를 1024단계로 늘려 다시 합성했더니 표가 19071제곱마이크로미터, 직접 행렬곱이 5209제곱마이크로미터로 결과가 뒤집혔습니다.");
  s.addChart(pres.charts.BAR, [{ name: "면적", labels: ["직접 행렬곱", "CORDIC", "RMCM"], values: [3011, 12858, 1199] }], Object.assign({ x: 0.6, y: 1.5, w: 4.0, h: 3.9, barDir: "col" }, chartBase("면적 (µm²)", [MID, RED, TEAL]), { invertedColors: [MID], valAxisHidden: true }));
  s.addChart(pres.charts.BAR, [{ name: "전력", labels: ["직접 행렬곱", "CORDIC", "RMCM"], values: [0.200, 1.278, 0.041] }], Object.assign({ x: 4.7, y: 1.5, w: 4.0, h: 3.9, barDir: "col" }, chartBase("전력 (mW)", [MID, RED, TEAL]), { dataLabelFormatCode: "0.000", valAxisHidden: true }));
  table(s, [
    ["200 MHz 타이밍 여유", "슬랙"],
    ["직접 행렬곱", "+1 ps (턱걸이)"],
    ["CORDIC", "−252 ps (위반)"],
    [{ text: "RMCM", bold: true }, { text: "+2,187 ps", bold: true }],
  ], 8.95, 1.7, 3.75, [2.15, 1.6], { size: 13, rowH: 0.5 });
  T(s, "Genus 합성, 5 ns, GPDK045. 입력 4096가지(256각도) 기준, RMCM은 직접 행렬곱과 bit-exact. 1024각도에서는 RMCM 19,071 µm²·0.297 mW·+1,178 ps, 직접 행렬곱 5,209 µm²·0.279 mW·0 ps.", { x: 8.95, y: 3.95, w: 3.75, h: 1.4, fontSize: 13, color: MID });
  s.addShape(pres.ShapeType.roundRect, { x: 0.6, y: 5.65, w: 12.1, h: 1.15, fill: { color: DARK }, line: { color: DARK }, rectRadius: 0.12 });
  T(s, "곱셈기를 없애는 것이 항상 이득은 아니다. 256각도(입력 4,096가지)에서는 표가 이겼지만, 1024각도(16,384가지)에서는 표가 직접 행렬곱보다 3.7배 커서 결과가 뒤집혔다.", { x: 0.85, y: 5.75, w: 11.6, h: 0.95, fontSize: 16, bold: true, color: WHITE, valign: "middle" });
}

// ---------- 6. 검증
{
  const s = content("검증: 소프트웨어 기준값과 비트 단위로 모두 일치했다",
    "검증은 소프트웨어 모델을 기준값으로 두고 RTL이 한 비트도 다르지 않은지 확인하는 방식으로 했습니다. 좌표 변환은 가능한 입력 4096가지를 전부 돌렸고, 실제 UZH 이벤트 8503개와 무작위 스트레스 2만 사이클에서도 불일치가 0이었습니다. 검증 과정에서 실제로 버그를 세 번 찾았습니다. 두 번은 테스트벤치가 입력을 한 박자 어긋나게 넣은 문제였고, 한 번은 추정기 RTL에서 같은 사이클에 레지스터를 갱신하고 그 값으로 분기하던 진짜 RTL 버그였습니다. 이런 버그를 찾아내는 검증 구조 자체도 결과의 일부라고 생각합니다.");
  table(s, [
    ["검증 항목", "범위", "결과"],
    ["좌표 변환 전수 검사 (RMCM RTL)", "16 로컬 좌표 × 1024각도 = 16,384가지", { text: "16,384/16,384 일치", bold: true, options: { color: GREEN } }],
    ["실제 이벤트 재생 (UZH, 통합 회로)", "8,503개 이벤트 + 실제 자세", { text: "불일치 0, 손실 0, 90칸 기록", bold: true, options: { color: GREEN } }],
    ["무작위 스트레스", "20,000 사이클, 20% 도착률, 매 사이클 θ 변경", { text: "불일치 0 (20,241건), 528칸 기록", bold: true, options: { color: GREEN } }],
    ["θ 추정기 RTL vs 오라클", "UZH 이벤트 300개의 매 추정값 (1024각도, 외부 SRAM 포트 버전)", { text: "불일치 0", bold: true, options: { color: GREEN } }],
    ["blink vs 항상-켬 코어", "유휴 100~6000 사이클", { text: "overrun·메모리 이미지 불일치 0", bold: true, options: { color: GREEN } }],
    ["게이트 시뮬레이션 (P&R 후 netlist + signoff SDF)", "무작위 6,000사이클 + 메모리 4,096칸 읽기", { text: "RTL과 출력 10,097줄 일치", bold: true, options: { color: GREEN } }],
  ], 0.6, 1.5, 12.1, [4.3, 4.9, 2.9], { size: 13, rowH: 0.46 });
  card(s, 0.6, 5.35, 12.1, 1.55, "검증이 잡아낸 실제 버그", "① 등록형(registered) 파이프라인에서 θ가 한 박자 늦게 잡히는 것을 몰라 기대값이 어긋남 (테스트벤치, 2회)\n② 추정기 RTL: 같은 사이클에 레지스터를 갱신하고 그 값으로 분기해 갱신 전 값을 읽는 버그 → 최종값을 조합논리로 먼저 계산하도록 수정", { size: 13, headColor: AMBER });
}



// ---------- 7. 테스트벤치 파형: 좌표 변환 파이프라인
if (hasFig("wave_coord_pipeline.png")) {
  const s = content("테스트벤치 파형: 이벤트가 레인을 거쳐 월드 주소로 나온다",
    "실제 UZH 이벤트를 넣어 돌린 테스트벤치의 파형입니다. 위에서부터 클록, 16개 소스의 도착, 그 순간의 회전각, 그리고 월드 메모리 쓰기 포트의 쓰기 신호와 주소, 극성입니다. 도착한 이벤트가 몇 사이클 뒤에 월드 주소로 변환되어 하나씩 쓰기 포트로 나오는 것을 볼 수 있습니다. 이 파형은 RTL 시뮬레이션에서 그대로 덤프한 것입니다.");
  s.addImage({ path: fig("wave_coord_pipeline.png"), x: 0.6, y: 1.4, w: 8.7, h: 5.22 });
  card(s, 9.55, 1.55, 3.15, 5.05, "읽는 법", "• arrival: 16개 소스 중 어디서 이벤트가 왔는가(16비트 비트맵)\n• theta_idx: 그 순간의 회전각 번호\n• world_we · world_addr: 변환된 월드 좌표(y,x)가 쓰기 포트로 한 건씩 나옴\n• overrun은 0으로 유지", { size: 14 });
  T(s, "RTL 시뮬레이션(Icarus Verilog), 실제 UZH 이벤트 + 실제 자세", { x: 0.6, y: 6.68, w: 8.7, h: 0.3, fontSize: 12, color: MID });
}

// ---------- 8. 월드 메모리에 쌓인 결과
if (hasFig("worldmem_rtl.png")) {
  const s = content("RTL이 쓴 월드 메모리: 8,503개 이벤트가 90칸에 쌓였다",
    "같은 UZH 이벤트 8503개를 통합 회로에 재생한 뒤 월드 메모리에 기록된 내용을 그린 것입니다. 64 곱하기 64 메모리에서 90칸이 채워졌고 극성별로 색을 구분했습니다. 테스트벤치는 같은 이벤트에서 기대되는 주소와 극성을 독립적으로 계산해 쓰기 모듈 입력 8503건을 모두 대조했고 불일치는 0이었습니다. 또 무작위 스트레스 2만 사이클에서도 2만 241건의 쓰기가 모두 일치했습니다.");
  s.addImage({ path: fig("worldmem_rtl.png"), x: 0.6, y: 1.45, w: 5.2, h: 5.2 });
  card(s, 6.1, 1.55, 6.6, 2.3, "UZH 실제 이벤트 재생", "이벤트 8,503개 → 쓰기 8,503건, 손실(overrun) 0\n쓰기 모듈 입력 8,503건을 독립 계산한 기대값과 대조: 불일치 0\n기록된 칸 90/4096", { size: 15, headColor: GREEN });
  card(s, 6.1, 4.05, 6.6, 2.55, "무작위 스트레스", "20,000 사이클, 도착률 20%, 매 사이클 θ 변경\n쓰기 20,241건 모두 기대값과 일치, 손실 0\n기록된 칸 528/4096 (희소한 실제 트래픽이 놓치는 같은 사이클 충돌 경로를 자극)", { size: 15, headColor: GREEN });
}

// ---------- 7. 메모리가 지배한다
{
  const s = content("면적의 70%는 월드 메모리, 그래서 메모리를 먼저 다뤘다",
    "처음에는 월드 메모리를 레지스터 배열로 합성했는데, 쓰기 모듈 하나가 전체 면적의 98퍼센트를 차지했습니다. 저장소를 SRAM 인터페이스 바깥으로 빼서 면적을 6배 줄였지만, 이건 저장소를 따로 계산한다는 뜻이지 공짜가 아닙니다. 메모리를 포함한 배치배선 결과로 보면 메모리가 면적의 70퍼센트 이상이고, 비트당 약 12제곱마이크로미터입니다. 교수님이 SRAM도 평가에 포함된다고 하셨고 교육용 PDK에는 SRAM 매크로가 없으므로, 메모리 면적과 전력은 별도 추정 모델로 다뤄야 합니다. 그래서 이후 최적화는 전부 메모리 쪽에 집중했습니다.");
  s.addChart(pres.charts.BAR, [{ name: "면적", labels: ["메모리 제외", "메모리 포함 (FF 4096칸)"], values: [40259, 161599] }], Object.assign({ x: 0.6, y: 1.5, w: 5.4, h: 4.2, barDir: "col" }, chartBase("P&R 셀 면적 (µm²)", [MID, TEAL]), { valAxisHidden: true, dataLabelFormatCode: "#,##0" }));
  T(s, bullets([
    "쓰기 모듈 + 레지스터 배열 합성: 211,856 µm², 전체의 98%가 저장소",
    "저장소를 SRAM 인터페이스 밖으로 분리: 35,111 µm² (6.0배 감소). 단, 저장소는 별도 계산 대상",
    "메모리 포함 P&R: 메모리가 면적의 70% 이상, 약 12 µm²/비트",
    "교육용 PDK에는 SRAM 매크로가 없다 → 메모리는 별도 추정 모델이 필요",
  ], { gap: 10 }), { x: 6.3, y: 1.6, w: 6.4, h: 3.3, fontSize: 15 });
  s.addShape(pres.ShapeType.roundRect, { x: 6.3, y: 5.0, w: 6.4, h: 1.75, fill: { color: DARK }, line: { color: DARK }, rectRadius: 0.12 });
  T(s, ["→ 이후 최적화의 초점은", "코어 로직이 아니라", "메모리의 클록 동작에 맞췄다."].join("\n"), { x: 6.55, y: 5.1, w: 5.9, h: 1.55, fontSize: 16, bold: true, color: WHITE, valign: "middle" });
}

// ---------- 8. 행 클록 게이팅
{
  const s = content("행 단위 클록 게이팅으로 메모리 전력을 65% 줄였다",
    "기존 메모리는 합성 도구가 칸마다 enable 먹스로 만들어서, FF 8192개의 클록이 매 사이클 토글했고 레지스터 내부 전력이 전체의 77에서 90퍼센트였습니다. 행마다 클록 게이트를 두어 지금 쓰는 행 128개 FF만 클록을 받도록 바꿨습니다. 같은 실제 DELTA 이벤트로 측정한 활동도 전력이 2.52밀리와트에서 0.87밀리와트로 65퍼센트 줄었고 면적도 5퍼센트 줄었습니다. 오른쪽 파형이 실제 시뮬레이션에서 쓰는 행의 클록만 토글하는 모습입니다. 쓰기 캐시도 시험했는데 64항목에서만 소폭 이득이고 필수는 아니라서 채택하지 않았습니다.");
  const hasW = hasFig("wave_row_gating.png");
  s.addChart(pres.charts.BAR, [{ name: "전력", labels: ["기존", "기존 +C64", "기존 +C256", "행게이팅", "행게이팅 +C64", "행게이팅 +C256"], values: [2.522, 2.792, 1.666, 0.870, 0.730, 0.991] }], Object.assign({ x: 0.6, y: 1.5, w: hasW ? 6.4 : 7.6, h: 4.3, barDir: "col" }, chartBase("실제 DELTA 활동도 전력 (mW)", [MID, MID, MID, TEAL, TEAL, TEAL]), { dataLabelFormatCode: "0.00", valAxisHidden: true, catAxisLabelFontSize: 11 }));
  if (hasW) {
    s.addImage({ path: fig("wave_row_gating.png"), x: 7.2, y: 1.45, w: 5.5, h: 2.82 });
    T(s, "RTL 시뮬레이션 파형: 쓰는 행의 게이트 클록만 토글", { x: 7.2, y: 4.3, w: 5.5, h: 0.4, fontSize: 13, color: MID });
    card(s, 7.2, 4.8, 5.5, 1.3, "결과", "전력 2.522 → 0.870 mW (−65.5%)\n면적 90,105 → 85,617 µm² (−5.0%)", { size: 15, headColor: GREEN });
  } else {
    card(s, 8.5, 1.55, 4.2, 2.15, "원리", "행(y)마다 래치+AND 클록 게이트. 쓰는 행의 128개 FF만 클록을 받는다.", { size: 14 });
    card(s, 8.5, 3.9, 4.2, 1.9, "결과", "전력 2.522 → 0.870 mW (−65.5%)\n면적 90,105 → 85,617 µm² (−5.0%)", { size: 14, headColor: GREEN });
  }
  T(s, "C64·C256 = 쓰기 캐시 64·256항목. 원리: 행(y)마다 클록 게이트를 두어 쓰는 행의 128개 FF만 클록을 받는다(리셋 때만 전 행). 쓰기 캐시(64항목)는 전력 −16%, 면적 +5.5%로 이득이 작아 필수로 두지 않았다. 256항목은 오히려 전력이 늘었다.", { x: 0.6, y: 6.25, w: 12.1, h: 0.7, fontSize: 13, color: MID });
}

// ---------- 9. blink
{
  const s = content("Blink: 입력이 없는 동안 코어 클록을 꺼 유휴 전력을 줄였다",
    "실제 DELTA 프레임을 보면 이벤트는 프레임 안에서 몰려서 나오고 나머지 시간은 칩이 놉니다. 입력이 일정 사이클 없으면 코어 클록을 끄는 blink 기능을 넣었습니다. 파형에서 마지막 입력 뒤 일정 시간이 지나면 코어 클록이 멈추고 새 입력이 오면 다시 켜집니다. 항상 켜진 코어와 같은 입력을 넣어 출력과 메모리 이미지가 완전히 같음을 확인했습니다. 유휴가 긴 시험 입력에서 활동도 전력이 2.09밀리와트에서 0.61밀리와트로 71퍼센트 줄었습니다. 단, 이 71퍼센트는 유휴 시간이 긴 시험 입력의 값이고 실제 절감은 칩이 일하는 비율에 달려 있습니다. 실제 DELTA 기준으로 200메가헤르츠에서 칩이 일하는 비율은 가정에 따라 3퍼센트에서 25퍼센트입니다.");
  const hasW = hasFig("wave_blink.png");
  s.addChart(pres.charts.BAR, [{ name: "전력", labels: ["행 게이팅 (blink 없음)", "blink"], values: [2.09, 0.61] }], Object.assign({ x: 0.6, y: 1.5, w: 4.6, h: 4.0, barDir: "col" }, chartBase("유휴 6000사이클 VCD 전력 (mW)", [MID, TEAL]), { dataLabelFormatCode: "0.00", valAxisHidden: true }));
  if (hasW) {
    s.addImage({ path: fig("wave_blink.png"), x: 5.5, y: 1.45, w: 7.2, h: 2.52 });
    T(s, "RTL 시뮬레이션 파형: 입력이 끊기면(511사이클) 코어 클록 차단, 새 입력에 재가동", { x: 5.5, y: 4.0, w: 7.2, h: 0.4, fontSize: 13, color: MID });
    table(s, [
      ["200 MHz에서 칩이 일하는 비율 (실제 DELTA)", "비율"],
      ["입력 8개/사이클 버스트 가정 (하한)", "3.1% (p90 5.4%)"],
      ["쓰기 포트 1건/사이클 상한 가정", "25%"],
    ], 5.5, 4.45, 7.2, [4.9, 2.3], { size: 14, rowH: 0.46 });
  } else {
    table(s, [
      ["200 MHz에서 칩이 일하는 비율 (실제 DELTA)", "비율"],
      ["입력 8개/사이클 버스트 가정 (하한)", "3.1% (p90 5.4%)"],
      ["쓰기 포트 1건/사이클 상한 가정", "25%"],
      ["100 MHz, 상한 가정", "50%"],
    ], 5.7, 1.6, 7.0, [4.6, 2.4], { size: 13, rowH: 0.5 });
  }
  T(s, "주의: −71%는 유휴가 길도록 만든 시험 입력의 값이다. 실제 부하에서의 절감은 위 가동 비율에 비례하며, vectorless 전력에서는 두 구성이 같게 나온다(활동도를 모르면 코어가 계속 켜져 있다고 가정). blink top P&R(5.2 ns): DRC·antenna 0, setup +0.022 ns, hold −0.010 ns(181경로), 5.94 mW.", { x: 0.6, y: 6.05, w: 12.1, h: 0.85, fontSize: 13, color: RED });
}

// ---------- 10. 물리 검증
const PNR = JSON.parse(process.env.PNR_JSON || "{}");
{
  const s = content("물리 검증: 클록 게이팅 hold는 구조로 해결, 일반 경로에 ps 단위 잔여",
    "배치배선까지 완주해 Quantus 추출 기반 signoff 수준으로 재타이밍했습니다. 래치와 AND 게이트를 따로 둔 행 게이팅 설계는 DRC와 antenna는 0건이었지만 클록 게이팅 hold가 최악 마이너스 30피코초였습니다. 원인은 클록 트리 합성이 래치를 말단 싱크로 보고 균형을 맞추면서 래치가 AND 게이트보다 0.2나노초 일찍 열린 것이었습니다. 라이브러리의 통합 클록 게이트 셀로 바꾸자 클록 게이팅 hold 위반은 0건이 됐습니다. 다만 5나노초에서 일반 레지스터 경로에 hold 마이너스 7피코초, setup 마이너스 19피코초 위반이 남았고, signoff 단계 ECO로는 setup이 오히려 나빠져 채택하지 않았습니다. 클록을 5.2나노초로 늦춘 결과는 오른쪽 열에 적었습니다.");
  table(s, [
    ["항목 (signoff)", "래치+AND 분리", "통합 ICG", PNR.col52Head || "통합 ICG @5.2 ns"],
    ["DRC / antenna", "0 / 0", "0 / 0", PNR.drc52 || "(진행 중)"],
    ["클록 게이팅 hold", "−0.030 ns (13)", "+0.080 ns (0)", PNR.cg52 || "(진행 중)"],
    ["reg2reg hold", "−0.010 ns (135)", "−0.007 ns (34)", PNR.hold52 || "(진행 중)"],
    ["setup", "위반 0", "−0.019 ns (1)", PNR.setup52 || "(진행 중)"],
    ["전력 (vectorless)", "5.89 mW", "6.11 mW", PNR.power52 || "(진행 중)"],
    ["표준셀 면적", "159,459 µm²", "162,312 µm²", PNR.area52 || "(진행 중)"],
  ], 0.6, 1.5, 8.0, [2.2, 1.8, 1.9, 2.1], { size: 12, rowH: 0.5 });
  T(s, "괄호 안은 위반 경로 수. 5 ns, util 0.6, GPDK045, Quantus 추출.", { x: 0.6, y: 5.05, w: 8.0, h: 0.3, fontSize: 11, color: MID });
  if (hasFig("pnr_layout.png")) {
    s.addImage({ path: fig("pnr_layout.png"), x: 8.85, y: 1.45, w: 3.9, h: 3.51 });
    T(s, "P&R 셀 배치도 (플립플롭 = 연회색, 클록 게이트 = 파랑)", { x: 8.85, y: 5.0, w: 3.9, h: 0.5, fontSize: 11, color: MID });
  }
  card(s, 0.6, 5.45, 3.9, 1.5, "원인", "CTS가 래치를 말단 싱크로 균형 맞춰 AND 게이트보다 약 0.2 ns 일찍 열림", { size: 13, headColor: RED });
  card(s, 4.65, 5.45, 3.95, 1.5, "수정과 시도", "래치+AND → 통합 클록게이트 셀로 hold 해결. ECO·hold 목표 강화는 setup이 깨져(−0.04~−1.17 ns) 미채택", { size: 13, headColor: GREEN });
  card(s, 8.85, 5.55, 3.85, 1.4, "남은 것", "일반 경로 ps 단위 잔여 위반. 클록 여유로 흡수하는 것이 현재 해법", { size: 13, headColor: AMBER });
}

// ---------- 11. θ 추정
{
  const s = content("회전각은 인과적으로만 추정한다: 미래가 필요한 방법은 버렸다",
    "회전각을 외부에서 받는 것이 1단계이고, 2단계는 이 각도를 이벤트에서 직접 추정하는 것입니다. 여러 방법을 비교하다가 중요한 사실을 발견했습니다. 평활화와 일괄 최적화는 정확도가 좋지만 미래 이벤트가 있어야 계산됩니다. 로봇팔은 지금 이 순간의 각도가 필요한 스트리밍 문제라 이 방법들은 실시간으로 쓸 수 없습니다. 그래서 유한 지연만 허용하는 방식을 택했고, 지연 8윈도우만으로 평균 이득의 대부분이 회복됩니다. 오른쪽 아래 그래프는 실제 DELTA 영상에서 장면 속 직선 방향으로 만든 회전각 정답과 우리 추정을 비교한 것으로, 대부분 구간에서 몇 도 안쪽으로 따라갑니다. 다만 정확도는 데이터에 따라 크게 달라서 한계를 따로 적었습니다.");
  table(s, [
    ["방법", "실시간 가능", "UZH 20곳 평균 / 최악 오차"],
    ["Contrast maximization (순수 인과)", { text: "가능", options: { color: GREEN, bold: true } }, "11.7° / 59.4°"],
    ["+ forward-backward 평활", { text: "불가 (미래 필요)", options: { color: RED, bold: true } }, "10.2° / 44.3°"],
    ["batch bundle adjustment", { text: "불가 (미래 필요)", options: { color: RED, bold: true } }, "11.5° / 28.7°"],
    ["bounded-lag (L=8 윈도우, 128 이벤트 FIFO)", { text: "가능 (지연 L)", options: { color: GREEN, bold: true } }, "10.6° / 50.3°"],
  ], 0.6, 1.5, 12.1, [5.6, 2.5, 4.0], { size: 14, rowH: 0.46 });
  s.addImage({ path: img("gt_orientation_vs_ours.png"), x: 0.6, y: 4.0, w: 6.7, h: 2.52 });
  T(s, "실제 DELTA 영상: 장면 속 직선 방향으로 만든 회전각 정답(파랑) vs 우리 추정(주황), 오른쪽은 오차(°)", { x: 0.6, y: 6.55, w: 6.7, h: 0.4, fontSize: 11, color: MID });
  card(s, 7.55, 4.0, 5.15, 1.45, "추정기 RTL (Bayes filter)", "이산 베이즈 필터를 고정소수점으로 구현. UZH 이벤트 300개 재생에서 오라클과 비트 단위로 일치(1024각도 버전).", { size: 13 });
  card(s, 7.55, 5.55, 5.15, 1.4, "정직한 한계", "정확도는 장면에 크게 의존한다. 로봇팔 실측(RobotEvt)에서는 UZH용 파라미터 그대로 평균 35.2° / 최악 91.8°.", { size: 13, headColor: RED });
}

// ---------- 12. 실제 월드맵 결과
{
  const s = content("실제 센서 영상으로 만든 월드 지도: 방 구조가 복원된다",
    "이 그림들은 실제 DELTA 센서가 찍은 영상으로 소프트웨어 모델이 만든 월드 지도입니다. 왼쪽은 이벤트를 회전만 보정해 쌓은 첫 결과이고 가운데 둘은 보정을 정교하게 한 최종 결과입니다. 맨 오른쪽은 같은 시점의 실제 프레임입니다. 아래는 모션캡처 정답이 있는 UZH 데이터입니다. 정답 자세로 만든 지도는 정답 자세의 시간 어긋남 때문에 번져 있어 공정한 비교는 아니지만, 우리 추정으로 쌓은 지도에서도 도형이 선명하게 복원됩니다. 정답이 없는 실제 영상은 육안과 간접 지표뿐이라는 점은 분명히 말씀드립니다.");
  s.addImage({ path: img("FINAL_comparison.png"), x: 0.6, y: 1.45, w: 9.6, h: 2.4 });
  T(s, "실제 DELTA 영상(960×720) 월드 지도: 첫 결과 · 최종(균형형) · 최종(정제형) · 같은 시점의 실제 프레임(각도 보정 후)", { x: 0.6, y: 3.9, w: 9.6, h: 0.5, fontSize: 12, color: MID });
  card(s, 10.4, 1.45, 2.3, 2.95, "정직한 평가", "정답이 없는 실제 영상은 육안과 간접 지표로만 평가", { size: 13, headColor: RED });
  s.addImage({ path: img("UZH_worldmap.png"), x: 0.6, y: 4.5, w: 6.0, h: 2.45 });
  T(s, bullets([
    "UZH(모션캡처 정답): 좌 = 정답 자세 맵(시간 어긋남 보정 전이라 번짐), 우 = 우리 ECC 추정 맵",
    "소프트웨어(ECC) 추정기: 광축 1초 구간 θ 오차 2.4~3.2° (정답 시간 보정 후)",
  ], { gap: 6 }), { x: 7.2, y: 4.6, w: 5.5, h: 2.4, fontSize: 14 });
}

// ---------- 12b. 갤러리
{
  const s = content("다른 영상과 합성 정답에서도 같은 파이프라인이 동작한다",
    "같은 파이프라인을 다른 영상에도 적용했습니다. 위는 실제 팬 동작 영상으로 만든 파노라마 월드 지도입니다. 왼쪽 아래는 실제 롤 영상에서 깊이 층을 이용해 만든 상대 3차원 점구름이고, 오른쪽 아래는 정답을 아는 합성 장면에서 파이프라인이 어디까지 복원하는지 본 결과입니다. 합성 결과는 우리 모델이 정확히 맞는 세계에서의 값이라는 한계가 있습니다.");
  s.addImage({ path: img("PAN_FINAL_worldmap.png"), x: 0.6, y: 1.4, w: 12.1, h: 3.47 });
  T(s, "실제 팬(pan) 영상으로 만든 월드 지도 (한 번에 파노라마로 쌓임)", { x: 0.6, y: 4.88, w: 12.1, h: 0.3, fontSize: 12, color: MID });
  s.addImage({ path: img("ROLL_3D_real_views.png"), x: 0.6, y: 5.2, w: 4.0, h: 1.64 });
  T(s, "실제 롤 영상의 상대 3D 점구름", { x: 0.6, y: 6.86, w: 4.0, h: 0.25, fontSize: 11, color: MID });
  s.addImage({ path: img("synthetic_validation.png"), x: 4.9, y: 5.2, w: 4.5, h: 1.63 });
  T(s, "합성 정답 장면 대비 복원 결과", { x: 4.9, y: 6.86, w: 4.5, h: 0.25, fontSize: 11, color: MID });
  card(s, 9.7, 5.2, 3.0, 1.75, "주의", "합성 점수는 모델이 정확히 맞는 세계의 값, 실제 영상엔 정답 없음", { size: 12, headColor: RED });
}

// ---------- 13. 시차
{
  const s = content("남은 문제: 회전 중심이 어긋나 가까운 물체는 번진다",
    "실제 영상에서 가까운 물체가 번지는 것을 발견했고 원인을 추적했습니다. 센서가 자기 중심으로 도는 것이 아니라 봉 끝에 매달려 피벗을 중심으로 원호를 그립니다. 그래서 깊이마다 회전 중심이 다르게 어긋납니다. 3차 Q&A에서 이 셋업이 실제 봉과 피벗 구조임이 확인되어, 저희 좌표 변환 모델의 원호 구조가 물리적으로 맞다는 근거도 됐습니다. 깊이 층별로 지도를 만들어 선명한 층을 고르면 번짐이 크게 줄지만, 이 부분은 소프트웨어 단계이고 아직 RTL에 넣지 않았습니다.");
  s.addImage({ path: img("worldmap_depth_stack.png"), x: 0.6, y: 1.5, w: 12.1, h: 4.03 });
  T(s, "회전 중심 하나로 쌓은 지도(좌) → 깊이 층별 지도에서 선명한 층 선택(중) → 추정된 상대 깊이(우)", { x: 0.6, y: 5.6, w: 12.1, h: 0.35, fontSize: 12, color: MID });
  card(s, 0.6, 6.0, 12.1, 0.9, "한계", "깊이 층 선택은 소프트웨어 모델이다. RTL에는 회전만 반영했고, 시차 보정은 향후 과제로 남겼다.", { size: 13, headColor: RED });
}

// ---------- 14. 생체 모방
{
  const s = content("생체 모방은 실제 데이터로 이긴 것만 남겼다",
    "생체 모방 아이디어를 여러 개 시도했지만, 합성 장면에서만 이득이 나온 것은 실제 프레임으로 확인해 기각했습니다. 눈 깜빡임을 본뜬 유휴 클록 차단과, 메모리 행 단위 클록 게이팅은 실제 데이터로 이득이 확인되어 채택했습니다. 반대로 이득 조절은 합성 장면에서는 좋아 보였지만 실제 DELTA 프레임에서는 이득이 없어서 정정했습니다. 습관화, 도약성 억제, 미세 안구운동, 추정기 입력 줄이기도 사전에 정한 기준을 넘지 못해 기각했습니다. 무엇을 안 했는지도 설계의 일부라고 생각합니다.");
  table(s, [
    ["생체 모방 아이디어", "결과", "근거"],
    ["중심와(fovea) / 이벤트 클러스터링 (1차)", { text: "채택", options: { color: GREEN, bold: true } }, "열 비트맵: 손실 57.6% → 6.9%(동일 합성 트래픽), 최종 결합판 0.47%(UZH 실측)"],
    ["눈 깜빡임: 유휴 시 코어 클록 차단", { text: "채택", options: { color: GREEN, bold: true } }, "항상-켬과 출력·메모리 일치, 유휴 전력 −71%(시험 입력)"],
    ["행 단위 선택적 활성화 (메모리)", { text: "채택", options: { color: GREEN, bold: true } }, "전력 −65.5%, 면적 −5%"],
    ["이득 조절(과부하 솎아내기)", { text: "기각·정정", options: { color: RED, bold: true } }, "합성 장면에서만 이득, 실제 DELTA 프레임에서 이득 없음"],
    ["추정기 입력 줄이기(ON만/중심 가중/불응기)", { text: "기각", options: { color: RED, bold: true } }, "정확도 1.5배 이상 악화"],
    ["미세 안구운동(지터)", { text: "기각", options: { color: RED, bold: true } }, "부화소 복원 효과 없음"],
    ["원심성 복사(VOR): 회전 지령을 θ 사전분포로", { text: "기각", options: { color: INK, bold: true } }, "UZH 평균 23.4°→8.5°이나 RobotEvt 36.1°→34.9°(기준 25.3° 미달), 사전 등록 기준 미통과"],
    ["희소 행 할당(해마식 지연 할당)", { text: "기각", options: { color: INK, bold: true } }, "건드려진 행 UZH 52.9%·RobotEvt 55.5%(기준 50% 이하 미달), 칸은 13~17%"],
    ["기억 소멸(forgetting)", { text: "기각", options: { color: INK, bold: true } }, "카운터 감쇠(K=4096): UZH 23.4°→23.8°, RobotEvt 36.1°→36.0°(0.8배 기준 미달)"],
    ["최근 쓰기 캐시 (감각 기억)", { text: "보류", options: { color: MID, bold: true } }, "64항목만 전력 −16%/면적 +5.5%, 필수 아님"],
  ], 0.6, 1.5, 12.1, [4.4, 1.3, 6.4], { size: 12, rowH: 0.46 });
}

// ---------- 15. 장단점·고려
{
  const s = content("장단점과 고려 사항: 확장 시 가장 큰 비용은 메모리",
    "장점은 좌표 변환이 곱셈기 없이 표 하나로 끝나고 bit-exact로 검증됐다는 것, 메모리와 유휴 전력을 구조적으로 줄였다는 것, 실제 데이터로 검증하고 기각한 것까지 정리했다는 것입니다. 단점과 고려 사항도 분명합니다. RTL은 4 곱하기 4 패치와 64 곱하기 64 월드에서 검증했고, 1024 곱하기 1024로 확장하면 메모리가 지배적이 됩니다. 이 크기를 지금의 FF로 만들면 대략 25제곱밀리미터라서 반드시 SRAM 매크로가 필요하고, 교육용 PDK에는 없으므로 별도 모델이 필요합니다. 회전각 추정은 장면에 따라 편차가 크고, 시차 보정은 아직 RTL에 반영하지 못했습니다.");
  card(s, 0.6, 1.55, 5.9, 2.65, "장점", "• 곱셈기 없는 표 기반 좌표 변환, bit-exact 검증\n• 메모리 클록 게이팅(−65.5%)과 blink로 구조적 전력 절감\n• 실제 센서·로봇팔 데이터로 검증, 안 되는 것은 기각\n• 3차 Q&A로 확인된 물리 셋업(봉-피벗)과 모델이 일치", { size: 15, headColor: GREEN });
  card(s, 6.8, 1.55, 5.9, 2.65, "단점·한계", "• 통합 회로의 합성·P&R은 4×4 패치, 64×64 월드, 256각도 (좌표 변환·추정기만 1024×1024로 검증)\n• 회전각 추정 정확도가 장면에 크게 의존\n• 시차(깊이) 보정은 소프트웨어만, RTL 미반영\n• 정답 없는 실제 영상은 간접 지표로만 평가", { size: 14, headColor: RED });
  card(s, 0.6, 4.4, 12.1, 2.45, "고려 사항: 목표 크기(1024×1024)로 확장할 때", "• 1024×1024 × 2비트 = 약 2.1 Mbit. 지금의 FF 메모리 비용(약 12 µm²/비트)로는 약 25 mm² → SRAM 매크로가 필수 (제안 크기 기준 단순 계산, 합성 결과 아님)\n• 교육용 PDK(GPDK045)에는 SRAM 컴파일러가 없어, 메모리 면적·전력은 별도 모델로 추정해야 함\n• 1024각도 목표 크기에서는 좌표 변환 표(RMCM) 19,071 µm²가 직접 행렬곱 5,209 µm²보다 3.7배 커서 직접 행렬곱이 맞음(단, 슬랙 0 ps로 여유 없음)" + String.fromCharCode(10) + "• 쓰기 경로(FIFO·중재·좌표 변환)는 레인 수에 비례해 늘어나지만 메모리에 비하면 작다", { size: 14, headColor: AMBER });
}

// ---------- 16. 요약
{
  const s = pres.addSlide({ masterName: "DARK" });
  n++;
  T(s, "요약과 앞으로", { x: 0.8, y: 0.6, w: 11.7, h: 0.8, fontSize: 34, bold: true, color: WHITE });
  const col = (x, head, body, c) => {
    T(s, head, { x, y: 1.8, w: 3.7, h: 0.5, fontSize: 18, bold: true, color: BLUE_D });
    T(s, body, { x, y: 2.4, w: 3.7, h: 3.6, fontSize: 17, color: WHITE });
  };
  col(0.8, "한 일", bullets(["회전각으로 이벤트를 월드 좌표로 옮기는 회로를 RTL로 구현", "표 기반 좌표 변환 (256각도에서 면적 2.5배↓, 전력 4.8배↓)", "단일 쓰기 포트, 행 클록 게이팅, blink"], { gap: 8 }), AMBER);
  col(4.9, "확인한 것", bullets(["소프트웨어 모델과 비트 단위 일치", "메모리 전력 −65.5%", "P&R: DRC·antenna 0건, 클록 게이팅 hold는 ICG로 해결"], { gap: 8 }), AMBER);
  col(9.0, "남은 것", bullets(["1024×1024로의 확장과 SRAM 모델링", "시차 보정의 RTL 반영", "실제 영상에서 θ 정확도 개선"], { gap: 8 }), AMBER);
  T(s, "주소 자체가 이벤트다 — 필요한 것만 옮기고, 쉬는 동안은 끈다.", { x: 0.8, y: 6.2, w: 11.7, h: 0.6, fontSize: 18, bold: true, color: MUTED_D });
  s.addNotes("정리하겠습니다. 저희는 회전각으로 이벤트를 월드 좌표로 옮기는 회로를 RTL로 만들고, 표 기반 좌표 변환과 메모리 행 게이팅, blink로 면적과 전력을 줄였습니다. 소프트웨어 모델과 비트 단위로 일치함을 확인했고, 배치배선에서도 DRC와 antenna 위반이 없습니다. 남은 과제는 목표 크기로의 확장과 SRAM 모델링, 시차 보정의 RTL 반영, 실제 영상에서의 각도 추정 정확도입니다. 들어주셔서 감사합니다.");
}

pres.writeFile({ fileName: OUT }).then(() => console.log("wrote", OUT, "slides", n));
