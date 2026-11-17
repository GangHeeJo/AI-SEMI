"""처음 보는 사람용 쉬운 설명 PDF (submission/준영현수.pdf)."""
from pathlib import Path
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (BaseDocTemplate, PageTemplate, Frame, Paragraph, Spacer, Image, Table, TableStyle,
                                PageBreak, KeepTogether)
from PIL import Image as PILImage

pdfmetrics.registerFont(TTFont("K", "C:/Windows/Fonts/malgun.ttf")); pdfmetrics.registerFont(TTFont("KB", "C:/Windows/Fonts/malgunbd.ttf"))
pdfmetrics.registerFontFamily("K", normal="K", bold="KB")
HERE = Path(__file__).resolve().parent; SUB = HERE.parent
FIG, EX = SUB / "figs", SUB / "figs_explain"
OUT = SUB / "준영현수.pdf"
BLUE, ORANGE, GREEN, GRAY, DARK = [colors.HexColor(c) for c in ("#1F5FA8", "#B85A1A", "#2E7255", "#6B7280", "#1F2937")]
LBLUE, LORANGE, LGREEN, LGRAY = [colors.HexColor(c) for c in ("#EAF1FA", "#FBEFE5", "#E8F3EC", "#F3F4F6")]
W, H = A4; M = 17 * mm; CW = W - 2 * M

S = dict(
    title=ParagraphStyle("t", fontName="KB", fontSize=21, leading=27, textColor=DARK, spaceAfter=3),
    tag=ParagraphStyle("tag", fontName="KB", fontSize=10, leading=13, textColor=BLUE, spaceAfter=2),
    body=ParagraphStyle("b", fontName="K", fontSize=10.8, leading=17, textColor=DARK, spaceAfter=5),
    small=ParagraphStyle("s", fontName="K", fontSize=9.2, leading=14, textColor=GRAY, alignment=1, spaceAfter=7),
    gl=ParagraphStyle("g", fontName="K", fontSize=9.6, leading=14.5, textColor=DARK),
    cell=ParagraphStyle("c", fontName="K", fontSize=9.8, leading=14.5, textColor=DARK),
    cellb=ParagraphStyle("cb", fontName="KB", fontSize=9.8, leading=14.5, textColor=DARK),
    big=ParagraphStyle("big", fontName="KB", fontSize=22, leading=26, textColor=BLUE, alignment=1),
    bigs=ParagraphStyle("bigs", fontName="K", fontSize=9.4, leading=13.5, textColor=DARK, alignment=1),
)


def P(t, st="body"): return Paragraph(t, S[st])


def img(path, width=CW, cap=None):
    w0, h0 = PILImage.open(path).size; hh = width * h0 / w0
    out = [Image(str(path), width=width, height=hh)]
    if cap: out.append(P(cap, "small"))
    else: out.append(Spacer(1, 4))
    return KeepTogether(out)


def gloss(items):
    rows = [[Paragraph(f"<b>{k}</b>", S["gl"]), Paragraph(v, S["gl"])] for k, v in items]
    t = Table(rows, colWidths=[30 * mm, CW - 30 * mm - 10 * mm])
    t.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), LGRAY), ("VALIGN", (0, 0), (-1, -1), "TOP"), ("LINEBELOW", (0, 0), (-1, -2), 0.3, colors.white),
                           ("LEFTPADDING", (0, 0), (-1, -1), 7), ("TOPPADDING", (0, 0), (-1, -1), 4), ("BOTTOMPADDING", (0, 0), (-1, -1), 4)]))
    head = Paragraph("<b>용어 풀이</b>", ParagraphStyle("gh", fontName="KB", fontSize=9.6, textColor=GRAY, spaceAfter=3, spaceBefore=6))
    return KeepTogether([head, t])


def stat_row(items):
    cells = [[P(v, "big"), P(l, "bigs")] for v, l in items]
    t = Table([[c[0] for c in cells], [c[1] for c in cells]], colWidths=[CW / len(items)] * len(items))
    t.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), LBLUE), ("BOX", (0, 0), (-1, -1), 0.8, BLUE), ("LINEAFTER", (0, 0), (-2, -1), 0.5, colors.white),
                           ("TOPPADDING", (0, 0), (-1, 0), 9), ("BOTTOMPADDING", (0, 1), (-1, 1), 9), ("VALIGN", (0, 0), (-1, -1), "MIDDLE")]))
    return t


