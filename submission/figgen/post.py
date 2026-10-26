"""pptxgenjs 출력 후처리: 모든 문단에 eaLnBrk="0"(한글을 글자 중간이 아니라 단어(공백) 단위로 줄바꿈). usage: post.py in.pptx out.pptx"""
import re
import sys
import zipfile

src, dst = sys.argv[1:3]
zin = zipfile.ZipFile(src)
zout = zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED)
n = 0
for item in zin.infolist():
    data = zin.read(item.filename)
    if re.match(r"ppt/slides/slide\d+\.xml$", item.filename):
        x = data.decode("utf-8")

        def fix(m):
            global n
            tag = m.group(0)
            if "eaLnBrk" in tag:
                return tag
            n += 1
            return tag.replace("<a:pPr", '<a:pPr eaLnBrk="0"', 1)
        x = re.sub(r"<a:pPr(?=[ >/])[^>]*>", fix, x)
        data = x.encode("utf-8")
    zout.writestr(item, data)
zout.close()
print("patched pPr:", n)
