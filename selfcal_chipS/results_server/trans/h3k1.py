import json, math, numpy as np
E = np.load('/home/aiasic26911/redred_gate_ext/ecc/work/data/roll_ecc.npy'); k, ok, dth = E[:,0], E[:,3].astype(bool), E[:,4]; thc = np.cumsum(np.where(ok, dth, 0.0))
def Am(a): c,s=math.cos(a),math.sin(a); return np.array([[c-1,s],[-s,c-1]])
for tag in ('dt32','K1','dt16'):
    so=[o for o in json.load(open(f'/home/aiasic26911/redred_gate_ext/trans/obs_{tag}.json'))['obs'] if o['br']=='score']
    f0=np.array([o['f0'] for o in so]); L=np.array([o['L'] for o in so]); q=np.array([o['q'] for o in so],float)
    thi=np.degrees(q[:,0]*2*math.pi/16384); t=q[:,1:3]/16
    idx=np.array([int(np.argmin(np.abs(k-x))) for x in f0+L]); sel=np.abs(k[idx]-(f0+L))<=4
    sg=1.0 if np.corrcoef(thc[idx][sel],thi[sel])[0,1]>0 else -1.0
    for nm,lim in (('first127',127),('to156',156),('all',len(so))):
        m=np.zeros(len(so),bool); m[:lim]=True; m&=sel
        for an,ang in (('th_chip',np.radians(thi)),('th_ecc',np.radians(sg*thc[idx]))):
            As=np.array([Am(a) for a in ang[m]]); Ac=As-As.mean(0); tc=t[m]-t[m].mean(0)
            S=np.einsum('kji,kjl->il',Ac,Ac); b=np.einsum('kji,kj->i',Ac,tc); u=np.linalg.solve(S,b)
            print(f'{tag:5s} {nm:8s} {an:7s} u=({u[0]:7.1f},{u[1]:7.1f}) R={np.hypot(*u):6.1f} Q=({480+u[0]:.0f},{360+u[1]:.0f})')
