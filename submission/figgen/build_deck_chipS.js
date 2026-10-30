// 2차 결과 발표자료(칩 S 중심) 생성 스크립트. 사용: node build_deck_chipS.js <출력.pptx> <이미지폴더(results_delta)> <그림폴더(submission/figs)>
// 서식은 REDRED_2차_발표자료.pptx(build_deck.js)와 동일: Apple 스타일 팔레트, 흰색/parchment/근흑 교대, hairline 카드, 나눔스퀘어 네오(post.py가 가족명 변환).
const pptxgen = require("pptxgenjs");
const path = require("path");
const fs = require("fs");
const OUT = process.argv[2];
const IMG = process.argv[3];
const FIG = process.argv[4];
const img = (f) => path.join(IMG, f);
const fig = (f) => path.join(FIG, f);
const hasFig = (f) => fs.existsSync(fig(f));

const INK = "1D1D1F", TEAL = "0066CC", LIGHT = "F5F5F7", MID = "7A7A7A", RED = "1D1D1F", GREEN = "0066CC", WHITE = "FFFFFF";
const BLUE_D = "2997FF", DARK = "272729", HAIR = "E0E0E0", MUTED_D = "CCCCCC";
const FONT = "나눔스퀘어 네오 Regular";

const pres = new pptxgen();
pres.layout = "LAYOUT_WIDE"; // 13.33 x 7.5
pres.title = "회전 이벤트 카메라 월드 좌표 변환·월드 메모리 칩 (2차 결과)";
pres.author = "REDRED";
pres.theme = { headFontFace: FONT, bodyFontFace: FONT };

["CONTENT", "PARCH"].forEach((nm) => pres.defineSlideMaster({
  title: nm, background: { color: nm === "CONTENT" ? WHITE : LIGHT },
  objects: [{ text: { text: "팀 REDRED · Digital 2차", options: { x: 0.6, y: 7.08, w: 5, h: 0.3, fontFace: FONT, fontSize: 10, color: MID, margin: 0 } } }],
  slideNumber: { x: 12.2, y: 7.08, w: 0.6, h: 0.3, fontFace: FONT, fontSize: 10, color: MID, align: "right" },
  margin: [0.5, 0.6, 0.5, 0.6],
}));
pres.defineSlideMaster({ title: "DARK", background: { color: DARK } });

let n = 0;
function content(title, notes) {
  const s = pres.addSlide({ masterName: n % 2 ? "PARCH" : "CONTENT" });
  s.addText(title, { x: 0.6, y: 0.35, w: 12.1, h: 0.95, fontFace: FONT, fontSize: 26, bold: true, color: INK, valign: "middle", margin: 0, isTextBox: true, fit: "shrink" });
  const TAGS = [["문제 정의", "목표"], ["교수님 센서", "목표 · 입력"], ["전체 구조", "달성 방법"], ["풀칩 배치배선", "결과"], ["검증", "결과"], ["정확도", "결과"], ["칩 S가 만든", "결과"], ["월드 지도 모음", "결과"], ["과적합 해결", "결과"], ["좌표 변환", "기술 내용"], ["월드 메모리", "기술 내용"], ["자세 추정기", "기술 내용"], ["시행착오", "시행착오"], ["용어 풀이", "부록"], ["장단점", "장단점 · 고려 사항"]];
  const tg = TAGS.find((t) => title.startsWith(t[0]));
  if (tg) s.addText(tg[1], { x: 9.9, y: 0.12, w: 2.8, h: 0.3, fontFace: FONT, fontSize: 11, bold: true, color: TEAL, align: "right", margin: 0, isTextBox: true });
  if (notes) s.addNotes(notes);
  n++;
  return s;
}
const T = (s, text, o) => s.addText(text, Object.assign({ fontFace: FONT, color: INK, fontSize: 15, margin: 0, isTextBox: true, valign: "top" }, o));
function card(s, x, y, w, h, head, body, o = {}) {
  s.addShape(pres.ShapeType.roundRect, { x, y, w, h, fill: { color: o.fill || WHITE }, line: { color: HAIR, width: 0.75 }, rectRadius: 0.12 });
  T(s, head, { x: x + 0.2, y: y + 0.15, w: w - 0.4, h: 0.4, fontSize: 16, bold: true, color: o.headColor || TEAL });
  T(s, body, { x: x + 0.2, y: y + 0.6, w: w - 0.4, h: Math.max(h - 0.75, 0.3), fontSize: o.size || 14, color: INK });
}
function bullets(items, o = {}) {
  return items.map((t, i) => ({ text: t, options: { bullet: true, breakLine: i < items.length - 1, paraSpaceAfter: o.gap === undefined ? 6 : o.gap } }));
}
function table(s, rows, x, y, w, colW, o = {}) {
  const body = rows.map((r, ri) => r.map((c) => {
    const isH = ri === 0;
    const cell = typeof c === "object" ? c : { text: String(c) };
    return { text: cell.text, options: Object.assign({ fontFace: FONT, fontSize: o.size || 13, color: INK, bold: isH || !!cell.bold, fill: { color: isH ? LIGHT : WHITE }, valign: "middle", margin: [0.04, 0.08, 0.04, 0.08], border: [{ type: "solid", pt: 0.5, color: HAIR }, { type: "solid", pt: 0.5, color: HAIR }, { type: "solid", pt: 0.5, color: HAIR }, { type: "solid", pt: 0.5, color: HAIR }] }, cell.options || {}) };
  }));
  s.addTable(body, { x, y, w, colW, rowH: o.rowH || 0.42, autoPage: false });
}
function bx(s, x, y, w, h, head, sub, o = {}) {
  s.addShape(pres.ShapeType.roundRect, { x, y, w, h, fill: { color: o.fill || WHITE }, line: { color: o.line || HAIR, width: 1 }, rectRadius: 0.1 });
  T(s, head, { x: x + 0.08, y: y + 0.08, w: w - 0.16, h: 0.4, fontSize: o.hs || 13, bold: true, color: o.color || TEAL, align: "center" });
  if (sub) T(s, sub, { x: x + 0.08, y: y + 0.5, w: w - 0.16, h: h - 0.55, fontSize: o.ss || 11, color: o.scolor || INK, align: "center" });
}
const arrow = (s, x1, y1, x2, y2) => s.addShape(pres.ShapeType.line, { x: x1, y: y1, w: x2 - x1, h: y2 - y1, line: { color: MID, width: 1.5, endArrowType: "triangle" } });
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
  T(s, "회전하는 이벤트 카메라를\n하나의 월드 지도로 옮기는 칩", { x: 0.8, y: 1.9, w: 11.7, h: 2.2, fontSize: 40, bold: true, color: WHITE, valign: "top" });
  T(s, "교수 센서 데이터를 직접 해독해 만든 풀칩 (RTL → P&R → signoff) 과 그 시행착오", { x: 0.8, y: 4.3, w: 11.7, h: 0.5, fontSize: 18, color: BLUE_D });
  T(s, "팀 REDRED", { x: 0.8, y: 6.3, w: 11.7, h: 0.4, fontSize: 16, color: MUTED_D });
  s.addNotes("안녕하세요, 팀 REDRED입니다. 저희는 회전하는 이벤트 카메라가 내보내는 이벤트를 하나의 월드 지도에 쌓는 칩을 만들었습니다. 교수님 센서의 원본 데이터 형식을 직접 해독해서 칩 입력으로 쓰고, 설계부터 배치배선과 검증까지 끝낸 풀칩입니다. 이 발표에서는 결과뿐 아니라 안 된 것과 고친 과정, 그리고 아직 남은 한계도 숨기지 않고 말씀드리겠습니다.");
  n++;
}