def table(rows, widths, head=True):
    data = [[Paragraph(str(c), S["cellb"] if (head and i == 0) else S["cell"]) for c in r] for i, r in enumerate(rows)]
    t = Table(data, colWidths=widths, repeatRows=1)
    st = [("VALIGN", (0, 0), (-1, -1), "TOP"), ("GRID", (0, 0), (-1, -1), 0.4, colors.HexColor("#D1D5DB")),
          ("TOPPADDING", (0, 0), (-1, -1), 4), ("BOTTOMPADDING", (0, 0), (-1, -1), 4)]
    if head: st.append(("BACKGROUND", (0, 0), (-1, 0), LBLUE))
    t.setStyle(TableStyle(st)); return t


def page_deco(c, d):
    c.saveState(); c.setFont("KB", 8.5); c.setFillColor(GRAY)
    c.drawString(M, H - 11 * mm, "REDRED · 회전 카메라 월드 맵 칩"); c.drawRightString(W - M, 10 * mm, f"{d.page}")
    c.setStrokeColor(colors.HexColor("#D1D5DB")); c.line(M, H - 13 * mm, W - M, H - 13 * mm); c.restoreState()


def head(tag, title): return [P(tag, "tag"), P(title, "title"), Spacer(1, 3)]


st = []
# ---- 1 표지
st += [Spacer(1, 22 * mm), P("2026 전국 대학생 AI 반도체 회로 설계 경진대회 · Digital 트랙 · 팀 REDRED", "tag"),
       Paragraph("돌아가는 카메라 영상을<br/>하나의 지도로 만드는 칩", ParagraphStyle("ct", fontName="KB", fontSize=29, leading=38, textColor=DARK, spaceAfter=10)),
       P("처음 보는 분도 읽을 수 있게 쓴 설명서입니다. 무엇을 풀려고 했고, 어떻게 만들었고, 어디까지 확인했는지를 그림 중심으로 정리했습니다.", "body"),
       Spacer(1, 8 * mm),
       stat_row([("0.47°", "실제 영상에서<br/>회전각 평균 오차"), ("1 bit", "설계와 한 비트도<br/>다르지 않음"), ("8 ns", "풀칩 배치배선 후<br/>타이밍 통과")]),
       Spacer(1, 9 * mm), img(EX / "flow4.png", cap="전체 흐름: 센서 이벤트 → 회전각 추정 → 좌표 변환 → 월드 맵"),
       Spacer(1, 4 * mm),
       table([["목차"], ["1 문제와 목표 · 2 칩이 하는 일 · 3 월드 맵을 만드는 방법 · 4 시뮬레이션 결과 사진 · 5 회전각 정확도 · 6 회전 중심(피벗)과 자기보정 · 7 설계와 검증 · 8 우리의 특장점 · 9 현재 상태와 남은 과제"]], [CW]),
       PageBreak()]
# ---- 2 문제
st += head("1  문제와 목표", "카메라가 돌면 영상이 번진다")
st += [P("<b>이벤트 카메라</b>는 일반 카메라처럼 사진을 찍지 않고, 밝기가 <b>바뀐 픽셀만</b> 그 주소를 계속 알려 줍니다. 그래서 아주 빠르게 움직이는 장면도 놓치지 않습니다. 대신 카메라가 돌면 같은 물체가 센서의 다른 픽셀에서 반응해, 점들을 그냥 쌓으면 아래 왼쪽처럼 소용돌이로 번집니다."),
       img(FIG / "raw_frames_roll.png", cap="실제 roll 녹화(회전) 원본 이벤트 프레임. 시간이 지나면서 같은 방이 돌아가며 보인다."),
       img(EX / "swirl.png"),
       P("<b>목표</b>: 센서 이벤트를 받아, 회전을 되돌린 <b>월드 맵</b>(카메라가 어디를 보든 같은 물체가 같은 자리에 쌓이는 지도)을 <b>칩 한 개</b>로 만든다. 대회 조건에 따라 회전은 180° 이내, 평행 이동은 없다고 가정한다."),
       gloss([("이벤트", "밝기가 변한 픽셀 하나의 신호(위치·시각·밝아졌나 어두워졌나)."), ("월드 맵", "카메라 움직임을 지운 고정된 지도."), ("roll / pan", "카메라가 제자리에서 돌아가는 녹화(roll), 옆으로 훑는 녹화(pan).")]),
       PageBreak()]
