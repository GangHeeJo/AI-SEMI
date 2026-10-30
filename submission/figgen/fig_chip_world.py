import numpy as np, json, sys, os
import matplotlib; matplotlib.use('Agg')
import matplotlib.pyplot as plt
plt.rcParams['font.family']='Malgun Gothic'; plt.rcParams['axes.unicode_minus']=False
sys.path.insert(0,'.')
import job6_golden as G
T=os.environ['TEMP']+'/chipfig'; R='job27_vectors_cal'
def load(path, w, h):
    v=[int(l,16) for l in open(path)]
    m=np.zeros(w*h,int)
    for c in range(w*h): m[c]=(v[c>>4]>>(4*(c&15)))&15
    return m.reshape(h,w)
def raw(ds,f0,f1,W,H):
    st=G.Stream(ds); a=np.zeros((H,W))
    for k in range(f0,f1):
        x,y,_=st.frame(k); np.add.at(a,(np.clip(y,0,H-1),np.clip(x,0,W-1)),1)
    return a
def show(ax,a,t,gam=0.6):
    ax.imshow(a**gam if a.max()>0 else a,cmap='gray',interpolation='nearest'); ax.set_title(t,fontsize=11); ax.axis('off')
# roll_B
w=json.load(open(f'{T}/vec/roll_B/world.json')); mh=load(f'{T}/vec/roll_B/mem_final_w.hex',w['W'],w['H'])
wc=json.load(open(f'{R}/roll_B/world.json')); mc=load(f'{R}/roll_B/mem_final_w.hex',wc['W'],wc['H'])
rw=raw('roll',921,953,960,720)
fig,ax=plt.subplots(1,3,figsize=(15,5.6),facecolor='white')
show(ax[0],rw,'보정 없음: 센서 좌표에 그대로 쌓음 (roll 32프레임)'); show(ax[1],mh,'칩 출력 월드 메모리 (RTL 시뮬)'); show(ax[2],mc,'칩 출력, 자기보정 피벗 설정')
plt.tight_layout(); plt.savefig(f'{T}/out/chip_roll_world.png',dpi=130); plt.close()
# pan_B
w=json.load(open(f'{T}/vec/pan_B/world.json')); mp=load(f'{T}/vec/pan_B/mem_final_w.hex',w['W'],w['H'])
rp=raw('pan',85,149,960,720)
nz=np.argwhere(mp>0); y0,x0=nz.min(0); y1,x1=nz.max(0)+1
fig,ax=plt.subplots(1,2,figsize=(13,4.6),facecolor='white',gridspec_kw={'width_ratios':[960,(x1-x0)*8]})
show(ax[0],rp,'보정 없음: 센서 좌표에 쌓음 (pan 64프레임)'); show(ax[1],mp[y0:y1,x0:x1],'칩 출력 월드 메모리 (RTL 시뮬)')
plt.tight_layout(); plt.savefig(f'{T}/out/chip_pan_world.png',dpi=130); plt.close()
# 각도
def ang(p):
    th=[]
    for l in open(p):
        cs,sn,_,_=[int(t,16) if int(t,16)<2**31 else int(t,16)-2**32 for t in l.split()]
        th.append(np.degrees(np.arctan2(sn,cs)))
    return np.unwrap(np.radians(th))*180/np.pi
fig,ax=plt.subplots(1,2,figsize=(12,4),facecolor='white')
for s,c in (('roll_A','C0'),('roll_B','C1')):
    mt=json.load(open(f'{R}/{s}/meta.json')); a=ang(f'{R}/{s}/exp_fp.hex'); ax[0].plot(np.arange(mt['f0'],mt['f0']+len(a)),a,c,label=s)
ax[0].set_title('칩이 프레임마다 추정한 회전각 (roll)'); ax[0].set_xlabel('프레임'); ax[0].set_ylabel('각도 (°)'); ax[0].legend(); ax[0].grid(alpha=.3)
mt=json.load(open(f'{T}/vec/pan_B/meta.json')); a=ang(f'{T}/vec/pan_B/exp_fp.hex'); ax[1].plot(np.arange(mt['f0'],mt['f0']+len(a)),a,'C2'); ax[1].set_title('칩이 추정한 회전각 (pan 구간 B)'); ax[1].set_xlabel('프레임'); ax[1].grid(alpha=.3)
plt.tight_layout(); plt.savefig(f'{T}/out/chip_angle.png',dpi=130); plt.close()
print('ok', mh.sum(), mc.sum(), mp.sum())