// ---------- 2'. 핵심 특장점 (신규, 맨 앞)
{
  const s = pres.addSlide({ masterName: "DARK" });
  T(s, "핵심 특장점", { x: 0.7, y: 0.4, w: 9, h: 0.8, fontSize: 32, bold: true, color: WHITE });
  T(s, "숫자는 모두 이 발표에서 근거를 보여 드립니다 (괄호는 해당 쪽)", { x: 0.7, y: 1.1, w: 11.5, h: 0.4, fontSize: 14, color: MUTED_D });
  const tiles = [
    ["불일치 0", "RTL = 기준모델", "roll·pan·UZH와 종단 시뮬 전부 비트 일치, LEC 14,618점 통과 (7쪽)"],
    ["+2.4 ns", "8.0 ns 풀칩 signoff 통과", "setup 여유 2.4 ns, DRC는 전원선 10건뿐, 게이트 시뮬 bit-exact (6쪽)"],
    ["0.47°", "실제 roll 영상 각도 오차", "교수 센서 323° 회전 녹화, ECC 정답 대비 평균 (8쪽)"],
    ["61° → 0.67°", "과적합 해결 알고리즘 (검증 완료)", "녹화별 상수가 사실 피벗 하나 → 데이터에서 구함. 합성 정답에서 독립 검증, 칩은 상수를 레지스터로 받음 (11쪽)"],
    ["원본 직접", "교수 센서 데이터를 해독해 입력", "Samsung group AER 워드를 디코더가 그대로 받음, 실측 프레임 773 µs (4쪽)"],
    ["60개 → 선별", "후보를 측정으로 걸러냄", "탈락 사유와 시행착오 4쪽(생체 모방 포함)을 숨김없이 수록 (15~18쪽)"],
  ];
  tiles.forEach((t, i) => {
    const x = 0.7 + (i % 3) * 4.1, y = 1.75 + Math.floor(i / 3) * 2.35;
    s.addShape(pres.ShapeType.roundRect, { x, y, w: 3.9, h: 2.15, fill: { color: "343437" }, line: { color: "4A4A4D", width: 0.75 }, rectRadius: 0.12 });
    T(s, t[0], { x: x + 0.2, y: y + 0.18, w: 3.5, h: 0.8, fontSize: 36, bold: true, color: BLUE_D, valign: "middle" });
    T(s, t[1], { x: x + 0.2, y: y + 1.0, w: 3.5, h: 0.4, fontSize: 16, bold: true, color: WHITE });
    T(s, t[2], { x: x + 0.2, y: y + 1.42, w: 3.5, h: 0.7, fontSize: 12, color: MUTED_D });
  });
  T(s, "정직한 한계", { x: 0.7, y: 6.55, w: 1.6, h: 0.4, fontSize: 14, bold: true, color: "FFB74D" });
  T(s, "출하 클록은 8 ns · 전력은 활동도 입력 없는 값 (18쪽에서 보강)", { x: 2.3, y: 6.55, w: 10.4, h: 0.5, fontSize: 13, color: WHITE });
  s.addNotes("이 발표의 핵심 특장점 여섯 가지를 먼저 말씀드립니다. 첫째, 설계한 RTL이 기준모델과 한 비트도 다르지 않습니다. 변환과 쓰기 경로, 추정기, 종단 시뮬레이션이 모두 불일치 0이고 논리 동등성 검사도 통과했습니다. 둘째, 풀칩을 8나노초에서 배치배선하고 signoff 타이밍 여유 2.4나노초로 통과했습니다. 셋째, 교수님의 실제 roll 영상에서 각도 오차가 평균 0.47도입니다. 넷째, 칩에 녹화에 맞춘 상수가 있었는데 그게 사실 피벗 하나였고, 데이터에서 구하는 해결 알고리즘으로 61도 붕괴가 0.67도로 줄어드는 것을 정답 있는 합성 장면에서 독립적으로 확인했습니다. 칩은 이 상수를 설정 레지스터로 받는 구조입니다. 다섯째, 교수님 센서의 원본 데이터를 직접 해독해서 칩이 그대로 받습니다. 여섯째, 후보 약 60개를 측정으로 걸러냈고 안 된 것과 고친 과정도 다섯 쪽에 걸쳐 모두 적었습니다. 그리고 한계도 있습니다. 출하 클록은 8나노초이고, 전력은 활동도 입력이 없는 값입니다.");
  n++;
}

// ---------- 2. 문제 정의
{
  const s = content("문제 정의와 목표: 센서가 돌아도 지도는 제자리에 있어야 한다",
    "이벤트 카메라는 밝기가 변한 픽셀의 주소와 극성만 내보냅니다. 카메라가 회전하면 같은 물체가 센서의 다른 픽셀에서 발화하므로, 이벤트를 그대로 쌓으면 왼쪽처럼 소용돌이로 번집니다. 회전각으로 좌표를 되돌려 쌓으면 오른쪽처럼 방의 구조가 보입니다. 그래서 칩이 해야 할 일은 두 가지입니다. 회전각을 구하고, 그 각도로 이벤트마다 월드 좌표를 계산해 월드 메모리에 쓰는 것입니다. 제약은 교수님 Q&A로 확정됐습니다. 회전은 180도 이내이고 평행 이동은 없습니다.");
  card(s, 0.6, 1.55, 3.9, 1.95, "목표", "교수 센서 원본 이벤트를 받아\n회전을 보정한 월드 맵을\n칩 한 개로 만든다 (960×720)", { size: 15 });
  card(s, 4.72, 1.55, 3.9, 1.95, "제약 (교수 Q&A 확정)", "회전 180° 이내\n평행 이동 없음\n표면만 보는 2차원 월드", { size: 15 });
  card(s, 8.84, 1.55, 3.9, 1.95, "달성 방법 (요약, 5쪽)", "① 회전각을 이벤트에서 추정\n② 이벤트마다 월드 좌표 계산\n③ 월드 메모리에 쓰기", { size: 15 });
  s.addImage({ path: fig("hs_A1_roll.png"), x: 0.6, y: 3.6, w: 7.1, h: 3.48 });
  s.addShape(pres.ShapeType.roundRect, { x: 8.0, y: 3.7, w: 4.74, h: 3.2, fill: { color: DARK }, line: { color: DARK }, rectRadius: 0.12 });
  T(s, "목표 지표", { x: 8.25, y: 3.9, w: 4.3, h: 0.4, fontSize: 17, bold: true, color: BLUE_D });
  T(s, bullets(["실제 센서 데이터에서 동작하는가 (8쪽)", "RTL이 기준모델과 비트 단위로 같은가 (7쪽)", "배치배선·signoff까지 닫혔는가 (6쪽)", "녹화별 과적합 없이 일반화하는가 (11쪽)", "한계를 스스로 설명할 수 있는가 (20쪽)"], { gap: 4 }), { x: 8.25, y: 4.4, w: 4.3, h: 2.3, fontSize: 15, color: WHITE });
}

// ---------- 3. 데이터
{
  const s = content("교수님 센서의 원본 데이터를 직접 해독해서 입력으로 썼다",
    "교수님이 주신 녹화는 .dvs 파일이고, 삼성 S5KRC1S 센서의 group AER 형식입니다. 이벤트 워드 하나가 최대 16픽셀을 담고, 컬럼 주소는 컬럼마다 한 번, 타임스탬프는 프레임마다 하나입니다. 프레임 주기는 1000fps가 아니라 실측 773마이크로초, 약 1294fps였습니다. 녹화는 두 개입니다. roll은 7500만 이벤트에 총 323도 회전하고, pan은 8700만 이벤트에 수평 1680픽셀 움직입니다. 정답 각도가 없어서 프레임끼리 정합하는 방법으로 정답을 대신 만들었고, 외부 벤치마크로 UZH 회전 시퀀스도 같은 디코더에 넣어 확인했습니다.");
  table(s, [
    ["항목", "내용"],
    ["형식", "Samsung S5KRC1S group AER (이벤트를 주소로 전달하는 AER 방식 중, 워드 1개에 최대 16픽셀을 묶음). 컬럼 주소는 컬럼당 1회, 타임스탬프는 프레임당 1개"],
    ["프레임 주기", "773 µs (약 1,294 fps) — \"1000 fps\"가 아님을 실측으로 확인"],
    ["roll 녹화 (9/22)", "7,534만 이벤트, 약 2,060프레임, 총 회전 323°"],
    ["pan 녹화 (9/15)", "8,678만 이벤트, 수평 이동 1,680 px"],
    ["정답", "없음 → 4프레임 창을 ECC(영상 두 장을 맞춰 회전각을 구하는 방법)로 정합한 각도를 정답 대용으로 사용"],
    ["외부 벤치마크", "UZH 회전 시퀀스(IMU·모캡 정답)를 같은 group AER 워드로 다시 부호화해 같은 디코더로 통과"],
  ], 0.6, 1.55, 12.1, [2.4, 9.7], { size: 12, rowH: 0.4 });
  card(s, 0.6, 4.6, 7.1, 2.3, "의미", "데이터 형식을 풀어서 칩의 디코더가 센서 원본 워드를 그대로 받는다 — 전처리용 변환기 없이 센서에 바로 붙는 구조.\n입력은 회전 중에 프레임당 수십만~수백만 이벤트가 몰리는 실제 센서 데이터다 (오른쪽: roll 녹화 100 ms 간격 이벤트 프레임).", { size: 13 });
  s.addImage({ path: fig("raw_frames_roll.png"), x: 7.95, y: 4.55, w: 4.75, h: 2.45 });
}