# ---- 3 칩 구조
st += head("2  칩이 하는 일", "이벤트마다 네 단계를 거친다")
st += [P("센서가 보낸 신호를 받자마자 아래 순서로 처리합니다. 파란색은 이벤트마다 도는 쓰기 경로, 주황색은 회전각을 구하는 부분입니다. 회전각 계산과 좌표 변환이 <b>같은 칩 안</b>에 있어서 바깥에서 각도를 따로 넣어 줄 필요가 없습니다."),
       img(FIG / "chipS_arch.png", cap="칩 내부 구조. ①디코더 ②픽셀을 추정기로도 전달 ③회전각 추정과 cos·sin 계산 ④좌표 변환 ⑤메모리에 쓰기"),
       table([["단계", "하는 일", "쉬운 설명"],
              ["디코더", "센서 워드 → 픽셀 주소", "센서는 픽셀 최대 16개를 한 묶음으로 보낸다. 이를 하나씩 풀어 준다."],
              ["자세 추정기", "1비트 지도로 회전각 계산", "직전 프레임과 지금 프레임을 비교해 '몇 도 돌았나'를 정수 연산만으로 찾는다."],
              ["좌표 변환", "픽셀 → 월드 좌표", "돌아간 각도만큼 되돌린 위치를 계산한다. 곱셈기 없이 덧셈으로 하는 방식을 쓴다."],
              ["월드 메모리", "같은 칸에 횟수 쌓기", "같은 자리에 많이 찍힌 곳이 곧 물체의 윤곽이 된다."]], [26 * mm, 42 * mm, CW - 68 * mm]),
       gloss([("AER", "이벤트를 '주소'로 전달하는 센서 통신 방식."), ("CORDIC", "곱셈기 없이 각도에서 cos·sin 값을 구하는 계산 방법."), ("프레임", "센서가 이벤트를 묶어 보내는 시간 단위(실측 773 µs).")]),
       PageBreak()]
# ---- 4 월드 맵 구현
st += head("3  월드 맵을 만드는 방법", "작은 칸에 '얼마나 자주 찍혔나'를 센다")
st += [P("월드 맵은 영상이 아니라 <b>횟수 표</b>입니다. 월드 좌표로 옮긴 점이 어느 칸에 떨어지는지 보고 그 칸의 카운터를 올립니다. 칸 하나는 픽셀 8×8개이고, 칸마다 4비트만 씁니다. 4비트는 15까지밖에 못 세므로 <b>로그 카운터</b>(확률적으로 올려 큰 수를 흉내 냄)를 씁니다."),
       img(EX / "worldmem.png"),
       P("메모리는 하드 메모리 뱅크 16개로 나누고, <b>지금 쓰는 행만 클록을 켭니다</b>. 실제 활동도에서 이 방식으로 메모리 전력이 약 65% 줄었습니다. 아래는 실제 녹화로 뱅크마다 몇 칸이 쓰였는지, 카운터 값이 어떻게 퍼지는지 본 것입니다."),
       img(FIG / "chip_bank_hist.png", cap="roll(왼쪽)은 중앙 뱅크, pan(가운데)은 거의 전 뱅크를 고르게 쓴다. 오른쪽은 카운터 값 분포."),
       gloss([("클록 게이팅", "일하지 않는 회로에는 박자(클록)를 끊어 전력을 아끼는 기술."), ("뱅크", "큰 메모리를 나눈 조각. 필요한 조각만 깨운다."), ("로그 카운터", "작은 비트로 큰 수를 세는 방식. 정확한 횟수 대신 대략의 크기를 기록.")]),
       PageBreak()]
