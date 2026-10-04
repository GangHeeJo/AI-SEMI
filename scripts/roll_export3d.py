#!/usr/bin/env python3
# §189: 상대 3D 점(u,v,s)을 마우스로 돌려 볼 수 있는 HTML 뷰어(three.js, 자체 궤도 조작)와 두 각도 정지 이미지로 내보낸다.
# 점 = 2px 격자 칸마다 (u,v) 중심 + 평균 s, 색 = 상대 깊이(turbo), 밝기 = log 이벤트 수. 깊이 축 눈금은 교정값이 없어 슬라이더로 조절.
# 사용: roll_export3d.py <events.h5> <theta.npy> <calib.json> <diag_prefix> <out_prefix> [max_points]   (DELTA_RHO 환경변수는 해당 실행과 동일하게)
import base64
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

from roll_relative3d import load, uv

h5p, th, cal, diag, out = sys.argv[1:6]; MAXP = int(sys.argv[6]) if len(sys.argv) > 6 else 350000
x, y, a, s, fl, e, c0, tol, C = load(h5p, th, cal, diag); ag = (fl == 1) & np.isfinite(s); x, y, a, s = x[ag], y[ag], a[ag], s[ag]; u, v = uv(x, y, a, s, e, c0)
BIN = 2; gx = np.floor((u - u.min()) / BIN).astype(np.int64); gy = np.floor((v - v.min()) / BIN).astype(np.int64); W = gx.max() + 1; key = gy * W + gx
N = np.bincount(key); S = np.bincount(key, weights=s, minlength=len(N)); occ = np.nonzero(N >= 3)[0]; occ = occ[np.argsort(N[occ])[::-1][:MAXP]]
sm = S[occ] / N[occ]; pu = (occ % W) * BIN + u.min(); pv = (occ // W) * BIN + v.min(); lo, hi = np.percentile(sm, [2, 98]); keep = (sm >= lo - 0.3 * (hi - lo)) & (sm <= hi + 0.3 * (hi - lo))
pu, pv, sm, nn = pu[keep], pv[keep], sm[keep], N[occ][keep]; pu -= np.median(pu); pv = -(pv - np.median(pv)); depth = np.clip((sm - lo) / (hi - lo + 1e-6), 0, 1)
rgb = (plt.cm.turbo(depth)[:, :3] * np.clip(np.log1p(nn) / np.log1p(np.percentile(nn, 99.5)), 0.2, 1)[:, None] * 255).astype(np.uint8)
print(f"points {len(pu)}  u,v extent {np.ptp(pu):.0f} x {np.ptp(pv):.0f} px, s range {lo:.0f}..{hi:.0f} px")
def two_views(path):
    fig, ax = plt.subplots(1, 2, figsize=(22, 9))
    for k, ang in enumerate((-35, 35)):
        r = np.radians(ang); X = pu * np.cos(r) + (sm - np.median(sm)) * 2.0 * np.sin(r); ax[k].scatter(X, pv, c=rgb / 255.0, s=0.3, marker="."); ax[k].set_aspect("equal"); ax[k].axis("off"); ax[k].set_title(f"view rotated {ang:+d} deg about the vertical axis (depth scale x2)", fontsize=12)
    plt.tight_layout(); plt.savefig(path, dpi=45); plt.close()
two_views(out + "_views.png")
P = np.stack([pu, pv, (sm - np.median(sm))], 1); Pq = np.round(P * 8).astype(np.int16)
html = """<!doctype html><html><head><meta charset="utf-8"><title>Relative 3D world map</title><style>body{margin:0;background:#0b0b0e;color:#ddd;font:13px sans-serif;overflow:hidden}#ui{position:fixed;left:12px;top:10px;background:#000a;padding:8px 12px;border-radius:6px}label{display:block;margin:4px 0}input{width:220px}</style></head><body>
<div id="ui"><b>Relative 3D world map</b> (depth axis is relative; scale unknown)<label>depth scale <input id="zs" type="range" min="0" max="10" step="0.1" value="2"></label><label>point size <input id="ps" type="range" min="0.5" max="4" step="0.1" value="1.5"></label><div>drag = rotate, wheel = zoom, shift+drag = pan. Color: blue = far end, red = near end of the relative depth axis.</div></div>
<script src="https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js"></script><script>
const b64=(s)=>Uint8Array.from(atob(s),c=>c.charCodeAt(0)).buffer;
const pos=new Int16Array(b64("__POS__")),col=new Uint8Array(b64("__COL__")),n=col.length/3;
const scene=new THREE.Scene(),cam=new THREE.PerspectiveCamera(50,innerWidth/innerHeight,1,20000),ren=new THREE.WebGLRenderer({antialias:true});ren.setSize(innerWidth,innerHeight);document.body.appendChild(ren.domElement);
const g=new THREE.BufferGeometry(),p=new Float32Array(n*3),c=new Float32Array(n*3);for(let i=0;i<n;i++){p[3*i]=pos[3*i]/8;p[3*i+1]=pos[3*i+1]/8;p[3*i+2]=pos[3*i+2]/8;c[3*i]=col[3*i]/255;c[3*i+1]=col[3*i+1]/255;c[3*i+2]=col[3*i+2]/255}
g.setAttribute('position',new THREE.BufferAttribute(p,3));g.setAttribute('color',new THREE.BufferAttribute(c,3));
const m=new THREE.PointsMaterial({size:1.5,vertexColors:true,sizeAttenuation:false}),pts=new THREE.Points(g,m),grp=new THREE.Group();grp.add(pts);scene.add(grp);
let rx=0.0,ry=0.0,dist=1500,pan=new THREE.Vector3();const up=()=>{pts.scale.z=parseFloat(document.getElementById('zs').value);m.size=parseFloat(document.getElementById('ps').value);grp.rotation.set(rx,ry,0,'YXZ');grp.position.copy(pan);cam.position.set(0,0,dist);cam.lookAt(0,0,0);ren.render(scene,cam)};
document.getElementById('zs').oninput=up;document.getElementById('ps').oninput=up;let dr=false,sh=false,lx=0,ly=0;
ren.domElement.onmousedown=e=>{dr=true;sh=e.shiftKey;lx=e.clientX;ly=e.clientY};onmouseup=()=>dr=false;onmousemove=e=>{if(!dr)return;const dx=e.clientX-lx,dy=e.clientY-ly;lx=e.clientX;ly=e.clientY;if(sh){pan.x+=dx;pan.y-=dy}else{ry+=dx*0.005;rx+=dy*0.005}up()};
ren.domElement.onwheel=e=>{dist*=e.deltaY>0?1.08:0.92;e.preventDefault();up()};onresize=()=>{cam.aspect=innerWidth/innerHeight;cam.updateProjectionMatrix();ren.setSize(innerWidth,innerHeight);up()};up();
</script></body></html>"""
html = html.replace("__POS__", base64.b64encode(Pq.tobytes()).decode()).replace("__COL__", base64.b64encode(rgb.tobytes()).decode())
open(out + ".html", "w", encoding="utf-8").write(html); print("html", len(html) / 1e6, "MB ->", out + ".html")