// ---------- 4. 전체 구조
{
  const s = content("전체 구조: 센서 워드 → 디코더 → 변환 8레인 → 월드 메모리",
    "칩의 구조입니다. 위쪽 줄이 쓰기 경로입니다. 센서의 group AER 워드가 디코더로 들어가고, 변환 8레인이 픽셀마다 월드 좌표를 계산하고, 직렬화기와 월드 라이터를 거쳐 월드 메모리 뱅크에 쓰입니다. 아래쪽 줄이 자세 추정기입니다. 같은 워드를 받아 시야 범위의 1비트 지도 세 장으로 회전각을 추정하고, CORDIC으로 만든 프레임 파라미터를 변환 레인에 프레임마다 한 번 넘겨줍니다. 칩 안에서 이벤트만으로 각도를 구하므로 외부에서 각도를 받을 필요가 없습니다.");
  const y1 = 1.7;
  bx(s, 0.6, y1, 1.9, 1.5, "센서 워드", "group AER 32비트\n(16픽셀/워드)", { hs: 13 });
  bx(s, 2.95, y1, 1.9, 1.5, "aer_decoder", "컬럼·그룹·프레임\n워드 해석", { hs: 13 });
  bx(s, 5.3, y1, 2.2, 1.5, "xf_b8 변환 8레인", "곱셈기 없는 증분 변환\n고정소수점 F=10", { hs: 13, fill: "EAF3FD", line: TEAL });
  bx(s, 7.95, y1, 1.9, 1.5, "pix_serializer", "픽셀 1개/사이클\n+ 병합 캐시", { hs: 13 });
  bx(s, 10.3, y1, 2.4, 1.5, "world_mem", "8 kbit 하드매크로\n뱅크 16개 (약 131 kbit)", { hs: 13, fill: "EAF3FD", line: TEAL });
  [[2.5, 2.95], [4.85, 5.3], [7.5, 7.95], [9.85, 10.3]].forEach(([a, b]) => arrow(s, a, y1 + 0.75, b, y1 + 0.75));
  const y2 = 4.15;
  bx(s, 2.95, y2, 1.9, 1.5, "est_tok_expand", "같은 픽셀 순서로\n펼침", { hs: 13 });
  bx(s, 5.3, y2, 2.9, 1.5, "est_core 자세 추정기", "1비트 평면 3장(cur/prev/key)\n후보 9개 점수 → 포물선 보정", { hs: 13, fill: "EAF3FD", line: TEAL });
  bx(s, 8.65, y2, 2.2, 1.5, "est_cordic ×2", "cos·sin → 프레임\n파라미터 (cs, sn, b0)", { hs: 13 });
  arrow(s, 3.9, y1 + 1.5, 3.9, y2); arrow(s, 4.85, y2 + 0.75, 5.3, y2 + 0.75); arrow(s, 8.2, y2 + 0.75, 8.65, y2 + 0.75);
  s.addShape(pres.ShapeType.line, { x: 6.4, y: y1 + 1.5, w: 3.35, h: y2 - (y1 + 1.5), line: { color: MID, width: 1.5, beginArrowType: "triangle" } });   // 음수 폭/높이는 PowerPoint가 못 열어서 시작점 화살표로 반대 방향을 그림
  T(s, "프레임마다 1회 (valid/ready)", { x: 7.2, y: 3.5, w: 3.4, h: 0.4, fontSize: 12, color: MID });
  card(s, 0.6, 5.95, 5.9, 0.95, "한 줄 요약", "쓰기 경로 + 추정기 + 매크로 메모리를 한 칩에", { size: 14 });
  card(s, 6.8, 5.95, 5.9, 0.95, "입출력", "입력: 센서 워드 스트림 / 출력: 월드 메모리 읽기 포트", { size: 14 });
}

// ---------- 13. 풀칩 P&R
{
  const s = content("풀칩 배치배선: 8.0 ns에서 signoff를 통과했다",
    "풀칩을 배치배선하고 독립 Quantus 추출로 signoff 타이밍을 쟀습니다. 8 ns, 125메가헤르츠에서 setup 여유가 2.4나노초, hold 여유는 7피코초로 위반이 없습니다. 센서의 최악 처리량이 약 112메가헤르츠라서 8나노초면 충족합니다. 8킬로비트 하드매크로 46개가 면적의 대부분이고, 표준셀은 0.33제곱밀리미터뿐입니다. DRC는 전원선 via 스택 10건만 남았는데, 신호선과 표준셀 위반은 없습니다. 이 10건을 없애려면 전원 배선부터 다시 만드는 풀 P&R이 필요해서 타이밍 클로저 위험 때문에 하지 않았습니다. 전력 13밀리와트는 벡터 없는 기본 활동도 값이고 매크로 내부 전력이 0으로 잡혀 있어 절대값 신뢰도는 낮습니다.");
  s.addImage({ path: fig("chipS_floorplan.png"), x: 0.6, y: 1.5, w: 6.4, h: 4.25 });
  T(s, "풀칩 배치: 2923×1942 µm, 8 kbit 하드매크로 46개 (추정기 평면 30 + 월드 16)", { x: 0.6, y: 5.8, w: 6.4, h: 0.5, fontSize: 11, color: MID });
  table(s, [
    ["항목 (8.0 ns, signoff)", "값"],
    ["setup WNS (Quantus, slow)", { text: "+2.406 ns, 위반 0", options: { bold: true, color: TEAL } }],
    ["hold WNS (fast)", { text: "+0.007 ns, 위반 0 (얇음)", options: { bold: true, color: TEAL } }],
    ["면적", "4.521 mm² = 매크로 4.194 + 표준셀 0.327"],
    ["전력 (벡터 없음)", "13.02 mW (매크로 내부 0으로 집계)"],
    ["DRC / 연결 / antenna", "10건(전원선 via 스택만) / 오픈 0 / 위반 없음"],
    ["LEC", { text: "비교점 14,618, 비동등 0", options: { bold: true, color: TEAL } }],
    ["처리량", "센서 최악 처리량 기준 필요 클록 약 112 MHz ≤ 125 MHz (현수 기록)"],
  ], 7.2, 1.55, 5.5, [2.2, 3.3], { size: 12, rowH: 0.5 });
  T(s, "용어: setup/hold 여유 = 신호가 너무 늦지(setup)·빠르지(hold) 않은 시간 여유(양수면 통과), LEC = 두 회로가 논리적으로 같음을 증명, DRC = 제조 설계 규칙 검사, signoff = 제조 직전 최종 검사 (19쪽 용어 풀이)", { x: 7.2, y: 5.6, w: 5.5, h: 0.8, fontSize: 10, color: MID });
  T(s, "한계: 전력은 활동도 입력 없이 낸 값이고 매크로 내부 전력이 0으로 집계되어 절대값 신뢰도가 낮다. 절감 근거는 병행 설계 실측(18쪽)으로 보강한다.", { x: 0.6, y: 6.35, w: 12.1, h: 0.6, fontSize: 13, color: INK });
}

