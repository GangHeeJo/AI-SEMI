import sys, numpy as np, h5py
sys.path.insert(0,'scripts')
from scipy import ndimage as ndi
from delta_rotation_cmax import CX,CY,H5,WIN_MS
import matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt
sp=sys.argv[1]
th=np.load(sp+"/trk_theta.npy"); mids=(np.arange(len(th))*WIN_MS+WIN_MS/2)*1e3
f=h5py.File(H5,'r'); n=f['events/t'].shape[0]; C=1200; off=C/2
maps=[np.zeros(C*C,np.float64) for _ in range(2)]
for s in range(0,n,4_000_000):
    x=f['events/x'][s:s+4_000_000].astype(float)-CX; y=f['events/y'][s:s+4_000_000].astype(float)-CY
    t=f['events/t'][s:s+4_000_000].astype(float)
    a=-np.interp(t,mids,th); c,sn=np.cos(a),np.sin(a)
    xi=np.rint(c*x-sn*y+off).astype(np.int64); yi=np.rint(sn*x+c*y+off).astype(np.int64)
    ok=(xi>=0)&(xi<C)&(yi>=0)&(yi<C); h=(t>=0.5e6*1.59).astype(int)
    for k in (0,1):
        q=ok&(h==k); maps[k]+=np.bincount(yi[q]*C+xi[q],minlength=C*C)
A,B=[m.reshape(C,C).astype(np.float32) for m in maps]
def prep(m):
    m=np.minimum(m,np.percentile(m[m>0],99)); g=ndi.gaussian_filter(m,2)-ndi.gaussian_filter(m,12)
    yy,xx=np.mgrid[:C,:C]; g[(xx-600)**2+(yy-600)**2>450**2]=0; return g
a,b=prep(A),prep(B)
def ncc(x,y): x=x-x.mean(); y=y-y.mean(); return (x*y).sum()/np.sqrt((x*x).sum()*(y*y).sum())
r=sorted([(float(ncc(a,ndi.rotate(b,p,reshape=False,order=1))),p) for p in range(-60,61,2)],reverse=True)
print("refined: top5 (ncc,rotateB deg):",[(round(c,3),p) for c,p in r[:5]],"| ncc@0:",round(dict((p,c) for c,p in r)[0],3))
fig,ax=plt.subplots(1,2,figsize=(16,8))
for k,(m,nm) in enumerate(((A,'A first half'),(B,'B second half'))):
    hi=np.percentile(m[m>0],99.5); ax[k].imshow(np.clip(m,0,hi),cmap='gray'); ax[k].set_title('refined '+nm); ax[k].axis('off')
plt.tight_layout(); plt.savefig(sp+"/maps_refined.png",dpi=45)
