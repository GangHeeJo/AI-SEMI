"""pptxgenjs 출력 후처리. usage: post.py in.pptx out.pptx
 1) 문단 eaLnBrk="0" (한글 단어 단위 줄바꿈)  2) 한글(East Asian) 글꼴을 라틴과 같은 NanumSquare Neo로 지정(a:ea) -- 기본은 맑은 고딕으로 빠짐
 3) 테마 글꼴(major/minor)의 ea/cs도 NanumSquare Neo"""
import re
import sys
import zipfile

FONT = "NanumSquare Neo"
import os
LATIN = os.environ.get("LATIN_FONT")  # 지정하면 라틴/숫자만 이 글꼴로(한글은 NanumSquare Neo 유지)
src, dst = sys.argv[1:3]
zin = zipfile.ZipFile(src)
zout = zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED)
n = {"p": 0, "ea": 0, "theme": 0}


def add_ea(x):
    def fix(m):
        tag = m.group(0)
        n["ea"] += 1
        return tag + f'<a:ea typeface="{FONT}"/>'
    # latin 바로 뒤에 ea가 없으면 추가
    return re.sub(r'<a:latin typeface="' + re.escape(FONT) + r'"[^>]*/>(?!<a:ea)', fix, x)


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
        data = add_ea(x).encode("utf-8")
    elif re.match(r"ppt/(charts/chart\d+|slideMasters/slideMaster\d+|slideLayouts/slideLayout\d+|notesSlides/notesSlide\d+)\.xml$", name):
        data = add_ea(data.decode("utf-8")).encode("utf-8")
    elif re.match(r"ppt/theme/theme\d+\.xml$", name):
        x = data.decode("utf-8")
        for tag in ("majorFont", "minorFont"):
            x, k = re.subn(r"(<a:%s>.*?)<a:ea typeface=\"[^\"]*\"\s*/>" % tag, r'\1<a:ea typeface="%s"/>' % FONT, x, flags=re.S)
            n["theme"] += k
        data = x.encode("utf-8")
    if LATIN and name.endswith(".xml") and name.startswith("ppt/") and b'typeface="NanumSquare Neo"' in data:
        data = data.replace(b'<a:latin typeface="NanumSquare Neo"', ('<a:latin typeface="%s"' % LATIN).encode("utf-8"))
    zout.writestr(item, data)
zout.close()
print("patched:", n)