// ---------- 12. 검증
{
  const s = content("검증: RTL이 기준모델과 한 비트도 다르지 않다",
    "검증은 기준모델을 정답으로 두고 RTL이 한 비트도 다르지 않은지 보는 방식입니다. 변환과 쓰기 경로는 교수 roll, pan과 UZH 세 데이터에서 픽셀마다 좌표와 뱅크, 주소, 니블을 비교하고, 끝에 월드 메모리 전체를 비교했는데 불일치가 없었습니다. 추정기는 교수 데이터 네 구간에서 프레임 파라미터와 창 상태, 점수, 끝 평면이 전부 일치했습니다. 칩 전체를 이은 종단 시뮬레이션도 프레임 파라미터, 창 상태, 최종 월드 메모리 2048워드까지 일치했습니다. 논리 동등성 검사는 합성 결과와 최종 넷리스트가 같은지 확인해 통과했고, 처음 시도한 평면 비교는 중단돼서 두 단계로 나눠 풀었습니다.");
  table(s, [
    ["검증 (RTL = 회로 설계 코드, 기준모델 = 소프트웨어 정답)", "대상", "결과 (불일치 0 = 한 비트도 다르지 않음)"],
    ["RTL ↔ 기준모델 (변환+쓰기)", "roll 20프레임 134만 픽셀, pan 20프레임 99만 픽셀, UZH 3,818 픽셀 + 월드 메모리 전체", { text: "불일치 0", options: { bold: true, color: GREEN } }],
    ["RTL ↔ 기준모델 (추정기)", "교수 4구간(roll_A/B, pan_A/B): 프레임 파라미터·창 상태·점수 54개/창·끝 평면", { text: "불일치 0", options: { bold: true, color: GREEN } }],
    ["종단 시뮬 (추정기+쓰기 경로)", "roll_B 32프레임, pan_B 64프레임: fp·창·최종 월드 2,048워드", { text: "불일치 0", options: { bold: true, color: GREEN } }],
    ["논리 동등성 (LEC)", "RTL → 합성 중간 → 최종 넷리스트, 비교점 14,618", { text: "비동등 0", options: { bold: true, color: GREEN } }],
    ["게이트 시뮬 (signoff SDF)", "pan_B, roll_B, MIN·MAX 코너 (8 ns)", { text: "bit-exact", options: { bold: true, color: GREEN } }],
  ], 0.6, 1.55, 12.1, [3.2, 6.9, 2.0], { size: 13, rowH: 0.62 });
  card(s, 0.6, 5.5, 12.1, 1.4, "검증이 잡아낸 것", "LEC 첫 시도(RTL 대 최종 넷리스트 직접 비교)는 곱셈-덧셈 경로에서 abort 124·비동등 2,523으로 실패 → 합성 중간 넷리스트를 거치는 2단계 비교로 해결. 게이트 시뮬 테스트벤치 결함 2건(입력 인가 시점, 첫 쓰기 유실)도 시뮬이 드러냄.", { size: 13 });
}

// ---------- 8. 정확도
{
  const s = content("정확도: roll은 0.47°, 하지만 UZH에서는 한계가 있다",
    "정수 기준모델의 정확도입니다. roll 녹화에서 ECC 정답 대비 평균 0.47도, pan에서 평균 14픽셀입니다. 이 정수 모델은 RTL의 사양이고, RTL과 비트 단위로 일치합니다. 다만 UZH 회전 시퀀스에서 3자유도 정수 모델의 정확도는 좋지 않았습니다. 5초 간격 중복 지표가 91픽셀로, float 기준 15픽셀에 한참 못 미칩니다. 원인은 이동량 차이를 기준 평면 각도로 돌려 주지 않는 근사로 의심되고, 교수님 데이터는 회전 한 자유도라 영향이 없습니다. 그래서 UZH에서의 RTL은 하드웨어 일치 검증용으로만 쓰고 정확도 수치로는 인용하지 않습니다.");
  table(s, [
    ["데이터", "측정", "결과", "비고"],
    ["roll (교수)", "ECC 대비 각도 오차, 정수 기준모델", { text: "평균 0.467° (오프셋 제거 0.462°)", options: { bold: true } }, "정답 = 4프레임 ECC 정합"],
    ["pan (교수)", "ECC 대비 이동 오차", { text: "평균 14.0 px (오프셋 제거 11.8 px)", options: { bold: true } }, "pan은 회전+이동 연동 상수 사용"],
    ["UZH (3자유도)", "float 복제 모델", "5초 간격 중앙값 28 → 9 px (키프레임 8장), 모델 바닥 3.9 px", "float 결과"],
    ["UZH (3자유도)", "정수 기준모델", { text: "5초 91 px — 정확도 수치로 쓰지 않음", options: { color: RED, bold: true } }, "RTL=기준모델 일치 검증용"],
  ], 0.6, 1.5, 12.1, [1.9, 3.3, 4.2, 2.7], { size: 12, rowH: 0.45 });
  s.addImage({ path: fig("hs_C3_roll_ecc.png"), x: 0.6, y: 3.95, w: 4.6, h: 2.87 });
  s.addImage({ path: fig("hs_C5b_err_hist.png"), x: 5.4, y: 3.95, w: 7.3, h: 2.59 });
  T(s, "정답이 ECC 체인이라 그 자체의 오차가 섞여 있어 교수 데이터와 UZH 정확도는 직접 비교하지 않는다. 빠른 3축 회전에서는 추적을 잃으면 도형이 복제되는 한계가 남아 있다.", { x: 5.4, y: 6.58, w: 7.3, h: 0.5, fontSize: 11, color: MID });
}

// ---------- 8b. 칩이 만든 월드 지도 (roll, pan)
{
  const s = content("칩 S가 만든 월드 맵: 보정 전 소용돌이가 방의 구조로 바뀐다",
    "위쪽은 교수님 roll과 pan 녹화 전체를 칩 모델에 통과시킨 결과입니다. 왼쪽은 이벤트를 그대로 쌓은 것이고 오른쪽이 칩 출력입니다. roll은 응집도가 1.06에서 2.34로, pan은 1.16에서 2.76으로 올랐습니다. 아래쪽은 칩 RTL 시뮬레이션이 roll 32프레임을 받아 실제 월드 메모리에 쓴 값입니다. 8픽셀 셀에 4비트 로그 카운터라 해상도는 낮지만 같은 장면이 복원되고, 같은 칩에 자기보정 피벗을 설정해도 같은 지도가 나옵니다. 가장 아래 줄은 프레임이 쌓이며 지도가 자라는 과정입니다.");
  s.addImage({ path: fig("hs_A1_roll.png"), x: 0.6, y: 1.3, w: 6.0, h: 2.94 });
  s.addImage({ path: fig("hs_A2_pan.png"), x: 6.8, y: 1.3, w: 5.9, h: 1.45 });
  T(s, "교수님 roll·pan 녹화 전체: 이벤트를 그대로 쌓은 것(왼쪽) 대 칩 S 출력(오른쪽), 동일 스케일. 응집도(지도 선명도, 높을수록 선명) roll 1.06 → 2.34, pan 1.16 → 2.76.", { x: 6.8, y: 2.8, w: 5.9, h: 0.55, fontSize: 10, color: MID });
  s.addImage({ path: fig("chip_roll_world.png"), x: 0.6, y: 4.4, w: 5.6, h: 2.09 });
  T(s, "RTL 시뮬 roll 32프레임: 보정 없음 / 칩 출력 / 보정 피벗 설정", { x: 0.6, y: 6.52, w: 5.6, h: 0.3, fontSize: 10, color: MID });
  s.addImage({ path: fig("hs_E9_roll.png"), x: 6.8, y: 3.45, w: 2.5, h: 2.24 });
  T(s, "칩 월드 메모리 내용 (4비트 로그 카운터)", { x: 6.8, y: 5.72, w: 2.5, h: 0.4, fontSize: 10, color: MID });
  s.addImage({ path: fig("chip_map_growth.png"), x: 9.5, y: 3.5, w: 3.2, h: 0.73 });
  T(s, "프레임이 쌓이며 지도가 자란다 (2→32프레임)", { x: 9.5, y: 4.25, w: 3.2, h: 0.3, fontSize: 10, color: MID });
  T(s, "읽는 법: 위쪽 두 그림은 녹화 전체를 칩 모델에 통과시킨 월드 맵이고, 왼쪽 아래 RTL 시뮬 그림은 칩 RTL이 실제로 월드 메모리에 쓴 값(8 px 셀)이다. RTL = 기준모델이 비트 단위로 같아서 같은 장면을 보여 준다.", { x: 9.5, y: 4.7, w: 3.2, h: 2.2, fontSize: 11, color: INK });
}

// ---------- 8c. 파노라마와 3D
{
  const s = content("월드 지도 모음: pan 파노라마, 3D 시점, 외부 UZH 데이터",
    "위쪽은 pan 녹화로 만든 월드 지도 파노라마이고, 방과 광학 테이블의 구조가 이어져 보입니다. 아래는 회전만으로 복원한 월드 지도를 회전 중심 기준 상대 3D 점구름으로 보고, 수직축으로 마이너스 35도와 플러스 35도 돌려 본 것입니다. 이 그림들은 우리 소프트웨어 모델로 만든 시각화이고 칩의 출력 형식과 같은 월드 좌표를 씁니다.");
  s.addImage({ path: fig("panorama_pan.png"), x: 0.6, y: 1.4, w: 6.0, h: 1.67 });
  T(s, "pan 녹화 월드 지도 파노라마 (소프트웨어 모델)", { x: 0.6, y: 3.1, w: 6.0, h: 0.3, fontSize: 11, color: MID });
  s.addImage({ path: fig("hs_B_shapes.png"), x: 0.6, y: 3.5, w: 6.0, h: 2.68 });
  T(s, "외부 UZH shapes_rotation(59초) 칩 S 월드 맵: 복제 제거 전(왼쪽) 대 자기보정+키프레임 앵커(오른쪽), 응집도 3.18 → 10.03", { x: 0.6, y: 6.22, w: 6.0, h: 0.6, fontSize: 10, color: MID });
  s.addImage({ path: img("ROLL_3D_real_views.png"), x: 6.9, y: 1.4, w: 5.8, h: 2.32 });
  T(s, "roll 3D 월드 지도, 시점 −35° / +35°", { x: 6.9, y: 3.75, w: 5.8, h: 0.3, fontSize: 11, color: MID });
  s.addImage({ path: img("PAN_3D_real_views.png"), x: 6.9, y: 4.2, w: 5.8, h: 2.32 });
  T(s, "pan 3D 월드 지도, 시점 −35° / +35°", { x: 6.9, y: 6.55, w: 5.8, h: 0.3, fontSize: 11, color: MID });
}

