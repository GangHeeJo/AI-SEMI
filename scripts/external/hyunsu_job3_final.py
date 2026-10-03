import numpy as np, sys, json
sys.path.insert(0,'results')
from job3_estimator import *
name=sys.argv[1]; x,y,f=load(name)
base=dict(R=1,fwarp=True,sbits=4)
if name=='roll':
    grid=[dict(S=s,N=n) for s in (2,3,4) for n in (9,17)]+[dict(S=3,N=9,M=512),dict(S=3,N=9,refine=False),dict(S=3,N=9,fwarp=False)]
else:
    grid=[dict(S=s,N=n) for s in (2,3,4) for n in (9,17)]+[dict(S=3,N=9,span=16.0),dict(S=3,N=9,M=512),dict(S=3,N=9,fwarp=False)]
out=[]
for g in grid:
    cfg={**base,**g}
    r,est,qgt,_,k0=run(name,x,y,f,**cfg)
    v=~np.isnan(est); d1=np.diff(np.where(v,est,np.nan)); dg=np.diff(qgt); m=v[1:]&v[:-1]&(np.abs(dg)>(0.3 if name=='roll' else 2))
    r['scale']=float(np.nanmedian(d1[m]/dg[m])); r['cfg']=cfg; r['travel']=float(np.nanmax(np.abs(qgt[v]-qgt[v][0])))
    out.append(r); np.save(f"results/job3_est_{name}_{'_'.join(f'{k}{v}' for k,v in g.items())}.npy",np.stack([k0,est,qgt]))
    print(json.dumps({k:(round(v,3) if isinstance(v,float) else v) for k,v in r.items() if k in ('cfg','mean_abs','max_abs','final','rms','sparse_mean','scale','travel','reads_per_ev','score_reads_per_ev','adds_per_win','cmps_per_win','W','H')}));sys.stdout.flush()
json.dump(out,open(f'results/job3_{name}_final.json','w'),indent=1)
