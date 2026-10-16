"""컬럼 메타데이터로 헤더 없는 MySQL OUTFILE CSV를 정확히 해석한다."""
from pathlib import Path
import io,json,re,zipfile
import pandas as pd
ROOT=Path(__file__).resolve().parents[1]
FIELD=re.compile(r'"(?:\\.|[^"\\])*"|[^,\r\n]*');ESC=re.compile(r'\\(.)');EM={'0':'\0','b':'\b','n':'\n','r':'\r','t':'\t','Z':'\x1a'}
def parse_line(line):
 line=line.rstrip('\r\n');out=[];pos=0
 while True:
  m=FIELD.match(line,pos)
  if not m:raise ValueError('CSV 형식 오류')
  raw=m.group();end=m.end();v=None if raw==r'\N' else raw[1:-1] if raw.startswith('"') else raw
  if v is not None:v=ESC.sub(lambda q:EM.get(q[1],q[1]),v)
  out.append(v)
  if end==len(line):return out
  if line[end]!=',':raise ValueError('CSV 구분자 오류')
  pos=end+1
class Export:
 def __init__(self,source):
  self.z=zipfile.ZipFile(source);self.catalog=json.loads((ROOT/'metadata/catalog.json').read_text())['documentation_column_catalog_v1'];self.names={Path(n).name:n for n in self.z.namelist() if n.endswith('.csv')};self.prefix='kream_repro_full_' if any(n.startswith('kream_repro_full_') for n in self.names) else 'kream_full_'
 def read(self,table):
  cols=[c['column_name'] for c in sorted([c for c in self.catalog if c['table_name']==table],key=lambda c:int(c['column_position']))]
  if table=='export_manifest_v1':cols=['export_order','table_name','output_file_name','table_role','actual_rows','expected_rows','column_count','row_count_status','export_version','captured_at_kst']
  with self.z.open(self.names[self.prefix+table+'.csv']) as f:rows=[parse_line(l) for l in io.TextIOWrapper(f,encoding='utf-8-sig',newline='')]
  if any(len(r)!=len(cols) for r in rows):raise ValueError('컬럼 수 불일치: '+table)
  return pd.DataFrame(rows,columns=cols,dtype='string')
 def close(self):self.z.close()