// ---------- 9. 과적합: 원인, 해결, 독립 검증
{
  const s = content("과적합 해결: 상수 여러 개는 \"피벗 하나\"였고, 데이터에서 구한다",
    "과적합의 원인은 녹화마다 손으로 맞춘 상수가 사실 피벗 하나라는 점이었습니다. 다른 녹화의 상수를 그대로 쓰면 roll이 61도 무너지지만, 피벗을 데이터에서 구하는 자기보정으로 0.67도가 됩니다. 처음 몇 창을 3자유도로 돌려 각도와 이동량을 모으고 최소제곱으로 피벗을 구한 뒤 한 자유도로 고정합니다. 정수 기준모델에서도 확인했고, 구한 피벗의 각도 오차 0.405도는 손으로 맞춘 피벗의 0.467도보다 작았습니다. 아래 표는 정답 있는 합성 장면에서 독립적으로 검증한 결과입니다. 피벗 반지름이 50에서 20,000픽셀까지 변해도 프리즈 방식은 8도에서 116도로 무너지는 반면 자기보정은 0.2에서 1.7도를 유지합니다. 기준은 코드보다 먼저 커밋했고 실패한 기준도 그대로 보고합니다.");
  table(s, [
    ["ECC 대비, 오프셋 제거 평균", "roll", "pan"],
    ["다른 녹화의 상수를 그대로 사용 (프리즈)", { text: "61.2°", options: { bold: true, color: RED } }, { text: "472 px", options: { bold: true, color: RED } }],
    ["자기 데이터에 다시 맞춤 (재맞춤)", "0.62°", "8.97 px"],
    ["자기보정 (상수 0개, float 모델)", { text: "0.67°", options: { bold: true } }, "13.9 px (키프레임 8장 시 8.0 px)"],
    ["정수 기준모델: 구한 피벗 / 손으로 맞춘 피벗", "0.405° / 0.467°", "12.0 px"],
  ], 0.6, 1.5, 7.9, [4.3, 1.6, 2.0], { size: 12, rowH: 0.42 });
  T(s, "피벗 = 카메라가 도는 중심. 자기보정: 3자유도로 (θ, tx, ty)를 모아 t = (R(θ)−I)·u 최소제곱으로 피벗 u를 구함, r² 0.9 이상이면 1자유도 고정", { x: 0.6, y: 3.72, w: 7.9, h: 0.3, fontSize: 10, color: MID });
  s.addImage({ path: fig("hs_D6_roll.png"), x: 8.8, y: 1.45, w: 3.9, h: 1.76 });
  T(s, "다른 녹화의 상수를 쓰면(왼쪽) 번지고, 자기 녹화 상수(오른쪽)면 방이 보인다. roll, 응집도 1.28 대 2.34", { x: 8.8, y: 3.23, w: 3.9, h: 0.6, fontSize: 10, color: MID });
  s.addChart(pres.charts.BAR, [
    { name: "자기보정", labels: ["R 1,552 px (회전 20°)", "R 6,000 px (8°)", "R 20,025 px (5°)"], values: [0.29, 0.22, 1.68] },
    { name: "재맞춤", labels: ["R 1,552 px (회전 20°)", "R 6,000 px (8°)", "R 20,025 px (5°)"], values: [0.25, 0.10, 0.06] },
    { name: "프리즈 (다른 녹화 상수)", labels: ["R 1,552 px (회전 20°)", "R 6,000 px (8°)", "R 20,025 px (5°)"], values: [8.3, 18.1, 115.9] },
  ], Object.assign({ x: 0.6, y: 4.1, w: 8.0, h: 2.85, barDir: "col" }, chartBase("정답 있는 합성 장면: 각도 오차 (°)", [TEAL, "7A7A7A", "1D1D1F"]), { showLegend: true, legendPos: "b", legendFontFace: FONT, legendFontSize: 11, dataLabelFormatCode: "0.00", dataLabelFontSize: 10, valAxisMinVal: 0, valAxisMaxVal: 130 }));
  s.addShape(pres.ShapeType.roundRect, { x: 8.9, y: 3.95, w: 3.8, h: 1.45, fill: { color: DARK }, line: { color: DARK }, rectRadius: 0.12 });
  T(s, "115.9° → 1.68°", { x: 9.1, y: 4.05, w: 3.4, h: 0.7, fontSize: 28, bold: true, color: BLUE_D, valign: "middle" });
  T(s, "pan 크기 피벗(R 20,025 px): 프리즈 대비 자기보정", { x: 9.1, y: 4.8, w: 3.4, h: 0.55, fontSize: 12, color: WHITE });
  card(s, 8.9, 5.5, 3.8, 1.45, "범위", "50~150 px 피벗(G1~G4, 회전 120°)에서는 세 방식 모두 0.7~2.6°. 합성은 단일 깊이·한 방향 회전.", { size: 11 });
}

// ---------- 5. 좌표 변환
{
  const s = content("좌표 변환: 곱셈기 없이 8레인이 한 사이클에 픽셀을 옮긴다",
    "좌표 변환은 후보를 넓게 비교해서 골랐습니다. 직접 곱셈, CORDIC, 3단 전단 분해, 그리고 이번에 채택한 증분 변환을 같은 통합 모델에서 비교했습니다. 증분 변환 8레인은 곱셈기가 없고, 직접 곱셈과 출력이 한 비트도 다르지 않으면서 합성 면적은 2.29분의 1, 전력은 2.54분의 1입니다. 단, 이 이득은 센서가 8픽셀 묶음으로 데이터를 줄 때만 납니다. 한 픽셀씩 직렬로 처리하면 오히려 1.9배 큽니다. 교수님 센서가 group AER라서 맞아떨어진 선택입니다. CORDIC은 면적이 커서, 3단 전단은 정수 픽셀 전단이 비트 일치가 아니어서 탈락했습니다.");
  table(s, [
    ["후보", "결과", "이유"],
    [{ text: "증분 변환 8레인 (채택)", options: { bold: true } }, { text: "채택", options: { bold: true, color: GREEN } }, "직접 곱셈과 출력 비트 일치, 면적 2.29배·전력 2.54배 작음 (group AER 8픽셀 묶음과 결합할 때)"],
    ["직접 곱셈", "기준", "비트 기준 모델. 같은 8레인에서 더 큼"],
    ["CORDIC (곱셈기 없이 사인·코사인 계산)", "탈락", "면적이 커서"],
    ["3단 전단(shear) 분해 회전", "탈락", "정수 픽셀 전단은 평균 0.44 px 오차, 정수 일치 70% — 비트 일치 아님"],
    ["행별 읽기 시각 보정", "탈락", "프레임당 최대 0.4°라 선명도 변화 +0.2~0.4%"],
    ["렌즈 왜곡 보정", "탈락", "직선성 잔차 0.987 → 0.987 px, 지도 선명도 −1.9% (손해)"],
  ], 0.6, 1.5, 12.1, [3.4, 1.2, 7.5], { size: 12, rowH: 0.42 });
  s.addChart(pres.charts.BAR, [
    { name: "직접 곱셈", labels: ["면적", "전력"], values: [1.0, 1.0] },
    { name: "증분 변환 8레인 (채택)", labels: ["면적", "전력"], values: [0.44, 0.39] },
  ], Object.assign({ x: 6.8, y: 4.45, w: 5.9, h: 2.55, barDir: "col" }, chartBase("직접 곱셈 대비 상대값 (작을수록 좋음)", ["7A7A7A", TEAL]), { showLegend: true, legendPos: "r", legendFontFace: FONT, legendFontSize: 11, dataLabelFormatCode: "0.00", valAxisMinVal: 0, valAxisMaxVal: 1.2 }));
  card(s, 0.6, 4.7, 5.9, 2.2, "채택안 사양", "고정소수점 F=10, cos/sin은 CORDIC 2개(추정기 F=12, 월드 F=10)로 계산 — 각도 단계 LUT가 아니라 연속 각도\n합성 변환 블록 13,866 µm². 곱셈기를 없애는 것이 항상 이득은 아니고, 8픽셀 그룹 입력과 맞물릴 때만 이긴다.", { size: 12 });
}

