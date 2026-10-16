"""공급 원본의 오염과 정제 결과의 적용 근거를 독립적으로 대조한다."""
from pathlib import Path
import argparse,io,json,re,zipfile,collections,datetime
from decimal import Decimal,ROUND_HALF_UP
import pandas as pd
from profile_bronze import FILES,NULLS,normalize
from verify_final import parse_line
ROOT=Path(__file__).resolve().parents[1]
def date_kst(s):
 result=pd.Series(pd.NaT,index=s.index,dtype='datetime64[ns]')
 formats=[(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z','%Y-%m-%dT%H:%M:%SZ',True),(r'\d{14}','%Y%m%d%H%M%S',False),(r'\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}','%Y-%m-%d %H:%M:%S',False),(r'\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}','%Y/%m/%d %H:%M:%S',False),(r'\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}:\d{2}','%Y.%m.%d %H:%M:%S',False)]
 for pat,fmt,utc in formats:
  mask=s.str.fullmatch(pat);values=pd.to_datetime(s[mask],format=fmt,errors='coerce');result.loc[mask]=values+pd.Timedelta(hours=9) if utc else values
 return result

def price(v):
 if v.strip().upper() in NULLS:return None,'MISSING_PRICE'
 if re.fullmatch(r'-[0-9]+(?:\.[0-9]+)?',v):return None,'NEGATIVE_PRICE'
 if re.fullmatch(r'[0-9]{1,12}(?:\.[0-9]{1,4})?',v):return Decimal(v),'CONVERTED'
 if re.fullmatch(r'(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)원',v) and len(v[:-1].replace(',',''))<=12:return Decimal(v[:-1].replace(',','')),'CONVERTED'
 if re.fullmatch(r'[0-9]{1,12}(?:\.[0-9]{1,4})?만원',v):return Decimal(v[:-2])*10000,'CONVERTED'
 if re.fullmatch(r'\$[0-9]{1,12}(?:\.[0-9]{1,4})?',v):return Decimal(v[1:])*1350,'CONVERTED'
 return None,'PRICE_FORMAT_OR_RANGE_REVIEW'
def duration(v):
 if v.strip()=='-999':return None,'SENTINEL_MINUS_999'
 if v.strip().upper() in NULLS:return None,'MISSING_DURATION'
 if re.fullmatch(r'[0-9]{1,9}(?:\.[0-9]{1,4})?',v):return Decimal(v),'CONVERTED'
 if re.fullmatch(r'[0-9]{1,9}분\(min\)',v):return Decimal(v[:-6]),'CONVERTED'
 if re.fullmatch(r'[0-9]{1,9}초\(sec\)',v):return Decimal(v[:-6])/60,'CONVERTED'
 if re.fullmatch(r'[0-9]{1,9}s',v):return Decimal(v[:-1])/60,'CONVERTED'
 return None,'DURATION_FORMAT_OR_RANGE_REVIEW'

