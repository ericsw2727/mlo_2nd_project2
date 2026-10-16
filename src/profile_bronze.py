"""공급받은 원본 CSV 다섯 개를 변경 없이 읽어 AS-IS 품질을 진단한다."""
from pathlib import Path
import argparse,hashlib,json,re
import pandas as pd
FILES={
 'kream_product_std_dict.csv':(32,['DICT_ID','CODE_TYPE','STD_CODE','STD_KOR_NM','SYNONYM_LIST','BANNED_WORD_YN','BASE_RETAIL_KRW','FAKE_PENALTY_MULTIPLIER']),
 'kream_category_parent_lookup.csv':(1050,['CAT_ID','CAT_NM','CAT_LEVEL','REG_DT']),
 'kream_inspector_master.csv':(3150,['EMP_NO','EMP_NM','DEPT_NM','POSITION_NM','HIRE_DT','ACTIVE_YN']),
 'kream_inspection_300000.csv':(335000,['INSP_ID','REV_NO','ITEM_STD_CODE','ITEM_NM','PARENT_CAT_ID','TRADE_PRICE_KRW','INSP_DURATION_MIN','INSP_RESULT','INSPECTOR_EMP_NO','INBOUND_DT','INSP_DONE_DT','EXTRACTED_AT','INSP_MEMO']),
 'kream_inspection_join_ready.csv':(335000,['INSP_ID','REV_NO','ITEM_STD_CODE','ITEM_NM','PARENT_CAT_ID','PARENT_CAT_NM','TRADE_PRICE_KRW','INSP_DURATION_MIN','INSP_RESULT','COMPENSATION_LOSS_KRW','INSPECTOR_EMP_NO','INSPECTOR_EMP_NM','INSPECTOR_DEPT_NM','INSPECTOR_POSITION_NM','INBOUND_DT','INSP_DONE_DT','EXTRACTED_AT','INSP_MEMO'])}
NULLS={'','NULL','NONE','NA','N/A','NAN','-'}
TRANS=str.maketrans('０１２３４５６７８９ＡＣＴＫＲＭＩＮＳＰ＿','0123456789ACTKRMINSP_')
def normalize(s,kind):
 s=s.str.replace('[ \\t\\r\\n\u00a0\u200b\u3000]','',regex=True).str.upper().str.translate(TRANS)
 if kind=='INSP':s=s.str.replace(r'^INSP-([0-9]{6})$',r'INSP_\1',regex=True);s=s.str.replace(r'^([0-9]{6})$',r'INSP_\1',regex=True)
 if kind=='KRM':s=s.str.replace(r'^KRM-([0-9]{6})$',r'KRM\1',regex=True);s=s.str.replace(r'^([0-9]{6})$',r'KRM\1',regex=True)
 if kind=='CAT':s=s.str.replace(r'^CAT-([0-9]{5})$',r'CAT_\1',regex=True)
 return s

def run(raw_dir,out):
 missing=[f for f in FILES if not(raw_dir/f).is_file()]
 if missing:raise FileNotFoundError('원본 파일이 필요합니다: '+', '.join(missing))
 out.mkdir(parents=True,exist_ok=True);profiles=[];files=[];keys=[];data={}
 for filename,(expected,columns) in FILES.items():
  p=raw_dir/filename;df=pd.read_csv(p,dtype='string',keep_default_na=False,na_filter=False,encoding='utf-8-sig');data[filename]=df
  if list(df)!=columns:raise ValueError(filename+' 헤더 또는 컬럼 순서가 명세와 다릅니다: '+str(list(df)))
  files.append(dict(file=filename,sha256=hashlib.file_digest(open(p,'rb'),'sha256').hexdigest(),rows=len(df),expected_rows=expected,row_difference=len(df)-expected,columns=len(df.columns),exact_duplicate_rows=int(df.duplicated().sum())))
  for c in df:
   s=df[c];trim=s.str.strip();literal=trim.str.upper().isin(NULLS)&(trim!='')
   profiles.append(dict(file=filename,column=c,rows=len(s),blank_rows=int((trim=='').sum()),literal_missing_rows=int(literal.sum()),raw_distinct_values=int(s.nunique()),max_char_length=int(s.str.len().max()),outer_space_rows=int((s!=trim).sum()),replacement_character_rows=int(s.str.contains('\ufffd',regex=False).sum())))
  key='INSP_ID' if 'INSP_ID' in df else 'EMP_NO' if 'EMP_NO' in df else 'CAT_ID' if 'CAT_ID' in df else 'DICT_ID';norm=normalize(df[key],{'INSP_ID':'INSP','EMP_NO':'KRM','CAT_ID':'CAT'}.get(key,'DICT'))
  keys.append(dict(file=filename,key_column=key,raw_distinct_keys=int(df[key].nunique()),normalized_distinct_keys=int(norm.nunique()),normalization_changed_rows=int((df[key]!=norm).sum())))
 fact=data['kream_inspection_300000.csv'];idnorm=normalize(fact.INSP_ID,'INSP');groupframe=fact.copy();groupframe['INSP_ID']=idnorm;groups=groupframe.groupby(['INSP_ID','REV_NO'],dropna=False).size().rename('rows').reset_index();unique_payloads=groupframe.drop_duplicates().groupby(['INSP_ID','REV_NO'],dropna=False).size().rename('payload_versions').reset_index();groups=groups.merge(unique_payloads,on=['INSP_ID','REV_NO'],validate='one_to_one');groups.to_csv(out/'revision_groups.csv',index=False,encoding='utf-8-sig')
 emp=data['kream_inspector_master.csv'];active=emp.ACTIVE_YN.value_counts(dropna=False).rename_axis('raw_active_yn').reset_index(name='rows');active['standard_active_yn']=active.raw_active_yn.map(lambda v:'Y' if v=='Y' else 'N');active.to_csv(out/'active_status_profile.csv',index=False,encoding='utf-8-sig')
 pd.DataFrame(files).to_csv(out/'source_manifest.csv',index=False,encoding='utf-8-sig');pd.DataFrame(profiles).to_csv(out/'asis_column_profile.csv',index=False,encoding='utf-8-sig');pd.DataFrame(keys).to_csv(out/'asis_key_profile.csv',index=False,encoding='utf-8-sig')
 summary=dict(source_files=len(files),physical_received_rows=sum(x['rows'] for x in files),profiled_columns=len(profiles),conflicting_revision_groups=int((groups.payload_versions>1).sum()),conflicting_revision_rows=int(groups.loc[groups.payload_versions>1,'rows'].sum()),identical_duplicate_revision_groups=int(((groups.rows>1)&(groups.payload_versions==1)).sum()),interpretation='원천 검수와 조인 통합본은 동일 업무의 별도 표현이다. 물리 행 합계를 고유 검수 건수로 해석하지 않는다. 충돌은 정규화한 ID와 원본 개정 값을 기준으로 모든 업무 컬럼을 비교한 진단이다. 최종 분류는 SQL 개정 정규화 및 유효성 규칙과 대조한다.')
 (out/'asis_summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2));print(json.dumps(summary,ensure_ascii=False))
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--raw-dir',type=Path,required=True);p.add_argument('--output',type=Path,default=Path('reports/bronze'));a=p.parse_args();run(a.raw_dir,a.output)
