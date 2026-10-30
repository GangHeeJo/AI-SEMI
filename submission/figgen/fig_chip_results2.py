import numpy as np, json, sys, os, math
import matplotlib; matplotlib.use('Agg')
import matplotlib.pyplot as plt
plt.rcParams['font.family']='Malgun Gothic'; plt.rcParams['axes.unicode_minus']=False
sys.path.insert(0,'.')
import job6_golden as G, job17_core as J
T=os.environ['TEMP']+'/chipfig'; OUT=T+'/out'
# ---- A. 각도: 칩 정수 기준모델 vs ECC (roll 전체)
qf=np.load('../data/golden_roll_qf.npy').astype(float)*360/16384
e=np.load('../data/roll_ecc.npy'); k,tt,n,ok,dth,*_=e.T; ok=ok.astype(bool)
ecc=np.cumsum(np.where(ok,dth,0.0))
fr=k.astype(int); ms=fr*0.773
for sgn in (1,-1):
    d=sgn*qf[fr]-ecc
    if abs(np.median(d[ok]))<abs(np.median(d[ok]))+1e9: pass
d1=qf[fr]-ecc; d2=-qf[fr]-ecc
sg=1 if np.abs(d1[ok]-np.median(d1[ok])).mean()<np.abs(d2[ok]-np.median(d2[ok])).mean() else -1
d=sg*qf[fr]-ecc; d=d-np.median(d[ok]); chip=sg*qf[fr]-np.median(sg*qf[fr]-ecc)
print('sign',sg,'mean abs err',np.abs(d[ok]).mean(),'max',np.abs(d[ok]).max(), 'final chip',chip[-1],'ecc',ecc[-1])
fig,ax=plt.subplots(1,2,figsize=(13,4.3),facecolor='white')
ax[0].plot(ms[ok],ecc[ok],'C1',lw=2.2,label='정답 (ECC 4프레임 정합)'); ax[0].plot(ms[ok],chip[ok],'C0--',lw=1.6,label='칩 정수 기준모델 (RTL 사양)')
ax[0].set_xlabel('시간 (ms)'); ax[0].set_ylabel('누적 회전각 (°)'); ax[0].set_title('roll 녹화 전체 5초: 칩이 구한 회전각'); ax[0].legend(); ax[0].grid(alpha=.3)
ax[1].plot(ms[ok],d[ok],'C0',lw=1.2); ax[1].axhline(0,color='k',lw=.6); ax[1].set_xlabel('시간 (ms)'); ax[1].set_ylabel('오차 (°)'); ax[1].set_title('칩 - 정답 (프레임별 오차)'); ax[1].grid(alpha=.3)
plt.tight_layout(); plt.savefig(f'{OUT}/chip_theta_vs_ecc.png',dpi=140); plt.close()
# ---- B. 지도 성장
w=json.load(open(f'{T}/vec/roll_B/world.json')); meta=json.load(open(f'{T}/vec/roll_B/meta.json'))
fp=[tuple((int(t,16)-(1<<32) if int(t,16)>=1<<31 else int(t,16)) for t in l.split()) for l in open(f'{T}/vec/roll_B/exp_fp.hex')]
st=G.Stream('roll'); g4,g8=J.grids('roll'); X0,Y0,W,H=g8.X0,g8.Y0,g8.W,g8.H; F=10
m=np.zeros(W*H,np.int64); r=0xACE1
def ls(r): return (r>>1)|((((r>>0)^(r>>2)^(r>>3)^(r>>5))&1)<<15)
snaps={}; f0=meta['f0']; f1=meta['f1']
for i,kf in enumerate(range(f0,f1)):
    cs,sn,bx,by=fp[i]; x,y,_=st.frame(kf)
    X=bx+cs*x.astype(np.int64)-sn*y.astype(np.int64); Y=by+sn*x.astype(np.int64)+cs*y.astype(np.int64)
    cx=((X>>F)-X0)>>3; cy=((Y>>F)-Y0)>>3; ok2=(cx>=0)&(cx<W)&(cy>=0)&(cy<H)
    for c in (cy*W+cx)[ok2]:
        r=ls(r); v=int(m[c])
        if v<15 and (r&((1<<v)-1))==0: m[c]=v+1
    if i+1 in (2,4,8,16,32): snaps[i+1]=m.reshape(H,W).copy()
ks=sorted(snaps); nz=np.argwhere(snaps[ks[-1]]>0); y0,x0=nz.min(0); y1,x1=nz.max(0)+1
fig,ax=plt.subplots(1,len(ks),figsize=(15,3.4),facecolor='white')
for a,kk in zip(ax,ks):
    a.imshow(snaps[kk][y0:y1,x0:x1]**0.6,cmap='gray',vmin=0,vmax=15**0.6); a.set_title(f'{kk}프레임 ({kk*0.773:.1f} ms)',fontsize=11); a.axis('off')
plt.tight_layout(); plt.savefig(f'{OUT}/chip_map_growth.png',dpi=140); plt.close()
# ---- C. 뱅크별 점유 + 카운터 분포
def load(path,w,h):
    v=[int(l,16) for l in open(path)]; mm=np.zeros(len(v)*16,int)
    for c in range(len(v)*16): mm[c]=(v[c>>4]>>(4*(c&15)))&15
    return mm
fig,ax=plt.subplots(1,3,figsize=(14,3.9),facecolor='white')
for nm,c in (('roll_B','C0'),('pan_B','C2')):
    mm=load(f'{T}/vec/{nm}/mem_final_w.hex',0,0)
    bank=mm.reshape(16,-1)      # 16 banks x 2048 cells
    occ=(bank>0).sum(1)
    ax[0 if nm=='roll_B' else 1].bar(range(16),occ,color=c); ax[0 if nm=='roll_B' else 1].set_title(f'{nm}: 뱅크별 쓰인 셀 수'); ax[0 if nm=='roll_B' else 1].set_xlabel('월드 뱅크 번호'); ax[0 if nm=='roll_B' else 1].set_ylim(0,2048); ax[0 if nm=='roll_B' else 1].grid(alpha=.3,axis='y')
    print(nm,'active banks',int((occ>0).sum()),'cells>0',int((mm>0).sum()))
mr=load(f'{T}/vec/roll_B/mem_final_w.hex',0,0); mp=load(f'{T}/vec/pan_B/mem_final_w.hex',0,0)
hr=np.bincount(mr[mr>0],minlength=16)[1:]; hp=np.bincount(mp[mp>0],minlength=16)[1:]
ax[2].bar(np.arange(1,16)-0.2,hr,0.4,label='roll_B',color='C0'); ax[2].bar(np.arange(1,16)+0.2,hp,0.4,label='pan_B',color='C2')
ax[2].set_title('셀 카운터 값 분포 (4비트 로그 카운터)'); ax[2].set_xlabel('카운터 값 (1~15, 포화 15)'); ax[2].legend(); ax[2].grid(alpha=.3,axis='y')
plt.tight_layout(); plt.savefig(f'{OUT}/chip_bank_hist.png',dpi=140); plt.close()
print('done')
