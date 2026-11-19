import sys, numpy as np, cv2
from PIL import Image, ImageDraw, ImageFont
from matplotlib import cm

src, dst = sys.argv[1], sys.argv[2]
title = sys.argv[3] if len(sys.argv) > 3 else "칩 S가 월드 지도를 쌓는 과정"
z = np.load(src)
world, sens, ks, ang = z['world'], z['sensor'], z['k'], z['ang']
th = np.degrees(np.unwrap(np.radians(ang)))
if abs(th[-1]) < abs(th.min()): th = -th
th = th * np.sign(th[-1] if th[-1] != 0 else 1)
FPS = 30; Wd, Ht = 1280, 720
bg = (24, 26, 34)
fb = ImageFont.truetype("C:/Windows/Fonts/malgunbd.ttf", 30)
fm = ImageFont.truetype("C:/Windows/Fonts/malgunbd.ttf", 22)
fs = ImageFont.truetype("C:/Windows/Fonts/malgun.ttf", 19)
lut = (cm.magma(np.arange(256))[:, :3] * 255).astype(np.uint8)
lut[0] = (14, 15, 24)

_fin = world[-1].astype(np.float32); _m = _fin > 0
LO, HI = np.percentile(_fin[_m], 20), np.percentile(_fin[_m], 99.7)
gray_lut = (cm.gray(np.arange(256))[:, :3] * 255).astype(np.uint8)

def world_img(w):
    wf = w.astype(np.float32); msk = wf > 0
    x = np.clip((cv2.GaussianBlur(wf, (0, 0), 0.8) - LO) / (HI - LO), 0, 1) ** 1.8
    rgb = gray_lut[(x * 255).astype(np.uint8)]; rgb[~msk] = (14, 15, 24)
    return cv2.resize(rgb, None, fx=3, fy=3, interpolation=cv2.INTER_CUBIC)

def sens_img(s):
    nz = s[s > 0]; sc = 255.0 / max(float(np.percentile(nz, 97)) if nz.size else 1.0, 2.0)
    a = np.minimum(s.astype(np.float32) * sc, 255).astype(np.uint8)
    rgb = np.stack([a, a, a], -1); rgb[a == 0] = (14, 15, 24)
    return cv2.resize(rgb, None, fx=2.5, fy=2.5, interpolation=cv2.INTER_NEAREST)

vw = cv2.VideoWriter(dst, cv2.VideoWriter_fourcc(*'mp4v'), FPS, (Wd, Ht))
n = len(ks)
for i in range(n + 2 * FPS):
    j = min(i, n - 1)
    cv = np.zeros((Ht, Wd, 3), np.uint8); cv[:] = bg
    a = sens_img(sens[j]); b = world_img(world[j])
    ya = 120; xa = 40; cv[ya:ya + a.shape[0], xa:xa + a.shape[1]] = a
    yb = 110; xb = 700; cv[yb:yb + b.shape[0], xb:xb + b.shape[1]] = b
    pil = Image.fromarray(cv); d = ImageDraw.Draw(pil)
    d.text((40, 22), title, font=fb, fill=(240, 240, 245))
    d.text((xa, 90), "① 센서가 보는 화면 (최근 4프레임의 이벤트)", font=fm, fill=(180, 200, 255))
    d.text((xb, 78), "② 칩이 쌓은 월드 지도 (밝을수록 많이 쌓임)", font=fm, fill=(255, 190, 140))
    d.text((xa, 120 + a.shape[0] + 12), "카메라가 돌면서 같은 물체가 계속 다른 자리에 찍힘", font=fs, fill=(170, 175, 190))
    d.text((xa, 120 + a.shape[0] + 40), "→ 각도를 추정해 되돌린 뒤 오른쪽 지도에 쌓음", font=fs, fill=(170, 175, 190))
    d.text((700, 678), "※ 지도는 보기 좋게 약간 부드럽게 표시", font=fs, fill=(150, 155, 170))
    t_ms = ks[j] * 0.773
    d.text((40, 672), f"{t_ms:6.0f} ms   ·   프레임 {ks[j]}   ·   누적 회전 약 {abs(th[j]):.0f}°", font=fm, fill=(240, 240, 245))
    pw = 1200 * (j + 1) / n
    d.rectangle((40, 660, 40 + pw, 666), fill=(255, 150, 90)); d.rectangle((40 + pw, 660, 1240, 666), fill=(60, 64, 78))
    vw.write(cv2.cvtColor(np.array(pil), cv2.COLOR_RGB2BGR))
vw.release()
print('written', dst, n, 'snapshots', round((n + 2 * FPS) / FPS, 1), 's', 'theta end', th[-1])