// ---------- 6. 월드 메모리
{
  const s = content("월드 메모리: 8 px 셀 × 4비트 로그 카운터, 8 kbit 뱅크 16개",
    "월드 메모리는 8픽셀 단위 셀에 4비트짜리 확률적 로그 카운터를 둡니다. 이벤트가 들어올 때마다 셀 값을 올리는데, LFSR 난수로 확률적으로 올려서 4비트로도 넓은 범위를 셉니다. 2비트 극성은 셀의 96퍼센트가 포화돼서 장면이 거의 안 남아 탈락했습니다. 메모리는 8킬로비트 하드매크로 뱅크로 쪼개서 공간 타일로 배치했고, 시야 아래쪽 뱅크만 클록을 켭니다. 읽기와 쓰기 횟수를 줄이려고 프레임 단위로 비우는 64칸 병합 캐시를 앞에 두었는데, 64칸이면 프레임당 서로 다른 워드 수와 정확히 같아서 이상적인 병합입니다. 면적은 사실상 메모리가 결정합니다.");
  table(s, [
    ["항목", "값"],
    ["셀", "8 px × 8 px = 64 센서 픽셀, 4비트 Morris 로그 카운터 (난수 LFSR로 확률적으로 올려 큰 수까지 셈), 포화 0%"],
    ["뱅크", "64×32셀 = 8 kbit 공간 타일 하드매크로. 워드 64비트(4×4셀), 뱅크당 128워드"],
    ["월드 크기", "roll 180×180셀(1440×1440 px 영역), 칩은 16뱅크 약 131 kbit 사용"],
    ["병합 캐시", "프레임 단위로 비우는 완전연관 write-back 64칸 — 읽기 14,568회 = 프레임당 서로 다른 워드 수"],
    ["뱅크 게이팅", "시야 밑 뱅크만 클록 활성 (평균 활성 뱅크 roll 약 76%, pan 약 97%, 행우선 선형 배치 기준)"],
  ], 0.6, 1.55, 7.6, [1.7, 5.9], { size: 12, rowH: 0.46 });
  s.addImage({ path: fig("wave_row_gating.png"), x: 8.45, y: 1.5, w: 4.25, h: 2.27 });
  T(s, "행 단위 클록 게이팅 파형: 쓰는 행의 게이트 클록만 토글, 나머지 행은 꺼짐 (RTL 시뮬)", { x: 8.45, y: 3.8, w: 4.25, h: 0.7, fontSize: 11, color: MID });
  card(s, 8.5, 4.65, 4.2, 2.25, "선택 근거", "FF+클록게이팅은 Layout·PEX·게이트 시뮬이 전부 닫히는 유일한 구현. 게이팅이 없으면 면적 1.3배·전력 3.8배.", { size: 13 });
  s.addImage({ path: fig("chip_bank_hist.png"), x: 0.6, y: 4.45, w: 7.6, h: 2.12 });
  T(s, "한계: 교육용 PDK에는 SRAM 매크로가 없어 FF 기반(비트당 약 11.8 µm²). 큰 월드로 가려면 SRAM이 필요하다.", { x: 0.6, y: 6.6, w: 7.6, h: 0.4, fontSize: 11, color: MID });
}

// ---------- 7. 자세 추정기
{
  const s = content("자세 추정기: 시야 범위 1비트 지도로 이벤트에서 각도를 구한다",
    "자세 추정기는 이벤트만으로 회전각을 구합니다. 시야 범위를 3픽셀 셀로 나눈 1비트 지도를 세 장 둡니다. 직전 창, 현재 창, 그리고 키프레임 앵커입니다. 창의 이벤트를 후보 각도 아홉 개로 돌려서 직전 지도와 겹치는 정도를 점수로 매기고, 가장 높은 후보를 포물선으로 보정합니다. 느릴 때만 창을 8프레임으로 늘리고, 속도는 이전 값과 섞습니다. 키프레임은 각도가 30도 이상 벌어지면 교체해서 누적 오차를 줄입니다. 이 구조를 정수 기준모델로 먼저 만들고, 같은 동작을 RTL로 구현해 비트 단위로 맞췄습니다.");
  card(s, 0.6, 1.55, 3.9, 2.4, "지도", "시야 1비트 평면 3장\n(cur / prev / key)\n3 px 셀 · 320×240\n평면당 76.8 kbit, 합계 230.4 kbit", { size: 14 });
  card(s, 4.72, 1.55, 3.9, 2.4, "추정", "창 L=4 프레임 (느리면 8)\n표본 최대 2,048개\n후보 9개 × (prev + key×w/4)\n포물선 보정 · 속도 혼합 an/10", { size: 14 });
  card(s, 8.84, 1.55, 3.9, 2.4, "누적 오차 제어", "키프레임 앵커(기준 프레임): 각도가 30° 벌어지면 교체\n정수 연산만 (기준모델 = RTL 사양)", { size: 14 });
  table(s, [
    ["측정", "값"],
    ["처리량 (추정기 단독, 200 MHz)", "프레임당 0.43 ms — 프레임 주기 0.773 ms의 1.8배 여유"],
    ["처리량 (종단: 추정기+쓰기 경로, 현재 칩)", "roll_B 게이트 시뮬 2.86M 사이클/32프레임 = 프레임당 약 8.9만 사이클 → 8 ns에서 0.715 ms, 프레임 주기 0.773 ms 이내 (여유 1.08배, 얇음)"],
    ["합성 (평면 3장)", "평면이 월드 메모리(131 kbit)보다 큼 → 8 kbit 뱅크 매크로로 구성"],
  ], 0.6, 4.2, 12.1, [4.0, 8.1], { size: 13, rowH: 0.55 });
  T(s, "각도 추정과 좌표 변환이 같은 칩 안에 있어 외부 자세 입력이 필요 없다.", { x: 0.6, y: 6.55, w: 12.1, h: 0.4, fontSize: 14, bold: true, color: TEAL });
}

// ---------- 14. 시행착오: 클록 8 ns
{
  const s = content("시행착오 ①: 5.5 ns 목표는 시뮬이 못 따라가 8.0 ns로 물러났다",
    "가장 큰 시행착오입니다. 5.5나노초를 목표로 배치배선했고 정적 타이밍 분석은 여유가 25피코초로 통과했습니다. 그런데 느린 코너 SDF로 게이트 시뮬레이션을 돌리면 5.5나노초에서 정지했고 6나노초에서는 불일치가 났습니다. 8나노초와 12나노초에서는 완주해서 비트 단위로 일치합니다. 같은 넷리스트가 정적 분석에서는 위반이 없는데 시뮬에서만 이상해서 원인을 추적했습니다. 매크로 모델의 경주, 입력 인가 지연, 셀 모델의 타이밍 검사를 하나씩 배제했지만 끝내 규명하지 못했습니다. 그래서 출하 클록을 8나노초로 고정하고, 규명하지 못했다는 사실을 한계로 적었습니다.");
  table(s, [
    ["클록", "정적 타이밍 (STA: 계산으로 지연 검사)", "게이트 시뮬 (MAX 코너 SDF: 실제 지연값 시뮬)"],
    ["5.5 ns", "setup +0.025 ns (여유 얇음)", { text: "7번째 워드에서 정지", options: { color: RED, bold: true } }],
    ["6 ns", "—", { text: "불일치 (fp 52, window 2, world 770)", options: { color: RED, bold: true } }],
    ["8 ns", "setup +2.406 ns", { text: "bit-exact 통과 (pan_B, roll_B)", options: { bold: true } }],
    ["12 ns", "—", { text: "bit-exact 통과", options: { bold: true } }],
  ], 0.6, 1.55, 7.4, [1.3, 3.0, 3.1], { size: 13, rowH: 0.58 });
  card(s, 8.3, 1.55, 4.4, 2.9, "배제한 가설", "• 매크로 읽기/쓰기 경주 (모델 수정)\n• 입력 인가 지연 0.1~1.0 ns\n• 셀 모델 setup/hold 검사 (정지 구간 위반 0건)\n• 슬로우 뷰 hold STA (+3.67 ns)", { size: 12 });
  card(s, 0.6, 4.7, 5.9, 2.2, "그 과정에서 고친 것", "• 테스트벤치: 입력을 반주기에 인가하던 것을 SDC 입력 지연 방식으로\n• 첫 번째 월드 쓰기가 유실 → 앞에 더미 쓰기 2회\n• STA 허위 위반(setup −0.92/hold −0.71): set_propagated_clock 누락이 원인", { size: 12 });
  card(s, 6.8, 4.7, 5.9, 2.2, "남은 의문", "STA는 통과하는데 느린 코너 SDF 시뮬만 6 ns 이하에서 틀린다. STA가 못 보는 경로(클록 게이팅 래치, 반주기 경로, 매크로 타이밍 모델 차이)가 의심되지만 미규명.", { size: 12, headColor: RED });
}

