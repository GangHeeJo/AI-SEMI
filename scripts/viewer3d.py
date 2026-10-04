#!/usr/bin/env python3
# 상대 3D 점 구름 뷰어 공용 모듈: 이벤트별 (u,v,깊이)에서 2px 격자 점을 만들고 HTML(three.js 자체 궤도 조작) + 두 각도 정지 이미지를 쓴다.
import base64

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np


def write_viewer(u, v, d, out, title, depth_label, maxp=350000, bin_px=2, min_n=3):
    gx = np.floor((u - u.min()) / bin_px).astype(np.int64); gy = np.floor((v - v.min()) / bin_px).astype(np.int64); W = gx.max() + 1; key = gy * W + gx
    N = np.bincount(key); S = np.bincount(key, weights=d, minlength=len(N)); occ = np.nonzero(N >= min_n)[0]; occ = occ[np.argsort(N[occ])[::-1][:maxp]]
    sm = S[occ] / N[occ]; pu = (occ % W) * bin_px + u.min(); pv = (occ // W) * bin_px + v.min(); lo, hi = np.percentile(sm, [2, 98]); keep = (sm >= lo - 0.3 * (hi - lo)) & (sm <= hi + 0.3 * (hi - lo))
    pu, pv, sm, nn = pu[keep], pv[keep], sm[keep], N[occ][keep]; pu -= np.median(pu); pv = -(pv - np.median(pv)); depth = np.clip((sm - lo) / (hi - lo + 1e-6), 0, 1)
    rgb = (plt.cm.turbo(depth)[:, :3] * np.clip(np.log1p(nn) / np.log1p(np.percentile(nn, 99.5)), 0.2, 1)[:, None] * 255).astype(np.uint8)
    zspan = float(np.ptp(pu)) / max(hi - lo, 1e-6) * 0.15                                   # 기본 깊이 눈금: 깊이 범위가 가로 폭의 약 15%가 되도록(임의, 슬라이더로 조절)
    print(f"points {len(pu)}  extent {np.ptp(pu):.0f} x {np.ptp(pv):.0f}, depth {lo:.3f}..{hi:.3f}, default depth scale {zspan:.2f}")
    fig, ax = plt.subplots(1, 2, figsize=(22, 9))
    for k, ang in enumerate((-35, 35)):
        r = np.radians(ang); X = pu * np.cos(r) + (sm - np.median(sm)) * zspan * np.sin(r); ax[k].scatter(X, pv, c=rgb / 255.0, s=0.3, marker="."); ax[k].set_aspect("equal"); ax[k].axis("off"); ax[k].set_title(f"{title}: view rotated {ang:+d} deg about the vertical axis", fontsize=12)
    plt.tight_layout(); plt.savefig(out + "_views.png", dpi=45); plt.close()
    P = np.stack([pu, pv, (sm - np.median(sm)) * zspan], 1); Pq = np.round(P * 8).astype(np.int16)
    html = HTML.replace("__TITLE__", title).replace("__DEPTH__", depth_label).replace("__POS__", base64.b64encode(Pq.tobytes()).decode()).replace("__COL__", base64.b64encode(rgb.tobytes()).decode())
    open(out + ".html", "w", encoding="utf-8").write(html); print("html", round(len(html) / 1e6, 2), "MB ->", out + ".html")


HTML = '''<!doctype html><html><head><meta charset="utf-8"><title>__TITLE__</title><style>body{margin:0;background:#0b0b0e;color:#ddd;font:13px sans-serif;overflow:hidden}#ui{position:fixed;left:12px;top:10px;background:#000a;padding:8px 12px;border-radius:6px}label{display:block;margin:4px 0}input{width:220px}</style></head><body>
<div id="ui"><b>__TITLE__</b> (__DEPTH__; scale unknown)<label>depth scale <input id="zs" type="range" min="0" max="10" step="0.1" value="1"></label><label>point size <input id="ps" type="range" min="0.5" max="4" step="0.1" value="1.5"></label><div>drag = rotate, wheel = zoom, shift+drag = pan. Color = relative depth (blue = low end, red = high end of the axis).</div></div>
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
</script></body></html>'''
