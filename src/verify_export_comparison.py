"""기존 최종 ZIP과 재실행 ZIP의 업무 CSV 및 실행 메타데이터 차이를 구분한다."""
from pathlib import Path
import argparse,hashlib,json,zipfile
from evidence_csv import Export,ROOT

def run(original,repro):
 a,b=Export(original),Export(repro);left={n.removeprefix(a.prefix):n for n in a.names};right={n.removeprefix(b.prefix):n for n in b.names};assert left.keys()==right.keys();rows=[];different=[]
 for name in sorted(left):
  x=a.z.read(a.names[left[name]]);y=b.z.read(b.names[right[name]]);same=x==y
  rows.append({'file':name,'byte_identical':same,'original_sha256':hashlib.sha256(x).hexdigest(),'repro_sha256':hashlib.sha256(y).hexdigest()})
  if not same:
   t=name[:-4];u,v=a.read(t),b.read(t);assert u.shape==v.shape;changed=[c for c in u if not u[c].equals(v[c])]
   allowed={'data_quality_check_results_v1':{'checked_at_kst'},'export_manifest_v1':{'output_file_name','captured_at_kst'}}
   assert t in allowed and set(changed)<=allowed[t];different.append({'file':name,'changed_columns':changed})
 report={'original_sha256':hashlib.file_digest(open(original,'rb'),'sha256').hexdigest(),'repro_sha256':hashlib.file_digest(open(repro,'rb'),'sha256').hexdigest(),'csv_count':len(rows),'byte_identical_count':sum(r['byte_identical'] for r in rows),'differences':different,'files':rows};(ROOT/'evidence/export_comparison.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print('CSV',len(rows),'byte-identical',report['byte_identical_count']);a.close();b.close()
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--original',type=Path,required=True);p.add_argument('--repro',type=Path,required=True);a=p.parse_args();run(a.original,a.repro)
