"""pptxgenjs 출력 후처리. usage: post.py in.pptx out.pptx
 - 글꼴: 이 PC(및 사용자 PowerPoint)에서 실제로 인식되는 이름은 굵기별 가족명 "나눔스퀘어 네오 Regular"/"... Bold"뿐이다
   ("나눔스퀘어 네오", "NanumSquare Neo" 단독 이름은 맑은 고딕으로 대체됨 -- 직접 렌더링으로 확인).
   그래서 일반 글자는 Regular, 굵은 글자(b="1")는 Bold 가족으로 바꾸고 b 속성은 뺀다(이중 굵기 방지).
 - 한글(a:ea)/cs도 같은 글꼴, 테마 글꼴도 Regular
 - 문단 eaLnBrk="0"
"""
import re
import sys
import zipfile

REG = "나눔스퀘어 네오 Regular"
BOLD = "나눔스퀘어 네오 Bold"
src, dst = sys.argv[1:3]
zin = zipfile.ZipFile(src)
zout = zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED)
n = {"p": 0, "bold": 0, "ea": 0, "theme": 0}


def ensure_ea(inner, face):
    """latin 뒤에 ea/cs가 없으면 추가."""
    if "<a:latin" in inner and "<a:ea " not in inner:
        n["ea"] += 1
        inner = re.sub(r"(<a:latin [^>]*/>)", r'\1<a:ea typeface="%s"/>' % face, inner, count=1)
    if "<a:latin" in inner and "<a:cs " not in inner:
        inner = re.sub(r"(<a:ea [^>]*/>)", r'\1<a:cs typeface="%s"/>' % face, inner, count=1)
    return inner


def fix_rpr(m):
    tag, attrs, body = m.group(1), m.group(2), m.group(3)
    face = REG
    if re.search(r'\bb="1"', attrs):
        attrs = re.sub(r'\s+b="1"', "", attrs)
        face = BOLD
        n["bold"] += 1
    if "<a:latin" not in body:
        return "<a:%s%s>%s</a:%s>" % (tag, attrs, body, tag)
    body = re.sub(r'typeface="[^"]*"', 'typeface="%s"' % face, body)
    body = ensure_ea(body, face)
    return "<a:%s%s>%s</a:%s>" % (tag, attrs, body, tag)


RPR = re.compile(r"<a:(rPr|defRPr)((?:\s+[\w:]+=\"[^\"]*\")*)\s*>(.*?)</a:\1>", re.S)


def process_runs(x):
    return RPR.sub(fix_rpr, x)


for item in zin.infolist():
    data = zin.read(item.filename)
    name = item.filename
    if re.match(r"ppt/slides/slide\d+\.xml$", name):
        x = data.decode("utf-8")

        def fixp(m):
            tag = m.group(0)
            if "eaLnBrk" in tag:
                return tag
            n["p"] += 1
            return tag.replace("<a:pPr", '<a:pPr eaLnBrk="0"', 1)
        x = re.sub(r"<a:pPr(?=[ >/])[^>]*>", fixp, x)
        data = process_runs(x).encode("utf-8")
    elif re.match(r"ppt/(charts/chart\d+|slideMasters/slideMaster\d+|slideLayouts/slideLayout\d+|notesSlides/notesSlide\d+)\.xml$", name):
        data = process_runs(data.decode("utf-8")).encode("utf-8")
    elif re.match(r"ppt/theme/theme\d+\.xml$", name):
        x = data.decode("utf-8")
        for tag in ("majorFont", "minorFont"):
            x, k = re.subn(r"(<a:%s>\s*<a:latin typeface=\")[^\"]*(\")" % tag, r"\1%s\2" % REG, x)
            n["theme"] += k
            x, k = re.subn(r"(<a:%s>.*?<a:ea typeface=\")[^\"]*(\")" % tag, r"\1%s\2" % REG, x, flags=re.S)
            n["theme"] += k
        x = re.sub(r'(<a:font script="Hang" typeface=")[^"]*(")', r"\1%s\2" % REG, x)   # 한글 스크립트 글꼴(기본 맑은 고딕)
        x = re.sub(r'(<a:cs typeface=")(")', r"\1%s\2" % REG, x)
        data = x.encode("utf-8")
    zout.writestr(item, data)
zout.close()
print("patched:", n)
