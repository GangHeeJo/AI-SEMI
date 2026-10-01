import sys, numpy as np, h5py
sys.path.insert(0,'scripts')
from scipy import ndimage as ndi
from delta_rotation_cmax import H5, WIN_MS
sp=sys.argv[1]
th=np.load(sp+"/trk_theta.npy"); mids=(np.arange(len(th))*WIN_MS+WIN_MS/2)*1e3
f=h5py.File(H5,'r'); m=f['ms_to_idx'][:].astype(np.int64); C=800; off=C/2
yy,xx=np.mgrid[:C,:C]; disc=((xx-off)**2+(yy-off)**2)<340**2
def chunk(t0,t1):
    s,e=m[t0],m[t1]
    x=f['events/x'][s:e].astype(float)-480; y=f['events/y'][s:e].astype(float)-360; t=f['events/t'][s:e].astype(float)
    a=-np.interp(t,mids,th); c,sn=np.cos(a),np.sin(a)
    xi=np.rint(c*x-sn*y+off).astype(np.int64); yi=np.rint(sn*x+c*y+off).astype(np.int64)
    ok=(xi>=0)&(xi<C)&(yi>=0)&(yi<C)
    g=np.bincount(yi[ok]*C+xi[ok],minlength=C*C).reshape(C,C).astype(np.float32)
    g=np.minimum(g,np.percentile(g[g>0],99)); g=ndi.gaussian_filter(g,1.5)-ndi.gaussian_filter(g,10)
    return g*disc
def xcorr(a,b):
    F=np.fft.rfft2(a); G=np.fft.rfft2(b); r=np.fft.irfft2(F*np.conj(G),s=a.shape)
    r=np.fft.fftshift(r); k=np.unravel_index(r.argmax(),r.shape)
    n=np.sqrt((a*a).sum()*(b*b).sum())
    return r[k]/n,(k[1]-C//2,k[0]-C//2)
ref=chunk(740,780)
print("reference 740-780ms; rows: t_start, best dTheta(deg) , dx, dy (world px), ncc")
for t0 in range(560,1000,40):
    g=chunk(t0,t0+40); best=(-1,0,(0,0))
    for da in np.arange(-6,6.01,0.5):
        v,sh=xcorr(ndi.rotate(g,da,reshape=False,order=1)*disc,ref)
        if v>best[0]: best=(v,da,sh)
    print(t0,"dTheta=%+.1f"%best[1],"shift=(%+d,%+d)"%best[2],"ncc=%.3f"%best[0],flush=True)