// ---------- 15. 시행착오: 후보 탈락
{
  const s = content("시행착오 ②: 약 60개 후보를 측정해서 걸러냈다",
    "설계는 후보를 먼저 넓게 모으고 측정으로 걸러서 정했습니다. 약 60개 후보가 있었고, 후보마다 측정 결과와 탈락 사유를 문서로 남겼습니다. 월드 표현에서는 해시 스케치, 블록 부동소수점, 희소 월드, 로그 극좌표를 시험했는데 모두 상관이나 비트 비용에서 졌습니다. 추정기에서는 셀별 깊이 지도가 정답 궤적에서는 10퍼센트 좋아 보였지만 칩 안 추정 궤적에서는 틀린 방향 대조군이 더 높게 나와서 추정 오차를 흡수하는 것으로 판단하고 뺐습니다. 래치 메모리는 배치 후 시뮬에서 24퍼센트가 불일치해서 탈락했습니다. 무엇을 안 했는지도 설계의 일부라고 생각합니다.");
  table(s, [
    ["후보", "결과", "측정된 탈락 사유"],
    ["Count-Min 스케치 world", "탈락", "상관 0.1~0.4 — 셀 점유율이 높아 충돌로 빈 공간까지 번짐"],
    ["블록 부동소수점 world", "탈락", "상관 0.62/0.58 — 밝은 셀이 블록 지수를 올려 어두운 셀 소실"],
    ["희소 world (점유 셀만 저장)", "탈락", "4 px에서 희소하지 않음: 이벤트 45% 버림, 태그 포함 격자의 2.6배 비트"],
    ["로그-극좌표 world", "탈락", "선형극좌표 상관 0.87 < 8px 격자 0.92, 로그극좌표 0.71, pan 불가"],
    ["셀별 깊이 지도", "탈락", "정답 궤적에서 +10%지만 온칩 궤적에선 틀린 방향 대조군이 더 높게 나옴 (추정 오차 흡수)"],
    ["4 px 월드", "탈락", "추정 오차 1°에 미세 구조가 묻힘 → 8 px·4비트(면적 2.4배 작음)로"],
    ["world 예측 부호화 (AER)", "보류", "−25%지만 센서 측 1.38 Mbit 버퍼 필요"],
    ["메모리 뱅크를 래치로", "탈락", "배치 후 시뮬레이션 24% 불일치"],
    ["α-β 추적기", "탈락", "UZH에서 오히려 악화 (38.7 vs 32.6 °/s), 교수 데이터 과적합"],
  ], 0.6, 1.5, 8.0, [2.4, 0.8, 4.8], { size: 11, rowH: 0.52 });
  s.addChart(pres.charts.BAR, [{ name: "지도 상관", labels: ["8 px 격자 (채택)", "선형 극좌표", "로그 극좌표", "블록 부동소수점"], values: [0.92, 0.87, 0.71, 0.60] }], Object.assign({ x: 8.9, y: 1.5, w: 3.8, h: 4.2, barDir: "bar" }, chartBase("월드 표현별 지도 상관 (높을수록 좋음)", [TEAL, "7A7A7A", "7A7A7A", "7A7A7A"]), { dataLabelFormatCode: "0.00", valAxisMinVal: 0, valAxisMaxVal: 1 }));
  T(s, "블록 부동소수점은 0.62/0.58의 평균", { x: 8.9, y: 5.75, w: 3.8, h: 0.4, fontSize: 11, color: MID });
}

// ---------- 17. 시행착오 ③: 병행 설계 라인 + 메모리·물리
{
  const s = content("시행착오 ③: 병행 설계 라인과 메모리·물리 설계에서 겪은 것들",
    "") ;
  table(s, [
    ["시도", "결과", "교훈"],
    ["클록 게이팅 hold −0.030 ns", "라이브러리 ICG 셀(클록 게이트 전용 셀)로 +0.080 ns", "CTS(클록 트리 합성)가 래치를 말단으로 보고 AND보다 0.2 ns 일찍 엶"],
    ["reg2reg hold −7 ps (61경로)", "버퍼 삽입 실패 → mux 교체 MX2XL(더 빨라 악화) → CLKMX2X4로 +0.003 ns", "밀집 영역에선 새 셀을 못 놓음, 셀 속도는 실측으로 고름"],
    ["메모리 구현 (SRAM 없음)", "FF+클록 게이팅 11.8 µm²/bit만 레이아웃·추출·게이트 시뮬이 모두 닫힘 (게이팅 없음 15.5, 래치는 배치 후 24% 불일치)", "교육용 PDK 제약 안에서 실측으로 고름"],
    ["풀칩 DRC (전원선 via 스택)", "105 → 26 → 10건. 되돌리는 방식이 기존 객체까지 지워 전원 오픈 발생 → 사전 검사 후 한 번만 적용", "안 닫히면 이상한 상태에서 측정했는지부터 의심"],
    ["키프레임(SLAM) 지도", "합성 0.43~1.0° vs 현재 0.35~0.40°, 실제 DELTA 지도 정합 0.241 → 0.18~0.20", "현재 구조가 이미 암묵적 폐루프라 소급 보정 여지 없음"],
    ["1024각도 좌표 변환", "표(RMCM): DRC 1만+, setup −20.9 ns / 직접 행렬곱: DRC 0, 면적 1/4.6", "입력 공간이 크면 표가 지고 배선도 안 풀림"],
    ["추정기 FF 메모리 단독 P&R", "setup −17.7 ns, 면적 합성 584,631 → 1,162,829 µm²", "FF 기반은 한계, SRAM 필요"],
  ], 0.6, 1.5, 12.1, [2.8, 5.6, 3.7], { size: 11, rowH: 0.6 });
}

