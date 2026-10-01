import sys, numpy as np, h5py
sys.path.insert(0,'scripts')
from delta_rotation_cmax import H5, WIN_MS
sp=sys.argv[1]; t0=int(sys.argv[2]); L=int(sys.argv[3])
th=np.load(sp+"/trk_theta.npy"); mids=(np.arange(len(th))*WIN_MS+WIN_MS/2)*1e3
f=h5py.File(H5,'r'); m=f['ms_to_idx'][:].astype(np.int64)
s,e=m[t0],m[t0+L]
X=f['events/x'][s:e].astype(np.float64); Y=f['events/y'][s:e].astype(np.float64); T=f['events/t'][s:e].astype(np.float64)
ang=np.interp(T,mids,th)-np.interp(T.mean(),mids,th)           # 창 중앙 기준 상대 회전각
om=np.degrees((np.interp((t0+L)*1e3,mids,th)-np.interp(t0*1e3,mids,th))/(L*1e-3))
print(f"window {t0}-{t0+L}ms  mean omega {om:.0f} deg/s  rotation over window {np.degrees(ang.max()-ang.min()):.1f} deg  events {len(X)}")
TX,TY=6,4; tw,th_=960//TX,720//TY
cand=np.arange(-200,201,10)
def coll(x,y,a,cx,cy):
    c,sn=np.cos(-a),np.sin(-a)
    xr=cx+c*(x-cx)-sn*(y-cy); yr=cy+sn*(x-cx)+c*(y-cy)
    xi=np.rint(xr).astype(np.int64)+200; yi=np.rint(yr).astype(np.int64)+200
    ok=(xi>=0)&(xi<1360)&(yi>=0)&(yi<1120)
    cnt=np.bincount(yi[ok]*1360+xi[ok],minlength=1360*1120).astype(float); n=cnt.sum()
    return (cnt*(cnt-1)).sum()/max(n*(n-1),1)
print("per tile best center offset (dx,dy) from image center (480,360); gain vs (0,0). rows=y tiles")
for ty in range(TY):
    row=[]
    for tx in range(TX):
        k=(X>=tx*tw)&(X<(tx+1)*tw)&(Y>=ty*th_)&(Y<(ty+1)*th_)
        x,y,a=X[k],Y[k],ang[k]
        if len(x)>6000:
            idx=np.random.default_rng(0).choice(len(x),min(len(x),12000),replace=False); x,y,a=x[idx],y[idx],a[idx]
        if len(x)<3000: row.append("   n/a    "); continue
        base=coll(x,y,a,480,360); best=(base,0,0)
        for dy in cand:
            for dx in cand:
                v=coll(x,y,a,480+dx,360+dy)
                if v>best[0]: best=(v,dx,dy)
        row.append(f"({best[1]:+3d},{best[2]:+3d}) x{best[0]/base:.2f}")
    print("  "+"  ".join(row),flush=True)
