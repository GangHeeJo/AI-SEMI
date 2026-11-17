import json, math, numpy as np
E = np.load('/home/aiasic26911/redred_gate_ext/ecc/work/data/roll_ecc.npy'); k, ok, dth = E[:,0], E[:,3].astype(bool), E[:,4]; thc = np.cumsum(np.where(ok, dth, 0.0))
def Am(a): c,s=math.cos(a),math.sin(a); return np.array([[c-1,s],[-s,c-1]])
u=np.array([-10.3,57.2])
for tag in ('dt32','K1'):
    so=[o for o in json.load(open(f'/home/aiasic26911/redred_gate_ext/trans/obs_{tag}.json'))['obs'] if o['br']=='score']
    f0=np.array([o['f0'] for o in so]); L=np.array([o['L'] for o in so]); q=np.array([o['q'] for o in so],float)
    thi=np.degrees(q[:,0]*2*math.pi/16384); t=q[:,1:3]/16
    idx=np.array([int(np.argmin(np.abs(k-x))) for x in f0+L]); sel=np.abs(k[idx]-(f0+L))<=4
    sg=1.0 if np.corrcoef(thc[idx][sel],thi[sel])[0,1]>0 else -1.0
    ang=np.radians(sg*thc[idx])[sel]; tm=np.array([Am(a)@u for a in ang]); ti=t[sel]
    for c,nm in ((0,'x'),(1,'y')):
        A=np.vstack([tm[:,c],np.ones(len(tm))]).T; s,b=np.linalg.lstsq(A,ti[:,c],rcond=None)[0]
        print(f'{tag} {nm}: slope {s:.3f} intercept {b:.1f}px corr {np.corrcoef(tm[:,c],ti[:,c])[0,1]:.3f} model range {tm[:,c].min():.0f}..{tm[:,c].max():.0f}')
    # alternate: what u_x in the sign-flipped x assumption gives best x fit
    for ux in (-10.3,0,10):
        tm2=np.array([Am(a)@np.array([ux,57.2]) for a in ang]); print(f'   u_x={ux}: resid rms {np.sqrt(np.mean((ti-tm2-(ti-tm2).mean(0))**2)):.1f}')