// ---------- 19'. 시행착오 ⑤ 생체 모방 + 전력 근거
{
  const s = content("시행착오 ④: 생체 모방은 실제 데이터로 이긴 3개만 남겼다",
    "병행 설계 라인에서 저희는 생체 모방 아이디어를 여러 개 시도했습니다. 원칙은 합성 장면에서 좋아 보여도 실제 프레임과 사전에 정한 기준으로 다시 확인하는 것이었습니다. 채택한 것은 세 가지입니다. 이벤트를 열 단위로 묶는 중심와식 클러스터링은 손실을 57.6퍼센트에서 6.9퍼센트로 줄였고, 눈 깜빡임을 본뜬 유휴 시 코어 클록 차단은 유휴가 긴 입력에서 전력을 71퍼센트 줄였으며, 메모리 행 단위 선택적 활성화는 실제 DELTA 활동도에서 전력을 65.5퍼센트 줄였습니다. 반대로 이득 조절은 합성 장면에서만 이득이 있어 정정했고, 원심성 복사는 UZH에서는 23.4도에서 8.5도로 좋아졌지만 RobotEvt에서는 기준을 못 넘어 기각했습니다. 희소 행 할당과 기억 소멸, 키프레임 지도도 사전 기준을 넘지 못했습니다. 칩 S의 전력 13밀리와트는 활동도 입력이 없는 값이라서, 절감 효과는 이 병행 실측으로 보강합니다. 단 blink의 71퍼센트는 유휴가 길도록 만든 시험 입력의 값이고, 실제 DELTA에서 칩이 일하는 시간은 3에서 25퍼센트입니다.");
  table(s, [
    ["생체 모방 아이디어", "결과", "근거"],
    ["중심와(fovea) / 이벤트 클러스터링", { text: "채택", options: { bold: true, color: GREEN } }, "열 비트맵: 손실 57.6% → 6.9%(동일 합성 트래픽), 결합판 0.47%(UZH 실측)"],
    ["눈 깜빡임: 유휴 시 코어 클록 차단", { text: "채택", options: { bold: true, color: GREEN } }, "출력·메모리 일치, 유휴 전력 −71% (유휴 긴 시험 입력)"],
    ["행 단위 선택적 활성화 (메모리)", { text: "채택", options: { bold: true, color: GREEN } }, "실제 DELTA 활동도 전력 2.52 → 0.87 mW (−65.5%), 면적 −5%"],
    ["이득 조절(과부하 솎아내기)", "기각·정정", "합성에서만 이득, 실제 DELTA 프레임에서 이득 없음"],
    ["추정기 입력 줄이기(ON만/중심 가중/불응기)", "기각", "정확도 1.5배 이상 악화"],
    ["미세 안구운동(지터)", "기각", "부화소 복원 효과 없음"],
    ["원심성 복사(VOR): 회전 지령을 θ 사전분포로", "기각", "UZH 23.4° → 8.5°이나 RobotEvt 36.1° → 34.9° (기준 25.3° 미달)"],
    ["희소 행 할당(해마식 지연 할당)", "기각", "건드려진 행 UZH 52.9%·RobotEvt 55.5% (기준 50% 이하 미달)"],
    ["기억 소멸(forgetting)", "기각", "카운터 감쇠: UZH 23.4° → 23.8°, RobotEvt 36.1° → 36.0° (0.8배 기준 미달)"],
    ["키프레임(SLAM) 지도", "기각", "합성·실제 DELTA 모두 이득 없음, 메모리 3.7배"],
  ], 0.6, 1.5, 8.5, [3.1, 0.9, 4.5], { size: 11, rowH: 0.44 });
  s.addShape(pres.ShapeType.roundRect, { x: 9.35, y: 1.5, w: 3.35, h: 1.6, fill: { color: DARK }, line: { color: DARK }, rectRadius: 0.12 });
  T(s, "−65.5%", { x: 9.55, y: 1.6, w: 3.0, h: 0.8, fontSize: 36, bold: true, color: BLUE_D, valign: "middle" });
  T(s, "행 클록 게이팅 메모리 전력\n(실제 DELTA 활동도, 면적 −5%)", { x: 9.55, y: 2.4, w: 3.0, h: 0.65, fontSize: 12, color: WHITE });
  s.addImage({ path: fig("wave_blink.png"), x: 9.35, y: 3.25, w: 3.35, h: 1.2 });
  T(s, "Blink 파형: 입력이 끊기면 코어 클록 차단, 새 입력에 다시 켬. 유휴 전력 −71% (유휴 긴 시험 입력 한정)", { x: 9.35, y: 4.47, w: 3.35, h: 0.5, fontSize: 9, color: MID });
  card(s, 9.35, 5.0, 3.35, 1.9, "칩 S와의 관계", "칩 S의 8 kbit 뱅크는 이미 클록 게이팅(FF+CG). 13 mW는 활동도 입력이 없는 값이라 절감은 이 실측으로 보강. 실제 DELTA 칩 가동 비율은 3~25%.", { size: 11, headColor: RED });
  T(s, "원칙: 합성 장면 이득은 실제 프레임과 사전 기준으로 다시 확인한 뒤에만 채택", { x: 0.6, y: 6.55, w: 8.5, h: 0.4, fontSize: 13, bold: true, color: TEAL });
}

// ---------- 18g. 용어 풀이
{
  const s = content("용어 풀이: 이 발표에서 쓰는 말들",
    "");
  const L = [
    ["용어", "뜻"],
    ["이벤트 카메라 (DVS)", "밝기가 변한 픽셀만 (주소, 극성)으로 내보내는 센서"],
    ["AER / group AER", "이벤트를 주소로 전달하는 방식. group AER는 한 워드에 최대 16픽셀을 묶음"],
    ["ECC 정합", "영상 두 장을 맞춰 회전각을 구하는 방법 (정답 대용)"],
    ["피벗 (회전 중심)", "카메라가 도는 중심점. 이 위치가 틀리면 지도가 번짐"],
    ["응집도 (Cocc)", "월드 맵이 얼마나 선명하게 쌓였는지의 지표 (높을수록 선명)"],
    ["월드 메모리 / 월드 맵", "회전을 보정한 좌표에 이벤트를 쌓아 만든 지도 (칩 안 메모리)"],
    ["Morris 로그 카운터", "확률적으로 올려 4비트로 큰 수까지 세는 카운터 (LFSR = 난수 발생기)"],
    ["CORDIC", "곱셈기 없이 사인·코사인을 계산하는 회로"],
  ];
  const R = [
    ["용어", "뜻"],
    ["RTL / 기준모델 / bit-exact", "회로 설계 코드 / 소프트웨어 정답 모델 / 한 비트도 다르지 않음"],
    ["P&R · signoff", "배치배선 / 제조 직전 최종 타이밍·규칙 검사"],
    ["setup · hold 여유", "신호가 너무 늦지 않고(setup) 너무 빠르지 않은(hold) 시간 여유. 양수면 통과"],
    ["STA / SDF 게이트 시뮬", "계산으로 지연을 검사 / 실제 지연값을 넣은 회로 시뮬레이션"],
    ["LEC", "두 넷리스트가 논리적으로 같음을 증명하는 검사"],
    ["DRC · antenna", "제조 설계 규칙 검사 · 제조 중 전하 손상 규칙 검사"],
    ["클록 게이팅", "안 쓰는 부분의 클록을 꺼서 전력을 줄이는 기법 (ICG = 게이트 전용 셀)"],
    ["키프레임 / 프리즈", "기준이 되는 프레임(각도가 벌어지면 교체) / 다른 녹화의 상수를 그대로 고정"],
  ];
  table(s, L, 0.6, 1.5, 6.0, [2.0, 4.0], { size: 11, rowH: 0.62 });
  table(s, R, 6.75, 1.5, 5.95, [2.0, 3.95], { size: 11, rowH: 0.62 });
}

// ---------- 19. 장단점·한계·고려사항
{
  const s = content("장단점과 한계, 그리고 고려 사항",
    "정리하면 이 칩의 장점은 교수님 센서의 원본 데이터를 직접 받아 실제 영상에서 동작하고, 기준모델과 비트 단위로 같고, 배치배선과 signoff까지 닫혔다는 점입니다. 과적합은 피벗을 데이터에서 구하는 알고리즘으로 해결했습니다. 단점은 출하 클록이 8나노초로 물러났고, 느린 코너 시뮬이 5.5나노초에서 맞지 않는 이유를 규명하지 못했습니다. 고려할 점으로, 월드를 1024 곱하기 1024로 키우면 메모리가 지배하므로 SRAM이 필요하고, 전력은 활동도 기반 측정이 필요합니다.");
  card(s, 0.6, 1.55, 5.9, 2.7, "장점", "• 교수 센서 원본(group AER)을 칩이 직접 받음\n• 실제 roll 영상에서 0.47° (ECC 대비)\n• RTL = 기준모델, 풀칩 signoff·LEC·게이트 시뮬\n• 후보 60개를 측정으로 걸러낸 근거", { size: 14 });
  card(s, 6.8, 1.55, 5.9, 2.7, "단점·한계", "• 8 ns로 후퇴, 느린 코너 시뮬 원인 미규명\n• 시차가 강하고 성긴 장면과 UZH 3축에서 정확도 한계\n• 전력은 벡터 없는 값, DRC 전원선 10건", { size: 14, headColor: RED });
  card(s, 0.6, 4.45, 12.1, 2.45, "고려 사항: 목표 크기·구현으로 확장할 때", "• 월드를 1024×1024로 키우면 메모리가 면적을 지배한다 (FF 약 11.8 µm²/bit). SRAM 매크로가 필요한데 교육용 PDK에는 없다.\n• 일반화의 핵심은 녹화별 상수를 데이터에서 구하는 것이다: 자기보정 알고리즘으로 해결(합성 정답 검증, 정수 기준모델 확인).\n• 전력은 활동도 입력 기반(VCD) 측정으로 다시 잰다. 클록 여유를 5.5 ns 쪽으로 되돌리려면 느린 코너 시뮬 불일치 원인 규명이 먼저다.", { size: 14 });
}


// 발표 대본(10분)으로 노트 교체: notes_chipS.js
{
  const NOTES = require(path.join(__dirname, "notes_chipS.js"));
  pres._slides.forEach((sl, i) => {
    sl._slideObjects = sl._slideObjects.filter((o) => o._type !== "notes");
    if (NOTES[i]) sl.addNotes(NOTES[i]);
  });
}

pres.writeFile({ fileName: OUT }).then(() => console.log("wrote", OUT, "slides", pres.slides ? pres.slides.length : n));