# ---- 5 시뮬 사진 1
st += head("4  시뮬레이션 결과 사진", "칩 설계(RTL)를 시뮬레이터로 돌려 얻은 월드 맵")
st += [P("아래 사진의 오른쪽은 <b>칩의 회로 설계를 그대로 시뮬레이션</b>해서 월드 메모리에 실제로 쓰인 값을 그린 것입니다. 왼쪽은 아무 보정 없이 센서 좌표에 쌓은 결과입니다."),
       img(FIG / "chip_roll_world.png", cap="roll 32프레임. 왼쪽 보정 없음(소용돌이) / 가운데·오른쪽 칩 출력: 방의 구조가 보인다."),
       img(FIG / "chip_map_growth.png", cap="프레임이 쌓일수록 지도가 선명해지고 넓어진다(2 → 32프레임, 1.5 ms → 24.7 ms)."),
       img(FIG / "chip_pan_world.png", cap="pan 64프레임. 왼쪽 보정 없음 / 오른쪽 칩 출력 월드 메모리."),
       PageBreak()]
# ---- 6 시뮬 사진 2
st += head("4  시뮬레이션 결과 사진 (이어서)", "파노라마와 월드 메모리에 쓰인 값")
st += [img(FIG / "panorama_pan.png", cap="pan 녹화를 이어 붙인 파노라마(소프트웨어 기준 모델). 카메라가 훑은 넓은 장면이 하나로 이어진다."),
       img(FIG / "worldmem_rtl.png", width=CW * 0.52, cap="칩 RTL이 월드 메모리에 쓴 칸(64×64 확대). 파랑 = 밝아진 이벤트, 회색 = 어두워진 이벤트."),
       table([["지표", "보정 전", "칩 출력", "설명"],
              ["roll 응집도", "1.06", "2.34", "지도가 얼마나 선명하게 모였는지 나타내는 수. 클수록 선명."],
              ["pan 응집도", "1.16", "2.76", "같은 기준."]], [28 * mm, 20 * mm, 22 * mm, CW - 70 * mm]),
       Spacer(1, 3),
       gloss([("응집도", "같은 물체의 점이 한곳에 얼마나 모였는지를 재는 수치(우리가 정한 기준)."), ("RTL 시뮬레이션", "회로 설계 코드를 컴퓨터에서 동작시켜 보는 것. 실제 칩 제조 전의 확인 단계.")]),
       PageBreak()]
# ---- 7 정확도
st += head("5  회전각 정확도", "정답과 거의 겹친다")
st += [P("정답이 따로 없어서, 연속된 두 영상을 겹쳐 맞추는 <b>ECC 정합</b>으로 구한 각도를 정답 대용으로 썼습니다. 5초짜리 roll 녹화에서 칩이 구한 각도(점선)와 정답(주황)이 거의 겹치고, 오차는 평균 0.47°, 최대 1.7°입니다. 5초 동안 약 320° 돈 영상입니다."),
       img(FIG / "chip_theta_vs_ecc.png", cap="왼쪽: 누적 회전각. 오른쪽: 칩과 정답의 차이."),
       img(FIG / "hs_C5b_err_hist.png", cap="오차 분포. roll은 각도(°), pan은 픽셀. 대부분 작은 오차에 몰려 있다."),
       gloss([("ECC 정합", "두 영상을 가장 잘 포개지는 회전·이동을 찾는 방법. 정답 대용."), ("누적 회전각", "시작부터 지금까지 돈 총 각도.")]),
       PageBreak()]