def run(raw_dir,final_zip,out):
 out.mkdir(parents=True,exist_ok=True);catalog=json.loads((ROOT/'metadata/catalog.json').read_text());schemas={t['table_name']:[c['column_name'] for c in sorted([c for c in catalog['documentation_column_catalog_v1'] if c['table_name']==t['table_name']],key=lambda x:int(x['column_position']))] for t in catalog['documentation_table_catalog_v1']}
 z=zipfile.ZipFile(final_zip);names={Path(n).name:n for n in z.namelist() if not n.endswith('/')};prefix='kream_repro_full_' if any(n.startswith('kream_repro_full_') for n in names) else 'kream_full_'
 def records(t):
  with z.open(names[prefix+t+'.csv']) as f:
   for line in io.TextIOWrapper(f,encoding='utf-8-sig',newline=''):yield dict(zip(schemas[t],parse_line(line)))
 def frame(t):return pd.DataFrame(records(t),dtype='string')
 raw={name:pd.read_csv(raw_dir/name,dtype='string',keep_default_na=False,na_filter=False,encoding='utf-8-sig') for name in FILES};fact=raw['kream_inspection_300000.csv'];emp=raw['kream_inspector_master.csv'];n=len(fact);metrics=[];checks=[]
 def metric(c,rule,count,meaning,denominator=None):
  d=n if denominator is None else denominator;metrics.append(dict(source_file='kream_inspection_300000.csv' if denominator is None else c,column_name=c,issue=rule,rows=int(count),denominator=int(d),ratio_pct=round(count/d*100,6) if d else None,meaning=meaning))
 def check(name,checked,failed,meaning):checks.append(dict(check=name,checked_rows=int(checked),failed_rows=int(failed),status='PASS' if failed==0 else 'FAIL',definition=meaning))
 dates={c:date_kst(fact[c]) for c in ['INBOUND_DT','INSP_DONE_DT','EXTRACTED_AT']};invalid=pd.DataFrame({k:v.isna() for k,v in dates.items()}).any(axis=1);done_before=dates['INSP_DONE_DT']<dates['INBOUND_DT'];extract_before=dates['EXTRACTED_AT']<dates['INSP_DONE_DT'];time_error=invalid|done_before|extract_before
 metric('DATETIME','UNPARSEABLE_TIME',invalid.sum(),'어느 필수 시각이든 지원 형식이나 실제 달력 해석 실패');metric('DATETIME','DONE_BEFORE_INBOUND',done_before.sum(),'검수 완료가 입고보다 빠름');metric('DATETIME','EXTRACTED_BEFORE_DONE',extract_before.sum(),'추출이 완료보다 빠름');metric('DATETIME','TIME_ORDER_ERROR_UNIQUE',time_error.sum(),'필수 시각 해석 실패 또는 시간 역전의 고유 행 수')
 pv=[price(v) for v in fact.TRADE_PRICE_KRW];dv=[duration(v) for v in fact.INSP_DURATION_MIN]
 for c,values in [('TRADE_PRICE_KRW',pv),('INSP_DURATION_MIN',dv)]:
  for status,count in collections.Counter(x[1] for x in values).items():metric(c,status,count,'정의된 단위·형식에 따른 원본 해석 상태. CONVERTED는 변환 가능한 정상 후보')
 for c,kind,pat in [('INSP_ID','INSP',r'INSP_[0-9]{6}'),('INSPECTOR_EMP_NO','KRM',r'KRM[0-9]{6}'),('PARENT_CAT_ID','CAT',r'CAT_[0-9]{5}')]:
  s=normalize(fact[c],kind);metric(c,'NORMALIZATION_CHANGED',s.ne(fact[c]).sum(),'명세와 확정 규칙에 따른 표기 정규화 후보');metric(c,'INVALID_FORMAT_AFTER_NORMALIZATION',(~s.str.fullmatch(pat)).sum(),'정규화 후 형식 불일치. 결측과 마스터 참조 문제는 별도 판단')
 dict_df=frame('silver_product_std_dict');emp_df=frame('silver_inspector_master');cat_df=frame('silver_category_parent_lookup');models=dict_df[dict_df.CODE_TYPE=='ITEM_MODEL'].set_index('STD_CODE').STD_KOR_NM
 metric('ITEM_NM','NOT_EXACT_STANDARD_NAME',fact.ITEM_NM.ne(fact.ITEM_STD_CODE.map(models)).fillna(True).sum(),'원본 상품 코드를 기준으로 공식 표준명과 정확히 일치하지 않는 행. 복구 가능 여부와 구분')
 result_codes=set(dict_df.loc[dict_df.CODE_TYPE=='INSP_RESULT','STD_CODE']);metric('INSP_RESULT','NONSTANDARD_RAW_RESULT',(~fact.INSP_RESULT.isin(result_codes)).sum(),'원본 판정이 사전의 표준 코드와 정확히 일치하지 않음')
 for c,kind,master,key in [('INSPECTOR_EMP_NO','KRM',emp_df,'EMP_NO'),('PARENT_CAT_ID','CAT',cat_df,'CAT_ID')]:metric(c,'NO_VALID_SILVER_MASTER',(~normalize(fact[c],kind).isin(master[key])).sum(),'정규화 후보가 최종 정상 마스터에 없는 행. 결측·유령·격리 마스터 참조를 포함하며 복구 전 진단')
 nonstandard=(~emp.ACTIVE_YN.isin(['Y','N']));metric('kream_inspector_master.csv','NONSTANDARD_ACTIVE_CODE',nonstandard.sum(),'원본이 정확히 Y 또는 N이 아닌 행. 확정 정책으로 N 처리',len(emp))
 # 원본의 물리 행 번호를 통해 정상·격리·제외를 연결한다.
 source=fact.to_dict('records');assign={};qids=set();excluded=[];silver=[];q_payload_fail=0;null_representation=0
 original={'original_insp_id':'INSP_ID','original_rev_no':'REV_NO','original_item_std_code':'ITEM_STD_CODE','original_item_name':'ITEM_NM','original_parent_cat_id':'PARENT_CAT_ID','original_trade_price':'TRADE_PRICE_KRW','original_duration':'INSP_DURATION_MIN','original_insp_result':'INSP_RESULT','original_inspector_emp_no':'INSPECTOR_EMP_NO','original_inbound_dt':'INBOUND_DT','original_done_dt':'INSP_DONE_DT','original_extracted_at':'EXTRACTED_AT','original_memo':'INSP_MEMO'}
 for table,kind in [('quarantine_inspection','QUARANTINE'),('excluded_inspection','EXCLUDED')]:
  for r in records(table):
   sid=int(r['bronze_row_id']);assign.setdefault(sid,[]).append(kind)
   if kind=='QUARANTINE':qids.add(sid)
   else:excluded.append(r)
   rawrow=source[sid-1]
   for outfield,infield in original.items():
    value=r[outfield]
    if value is None and rawrow[infield]=='NULL':null_representation+=1
    elif value!=rawrow[infield]:q_payload_fail+=1
 check('AUDIT_ORIGINAL_PAYLOAD',len(original)*(len(qids)+len(excluded)),q_payload_fail,'격리·제외의 원본 13개 필드와 공급 CSV 대조. CSV NULL의 SQL NULL 적재 표현은 별도 계수')
 selected_errors=collections.Counter();selected_counts=collections.Counter();silverids=set()
 for r in records('silver_inspection'):
  sid=int(r['source_bronze_row_id']);assign.setdefault(sid,[]).append('SILVER');silverids.add(sid);silver.append(r);i=sid-1;selected_counts['silver']+=1
  selected_errors['PRICE_FROM_SOURCE']+=pv[i][0] is None or pv[i][0].quantize(Decimal('.0001'),rounding=ROUND_HALF_UP)!=Decimal(r['TRADE_PRICE_KRW'])
  selected_errors['DURATION_FROM_SOURCE']+=dv[i][0] is None or dv[i][0].quantize(Decimal('.0001'),rounding=ROUND_HALF_UP)!=Decimal(r['INSP_DURATION_MIN'])
  for c in dates:
   expected=dates[c].iat[i];selected_errors['TIME_FROM_SOURCE']+=pd.isna(expected) or expected.strftime('%Y-%m-%d %H:%M:%S')!=r[c]
 for name,count in selected_errors.items():check(name,len(silver)*3 if name=='TIME_FROM_SOURCE' else len(silver),count,'원본 물리 행에서 확정한 금액·분 단위·KST 시각 변환과 정상 결과 대조')
 check('SOURCE_PARTITION',n,sum(len(assign.get(i,[]))!=1 for i in range(1,n+1))+sum(i<1 or i>n for i in assign),'원본 335,000행이 정상·격리·제외 중 정확히 한 곳에 존재')
 ids=normalize(fact.INSP_ID,'INSP');g=fact.copy();g['INSP_ID']=ids;group_keys=['INSP_ID','REV_NO'];group_variants=g.drop_duplicates().groupby(group_keys).size();conflict_keys=group_variants[group_variants>1].index;conflict=pd.MultiIndex.from_frame(g[group_keys]).isin(conflict_keys);conflict_ids={i+1 for i,v in enumerate(conflict) if v}
 check('CONFLICT_ALL_QUARANTINED',len(conflict_ids),len(conflict_ids-qids),'동일 검수 ID·개정의 내용 충돌은 양쪽 모두 격리')
 bad_time_ids={i+1 for i,v in enumerate(time_error) if v};check('TIME_ERRORS_QUARANTINED',len(bad_time_ids),len(bad_time_ids-qids),'해석 불가·시간 역전 행 모두 격리')
 check('ACTIVE_POLICY_FROM_RAW',len(emp_df),sum(r.ACTIVE_YN!=('Y' if emp.iloc[int(r.source_bronze_row_id)-1].ACTIVE_YN=='Y' else 'N') for r in emp_df.itertuples()),'원본이 정확히 대문자 Y이면 Y, 나머지는 N')
 bad_numeric={i+1 for i,(p,d) in enumerate(zip(pv,dv)) if p[1]!='CONVERTED' or d[1]!='CONVERTED'}
 check('NUMERIC_ERRORS_QUARANTINED',len(bad_numeric),len(bad_numeric-qids),'금액 결측·음수·해석 실패 또는 소요시간 오류 행은 모두 격리')
 valid=g.loc[[i+1 not in qids for i in range(n)],['INSP_ID','REV_NO']].copy();valid['rev_numeric']=pd.to_numeric(valid.REV_NO,errors='coerce');maximum=valid.groupby('INSP_ID').rev_numeric.max();silverdf=pd.DataFrame(silver)
 check('LATEST_VALID_REVISION',len(silverdf),sum(Decimal(r['REV_NO'])!=Decimal(str(maximum.loc[r['INSP_ID']])) for r in silver),'격리 행을 제거한 뒤 검수 ID별 최고 유효 개정 채택')
 bad_revision2_ids=set(ids.loc[(fact.REV_NO=='2')&pd.Series([i+1 in qids for i in range(n)])]);fallback_count=int(((silverdf.REV_NO=='1')&silverdf.INSP_ID.isin(bad_revision2_ids)).sum())
 # 원천 검수와 조인 통합본의 원본 내용 대응을 직접 검증한다.
 joinraw=raw['kream_inspection_join_ready.csv'];shared=list(fact);fv=fact.to_numpy();jv=joinraw[shared].to_numpy();pairfail=0;paircount=0;seen_inspection=set();seen_join=set()
 for r in records('asis_inspection_join_row_pair_v1'):
  fi=int(r['inspection_bronze_row_id']);ji=int(r['join_ready_bronze_row_id']);paircount+=1
  if not(1<=fi<=len(fact) and 1<=ji<=len(joinraw)) or fi in seen_inspection or ji in seen_join:pairfail+=1;continue
  seen_inspection.add(fi);seen_join.add(ji);pairfail+=any(a!=b for a,b in zip(fv[fi-1],jv[ji-1]))
 check('RAW_SOURCE_PAIRING',paircount,pairfail+abs(n-paircount),'원천·조인 통합본의 13개 공유 필드가 대응 행끼리 같고 원본 물리 행 번호가 일대일인지 확인')
 for base,masterfile,key in [('inspector_master','kream_inspector_master.csv','EMP_NO'),('category_parent_lookup','kream_category_parent_lookup.csv','CAT_ID')]:
  size=len(raw[masterfile]);all_ids=[]
  for t in ['silver_'+base,'quarantine_'+base,'excluded_'+base]:all_ids.extend(int(r['source_bronze_row_id']) for r in records(t))
  counter=collections.Counter(all_ids);check('MASTER_PARTITION_'+key,size,sum(counter[i]!=1 for i in range(1,size+1))+sum(i<1 or i>size for i in counter),'원본 마스터의 모든 물리 행이 정상·격리·제외 중 정확히 한 곳에 존재')

 # 기존 진단 수치와 동일한 정의로 비교한다.
 baseline={'PHYSICAL_INSPECTIONS':(n,335000),'DISTINCT_INSPECTION_IDS':(ids.nunique(),300000),'REVISION_2_ROWS':(int((fact.REV_NO=='2').sum()),22600),'CONFLICT_GROUPS':(len(conflict_keys),2400),'CONFLICT_ROWS':(int(conflict.sum()),4800),'EXACT_DUPLICATE_ROWS':(int(fact.duplicated().sum()),10000),'DONE_BEFORE_INBOUND':(int(done_before.sum()),3165),'EXTRACTED_BEFORE_DONE':(int(extract_before.sum()),2891)}
 comparison=[dict(metric=k,pandas_value=int(a),previous_sql_value=b,difference=int(a)-b,source='이전 SQL 진단 작업 기록. 공급 CSV를 직접 읽어 동일 정의로 재확인') for k,(a,b) in baseline.items()]
 pd.DataFrame(comparison).to_csv(out/'sql_pandas_comparison.csv',index=False,encoding='utf-8-sig');pd.DataFrame(metrics).to_csv(out/'asis_business_diagnosis.csv',index=False,encoding='utf-8-sig');pd.DataFrame(checks).to_csv(out/'source_to_silver_checks.csv',index=False,encoding='utf-8-sig')
 summary=dict(executed_at_kst=datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=9))).isoformat(),pandas_version=pd.__version__,source_files=5,inspection_rows=n,time_order_error_rows=int(time_error.sum()),time_error_overlap_rows=int((done_before&extract_before).sum()),nonstandard_active_rows=int(nonstandard.sum()),fallback_to_revision1_rows=fallback_count,conflict_groups=len(conflict_keys),conflict_rows=int(conflict.sum()),source_checks=len(checks),source_failed_checks=sum(c['failed_rows']>0 for c in checks),source_failed_evaluations=sum(c['failed_rows'] for c in checks),sql_comparison_metrics=len(comparison),sql_comparison_differences=sum(c['difference']!=0 for c in comparison),csv_null_to_sql_null_fields=null_representation,disposition_counts=dict(collections.Counter(v[0] for v in assign.values() if len(v)==1)),metrics=metrics,checks=checks,sql_comparison=comparison)
 (out/'asis_audit_summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps({k:v for k,v in summary.items() if k not in ['metrics','checks','sql_comparison']},ensure_ascii=False))
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--raw-dir',type=Path,required=True);p.add_argument('--final-zip',type=Path,required=True);p.add_argument('--output',type=Path,default=ROOT/'reports/bronze');a=p.parse_args();run(a.raw_dir,a.final_zip,a.output)
