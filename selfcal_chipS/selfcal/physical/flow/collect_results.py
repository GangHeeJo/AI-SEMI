"""Collect bounded evidence without changing DUT or historical results."""
from pathlib import Path
import hashlib,json,re,shutil,gzip,tarfile
P=Path('/home/aiasic26911/selfcal_20261115/phys'); F=P/'full_8.0'; E=P/'final_evidence';E.mkdir(exist_ok=True)
def copy(src, dst):
    src=Path(src);dst=E/dst
    if src.exists():dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(str(src),str(dst))
G={}
for name in ['roll_B_MINIMUM','roll_B_MAXIMUM','pan_B_MINIMUM','pan_B_MAXIMUM','roll_r1_MINIMUM']:
    d=P/'gate'/name; log=(d/'xrun.log').read_text(errors='replace'); sdf=(d/'sdf.log').read_text(errors='replace')
    codes={c:len(re.findall(r'\*W,'+c+r'\b',log)) for c in sorted(set(re.findall(r'\*W,(\w+)',log)))}
    G[name]=dict(functional_pass=bool(re.search(r'^PASS$',log,re.M)), timing_violations=log.count('Timing violation'),
      runner_exit=int((d/'EXIT').read_text()),wall_seconds=int((d/'WALL_SECONDS').read_text()),warnings=codes,
      result=re.findall(r'^(?:RESULT|SELFCAL_FINAL).*',log,re.M))
    for fn in ['SUMMARY.txt','EXIT','WALL_SECONDS','STARTED','FINISHED','SHA256.txt','CLOCK.txt','xrun.log','sdf.log','tb_run.sv']:
        copy(d/fn,'gate/'+name+'/'+fn)
for fn in ['RTL_SHA256.txt','SOURCE_COMMIT.txt','SYN_SHA256.txt','FINAL3_SHA256.txt','STAGE1_SPEC.md']:
    copy(P/'evidence'/fn,'provenance/'+fn)
for fn in ['synthesis.log','pnr.log','stage2.log','stage2b.log','signoff3.log','lec_synthesis.log','lec_final3.log','rtl_regression_final.log']:
    copy(P/'logs'/fn,'logs/'+fn)
for fn in ['area.rpt','timing.rpt','power.rpt','gates.rpt','chip_s_full.sdc']:
    copy(F/'syn'/fn,'synthesis/'+fn)
for fn in ['drc_final3.rpt','conn_final3.rpt','antenna_final3.rpt','area_final3.rpt','checkplace3.rpt','signoff_power3_80.rpt','signoff_setup3.rpt','signoff_hold3.rpt','pin_placement.txt']:
    copy(F/'pnr'/fn,'physical/'+fn)
for kind in ['signoff_setup3','signoff_hold3']:
    for f in (F/'pnr'/kind).glob('*.summary.gz'):
        (E/'physical'/('%s_summary.txt'%kind)).write_bytes(gzip.open(str(f),'rb').read())
for fn in ['lec2.log','lec2_synthesis.log','fv/chip_s_full/rtl_to_fv_map.log']:
    copy(F/fn,'lec/'+Path(fn).name)
S=dict(source_commit=(P/'evidence/SOURCE_COMMIT.txt').read_text().strip(),clock_ns=8.0,
      synthesis_area_um2=4457451.573,macro_area_um2=4194133.734,pnr_area_um2=4564050.496,
      setup_wns_ns=0.169,hold_wns_ns=0.015,setup_hold_violating_paths=0,
      pg_maxviastack_drc=11,transition_real_nets=456,transition_real_terms=920,glitch_violations=13,
      out_of_core_instances=9,vectorless_power_mw=12.82646580,
      physical_status='NOT_CLEAN: PG_DRC, transition, glitch, placement boundary and startup GLS timing warnings',
      macro_model='behavioral; macro internal power excluded',gate=G,
      optional_not_run=['roll_r1 MAX','pan_r1 MIN/MAX','roll_r0 MIN/MAX'],
      algorithm_accuracy='ECC accuracy not evaluated; no estimator redesign in stage2/3')
(P/'RESULTS.json').write_text(json.dumps(S,indent=2)+'\n');copy(P/'RESULTS.json','RESULTS.json')
manifest=[]
for f in sorted(E.rglob('*')):
    if f.is_file():manifest.append(dict(path=str(f.relative_to(E)),bytes=f.stat().st_size,sha256=hashlib.sha256(f.read_bytes()).hexdigest()))
(E/'MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n')
with tarfile.open(str(P/'final_evidence.tar.gz'),'w:gz') as t:t.add(str(E),arcname='final_evidence')
print(json.dumps(dict(gate={k:{x:v[x] for x in ['functional_pass','timing_violations','wall_seconds']} for k,v in G.items()},evidence_files=len(manifest),archive_bytes=(P/'final_evidence.tar.gz').stat().st_size)))