# ---- 8 피벗
st += head("6  회전 중심(피벗)과 자기보정", "칩이 스스로 회전 중심을 찾는다")
st += [P("우리 센서는 막대 끝에 달려 있어 센서 한가운데가 아닌 <b>다른 점(피벗)</b> 둘레로 돕니다. 피벗이 어디인지 알아야 좌표를 정확히 되돌릴 수 있습니다."),
       img(EX / "pivot.png"),
       P("처음에는 피벗 위치를 칩에 <b>상수</b>로 넣었습니다. 그런데 다른 녹화에서는 각도 오차가 0.67°에서 <b>61°</b>까지 커졌습니다(특정 녹화에 맞춰진 과적합). 그래서 상수 대신 <b>데이터에서 피벗을 구하는 알고리즘</b>을 만들었습니다."),
       img(EX / "selfcal.png", cap="자기보정 절차: 처음 몇 구간에서 이동량까지 추정해 피벗을 직선 맞춤으로 구하고, 설명력이 충분하면 고정한다."),
       P("정답을 아는 합성 장면으로 독립 검증하면, 피벗이 멀리 있을 때 상수로 고정한 방식은 오차가 116°였고 이 알고리즘은 1.7°였습니다(소프트웨어 기준)."),
       gloss([("피벗", "카메라가 도는 중심점."), ("과적합", "특정 녹화에만 맞춰 놓아서 다른 영상에서는 틀리는 문제."), ("최소제곱", "여러 측정값에 가장 가까운 직선을 찾는 방법.")]),
       PageBreak()]
# ---- 9 설계·검증
st += head("7  설계와 검증", "만들고, 배치하고, 여러 방법으로 확인했다")
st += [img(EX / "verify.png", cap="설계 흐름과 확인 단계(교육용 45 nm 공정 라이브러리 사용)."),
       table([["확인 항목", "결과", "쉬운 설명"],
              ["기준모델 비교", "불일치 0", "소프트웨어 정답 모델과 회로의 출력이 한 비트도 다르지 않다."],
              ["타이밍 signoff(8 ns)", "setup +2.4 ns, hold +7 ps, 위반 0", "신호가 너무 늦거나 빠르지 않은 시간 여유(양수면 통과)."],
              ["LEC", "비교점 14,618개, 불일치 0", "설계 코드와 배치 후 회로가 논리적으로 같은지 비교."],
              ["게이트 시뮬", "roll MIN 통과", "실제 지연값을 넣고 다시 돌려 본 확인."],
              ["처리 속도", "프레임당 0.715 ms (여유 0.773 ms)", "센서가 프레임을 보내는 속도보다 약간 빠르다. 여유는 크지 않다."]], [34 * mm, 46 * mm, CW - 80 * mm]),
       Spacer(1, 4), img(FIG / "pnr_layout.png", width=CW * 0.52, cap="배치배선이 끝난 칩 내부(합성된 논리 회로)."),
       P("전력은 13.0 mW이지만, 실제 동작 활동 정보 없이 기본 가정으로 잰 값이라 참고용입니다. 클록 5.5 ns를 시도했으나 실제 지연 시뮬레이션이 맞지 않아 8 ns로 정했습니다."),
       gloss([("배치배선", "회로 부품을 칩 위에 놓고 선으로 잇는 과정."), ("signoff", "제조 직전에 하는 최종 검사."), ("setup / hold", "신호가 박자에 맞춰 도착하는지 보는 두 가지 시간 조건.")]),
       PageBreak()]
# ---- 10 특장점
st += head("8  우리의 특장점", "여섯 가지")
cards = [("센서 원본을 직접 받는다", "센서가 보내는 워드를 칩이 직접 풀어 쓴다. 중간 변환 장치가 필요 없다."),
         ("각도 계산이 칩 안에 있다", "회전각 추정과 좌표 변환이 한 칩에서 돌아 바깥 각도 입력이 필요 없다."),
         ("설계와 비트 단위로 같다", "RTL이 기준모델과 한 비트도 다르지 않고, signoff·LEC·게이트 시뮬까지 닫았다."),
         ("실제 영상에서 0.47°", "5초 roll 녹화에서 정답 대비 평균 0.47°, 파노라마·외부 데이터도 확인."),
         ("전력을 아끼는 메모리", "쓰는 행만 클록을 켜서 메모리 전력 약 65% 절감, 4비트 로그 카운터로 면적 절감."),
         ("측정으로 고른 설계", "후보 약 60개를 같은 조건에서 재서 골랐다. 예: 곱셈기 없는 변환은 면적 0.44배, 전력 0.39배.")]
