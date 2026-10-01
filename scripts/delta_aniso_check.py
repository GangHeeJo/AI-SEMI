import sys, numpy as np, h5py
sys.path.insert(0,'scripts')
from scipy import ndimage as ndi
from delta_rotation_cmax import H5, WIN_MS
sp=sys.argv[1]
th=np.load(sp+"/trk_theta.npy"); om=np.degrees(np.gradient(th,WIN_MS*1e-3))   # deg/s
mids=(np.arange(len(th))*WIN_MS+WIN_MS/2)*1e3
f=h5py.File(H5,'r'); m=f['ms_to_idx'][:].astype(np.int64); C=1200; off=C/2
yy,xx=np.mgrid[:C,:C]; R=np.hypot(xx-off,yy-off); ux=(xx-off)/np.maximum(R,1); uy=(yy-off)/np.maximum(R,1)
rings=[(60,150),(150,230),(230,310),(310,390),(390,470)]
def ratio(t0,t1,correct=True):
    s,e=m[t0],m[t1]
    x=f['events/x'][s:e].astype(float)-480; y=f['events/y'][s:e].astype(float)-360; t=f['events/t'][s:e].astype(float)
    a=-np.interp(t,mids,th) if correct else np.zeros_like(t); c,sn=np.cos(a),np.sin(a)
    xi=np.rint(c*x-sn*y+off).astype(np.int64); yi=np.rint(sn*x+c*y+off).astype(np.int64)
    ok=(xi>=0)&(xi<C)&(yi>=0)&(yi<C)
    g=np.bincount(yi[ok]*C+xi[ok],minlength=C*C).reshape(C,C).astype(np.float32)
    g=ndi.gaussian_filter(np.minimum(g,np.percentile(g[g>0],99.5)),1.0)
    gy,gx=np.gradient(g)
    gr=gx*ux+gy*uy; gt=-gx*uy+gy*ux       # 반경방향 / 접선방향 기울기
    out=[]
    for r0,r1 in rings:
        k=(R>=r0)&(R<r1)
        out.append(float((gt[k]**2).sum()/(gr[k]**2).sum()))
    return np.array(out)
def mean_om(t0,t1):
    k=(mids>=t0*1e3)&(mids<t1*1e3); return np.abs(om[k]).mean()
print("rings(px):",rings)
for name,(t0,t1) in (("slow",(215,275)),("mid",(450,510)),("fast",(1100,1160)),("fastest",(1200,1260))):
    print(f"{name:7s} {t0}-{t1}ms |omega|~{mean_om(t0,t1):5.0f} deg/s  E_tan/E_rad corrected:",np.round(ratio(t0,t1),2),
          " uncorrected:",np.round(ratio(t0,t1,False),2),flush=True)
