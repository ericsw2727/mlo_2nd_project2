"""원본 49개 컬럼과 TO-BE의 타입·업무 도메인 사이의 차이를 계수한다."""
from pathlib import Path
from decimal import Decimal
import argparse,json,re
import pandas as pd
from profile_bronze import FILES,NULLS
R=Path(__file__).resolve().parents[1]
TABLES={'kream_product_std_dict.csv':'silver_product_std_dict','kream_category_parent_lookup.csv':'silver_category_parent_lookup','kream_inspector_master.csv':'silver_inspector_master','kream_inspection_300000.csv':'silver_inspection','kream_inspection_join_ready.csv':'silver_inspection_join_ready'}
PATTERNS={'DICT_ID':r'DICT_[0-9]{3}','CAT_ID':r'CAT_[0-9]{5}','PARENT_CAT_ID':r'CAT_[0-9]{5}','EMP_NO':r'KRM[0-9]{6}','INSPECTOR_EMP_NO':r'KRM[0-9]{6}','INSP_ID':r'INSP_[0-9]{6}'}
ENUM={'ACTIVE_YN':['Y','N'],'BANNED_WORD_YN':['Y','N'],'CAT_LEVEL':['TOP_LEVEL','BRAND_LINE'],'CODE_TYPE':['ITEM_MODEL','BANNED_WORD','INSP_RESULT','DEPT_STD','BANNED_DEPT'],'INSP_RESULT':['PASS','FAKE_REJECT','CLAIM_FAKE_PASS','BOX_DMG_HOLD']}
def run(raw_dir,out):
 catalog=json.loads((R/'metadata/catalog.json').read_text());columns={(c['table_name'],c['column_name']):c for c in catalog['documentation_column_catalog_v1']};rows=[]
 for filename,(_,names) in FILES.items():
  d=pd.read_csv(raw_dir/filename,dtype='string',keep_default_na=False,na_filter=False,encoding='utf-8-sig')
  for name in names:
   c=columns[TABLES[filename],name];s=d[name];missing=s.str.strip().str.upper().isin(NULLS);values=s[~missing];typ=c['column_type'];bad=pd.Series(False,index=values.index);fmt=''
   if re.match(r'(?:var)?char\(',typ):limit=int(re.search(r'\d+',typ)[0]);bad=values.str.len()>limit;fmt=f'문자 길이 {limit} 이하'
   elif typ.startswith('decimal'):
    precision,scale=map(int,re.search(r'\((\d+),(\d+)\)',typ).groups())
    def valid(v):
     if not re.fullmatch(r'-?\d+(?:\.\d+)?',v):return False
     return len(v.split('.')[1] if '.' in v else '')<=scale and abs(Decimal(v))<Decimal(10)**(precision-scale)
    bad=~values.map(valid);fmt='단위 접미사·구분자 없는 '+typ
   elif typ in ['date','datetime']:
    pat=r'\d{4}-\d{2}-\d{2}' if typ=='date' else r'\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}';f='%Y-%m-%d' if typ=='date' else '%Y-%m-%d %H:%M:%S';bad=(~values.str.fullmatch(pat))|pd.to_datetime(values,format=f,errors='coerce').isna();fmt=f
   elif typ.startswith(('int','bigint','tinyint')):bad=~values.str.fullmatch(r'[1-9][0-9]*' if name=='REV_NO' else r'-?[0-9]+');fmt='정수'+(' 및 개정 1 이상' if name=='REV_NO' else '')
   else:fmt='문자열 보존'
   domain_bad=pd.Series(False,index=values.index);domain=''
   if name in PATTERNS:domain=PATTERNS[name];domain_bad=~values.str.fullmatch(domain)
   if name in ENUM:domain=' | '.join(ENUM[name]);domain_bad=~values.isin(ENUM[name])
   rows.append(dict(source_file=filename,column_name=name,rows=len(s),target_type=typ,target_nullable=c['is_nullable'],missing_representation_rows=int(missing.sum()),nonnull_checked_rows=len(values),target_type_format_difference_rows=int(bad.sum()),business_domain_difference_rows=int(domain_bad.sum()),target_format=fmt,business_domain=domain,interpretation='변환 전 원문과 최종 표준의 차이. 복구 가능한 표기와 단위 변환을 포함하며 이 수치를 격리 건수로 해석하지 않음'))
 assert len(rows)==49;out.mkdir(parents=True,exist_ok=True);pd.DataFrame(rows).to_csv(out/'asis_to_be_column_gap.csv',index=False,encoding='utf-8-sig');print('전체 49개 컬럼의 TO-BE 표준 차이 진단 완료')
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--raw-dir',type=Path,required=True);p.add_argument('--output',type=Path,default=R/'reports/bronze');a=p.parse_args();run(a.raw_dir,a.output)