rows = []
for i in range(0, 6, 2):
    rows.append([[Paragraph(f"<b>{cards[i][0]}</b>", S["cellb"]), Paragraph(cards[i][1], S["cell"])],
                 [Paragraph(f"<b>{cards[i + 1][0]}</b>", S["cellb"]), Paragraph(cards[i + 1][1], S["cell"])]])
t = Table(rows, colWidths=[CW / 2] * 2, rowHeights=[28 * mm] * 3)
t.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), LBLUE), ("BOX", (0, 0), (-1, -1), 0.8, BLUE), ("INNERGRID", (0, 0), (-1, -1), 1.5, colors.white),
                       ("VALIGN", (0, 0), (-1, -1), "TOP"), ("LEFTPADDING", (0, 0), (-1, -1), 9), ("TOPPADDING", (0, 0), (-1, -1), 8)]))
st += [t, Spacer(1, 6 * mm),
       P("<b>쉬운 한 줄 요약</b>: 센서가 보낸 이벤트로 카메라가 몇 도 돌았는지 스스로 계산하고, 그만큼 되돌려 하나의 지도에 쌓는 것까지를 칩 한 개로 만들었고, 설계부터 최종 타이밍 검사까지 확인했다."),
       PageBreak()]
# ---- 11 현재 상태
st += head("9  현재 상태와 남은 과제", "자기보정을 칩에 넣는 작업은 진행 중")
st += [P("대회에 제출한 칩은 피벗을 <b>설정값</b>으로 받습니다. 자기보정 알고리즘(피벗을 데이터에서 구하기)은 소프트웨어에서 검증을 마쳤고, 이를 칩 회로에 직접 넣은 <b>새 칩</b>을 추가로 만들어 같은 흐름으로 확인하고 있습니다."),
       table([["", "제출한 칩", "자기보정 포함 새 칩"],
              ["피벗", "설정값으로 입력(녹화마다 맞춰야 함)", "칩이 745프레임 동안 스스로 계산해 공표"],
              ["회로 확인", "RTL·배치배선·signoff·LEC·게이트 시뮬 완료", "RTL 25개 시험, 배치배선, signoff, LEC 완료. 게이트 시뮬 roll 통과, 추가 케이스 서버에서 진행 중"],
              ["회전각 정확도", "평균 0.47°", "아직 개선 전. 칩이 구한 피벗이 기준 중심에서 어긋나 0.76°"],
              ["물리 상태", "DRC 전원선 10건", "DRC 11, 일부 신호 전이시간·글리치 위반 남음"]], [26 * mm, 62 * mm, CW - 88 * mm]),
       Spacer(1, 5),
       P("<b>남은 문제</b>: 새 칩의 피벗이 소프트웨어 결과보다 약 20~30 픽셀 어긋납니다. 각도 정확도, 적합 규칙, 탐색 간격, 키프레임 비중, 단일·다중 깊이 합성 장면까지 하나씩 확인했지만 아직 원인을 찾지 못했습니다. 소프트웨어 알고리즘 자체는 실제 영상에서 독립 측정과 일치했고, 같은 칩 구현이 합성 장면에서는 수 픽셀 안으로 정확하므로, 실제 영상의 특성과 관련된 원인을 더 확인할 계획입니다."),
       P("<b>다음 단계</b>: ① 같은 실제 영상 관측을 소프트웨어 추정기와 칩 추정기에 똑같이 넣어 어디서 갈라지는지 비교 ② 물리 위반 정리를 위한 재배치배선 ③ 추가 게이트 시뮬 결과 반영."),
       gloss([("공표", "칩이 계산한 피벗을 확정해 바깥에 알리는 신호."), ("DRC", "제조 규칙(선 간격 등)을 어기지 않았는지 보는 검사.")]),
       ]
doc = BaseDocTemplate(str(OUT), pagesize=A4, leftMargin=M, rightMargin=M, topMargin=18 * mm, bottomMargin=16 * mm,
                      title="REDRED 쉬운 설명서", author="REDRED")
doc.addPageTemplates([PageTemplate(id="p", frames=[Frame(M, 16 * mm, CW, H - 34 * mm, id="f", leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)], onPage=page_deco)])
doc.build(st); print("saved", OUT)
