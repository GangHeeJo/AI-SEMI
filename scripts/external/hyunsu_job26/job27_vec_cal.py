# job27: 보정 피벗(데이터에서 구한 값)으로 칩 S 검증 벡터를 다시 만든다. 현수의 job24_vec.py / job24_world.py를 코드 수정 없이 텍스트 치환으로 재사용:
#  - 피벗만 G.DS['roll']['pivot'] 를 덮어씀, 출력 폴더만 job27_vectors_cal 로 바꿈.
# 사용: python job27_vec_cal.py vec roll   |   python job27_vec_cal.py world roll_A
import sys, os
from pathlib import Path
here = Path(__file__).resolve().parent
sys.path.insert(0, str(here))
import job6_golden as G
PIV = tuple(int(v) for v in os.environ.get('PIVOT', '473,408').split(','))
G.DS['roll']['pivot'] = PIV
kind = sys.argv[1]
src = (here / ('job24_vec.py' if kind == 'vec' else 'job24_world.py')).read_text(encoding='utf-8').replace('job24_vectors', 'job27_vectors_cal')
sys.argv = [sys.argv[0]] + sys.argv[2:]
print('pivot override', PIV, 'kind', kind, flush=True)
exec(compile(src, f'job24_{kind}_cal', 'exec'), {'__name__': '__main__', '__file__': str(here / ('job24_vec.py' if kind == 'vec' else 'job24_world.py'))})
