"""최종 OUTFILE ZIP을 Pandas로 읽어 표준·키·참조·업무 규칙을 재검증한다."""
from pathlib import Path
import argparse,csv,io,json,re,zipfile,hashlib,datetime
from decimal import Decimal
import pandas as pd
ROOT=Path(__file__).resolve().parents[1]
FIELD=re.compile(r'"(?:\\.|[^"\\])*"|[^,\r\n]*');ESC=re.compile(r'\\(.)');EM={'0':'\0','b':'\b','n':'\n','r':'\r','t':'\t','Z':'\x1a'}
def parse_line(line):
 line=line.rstrip('\r\n');row=[];pos=0
 while True:
  m=FIELD.match(line,pos)
  if not m:raise ValueError('잘못된 CSV 필드')
  raw=m.group();end=m.end();v=None if raw==r'\N' else raw[1:-1] if raw.startswith('"') else raw
  if v is not None and '\\' in v:v=ESC.sub(lambda q:EM.get(q[1],q[1]),v)
  row.append(v)
  if end==len(line):return row
  if line[end]!=',':raise ValueError('잘못된 CSV 구분자')
  pos=end+1

def run(source):
 catalog=json.loads((ROOT/'metadata/catalog.json').read_text());scope=json.loads((ROOT/'metadata/scope.json').read_text());schemas={t:sorted([c for c in catalog['documentation_column_catalog_v1'] if c['table_name']==t],key=lambda c:int(c['column_position'])) for t in scope};checks=[];profiles=[];dfs={};business=[]
 z=zipfile.ZipFile(source);names={Path(i).name:i for i in z.namelist() if not i.endswith('/')};prefix='kream_repro_full_' if any(n.startswith('kream_repro_full_') for n in names) else 'kream_full_'
 def frame(name,columns):
  with z.open(names[name]) as f:
   rows=[parse_line(line) for line in io.TextIOWrapper(f,encoding='utf-8-sig',newline='')]
  if any(len(r)!=len(columns) for r in rows):raise ValueError(name+' 컬럼 수 불일치')
  return pd.DataFrame(rows,columns=columns,dtype='string')
 manifest=frame(prefix+'export_manifest_v1.csv',['export_order','table_name','output_file_name','table_role','actual_rows','expected_rows','column_count','row_count_status','export_version','captured_at_kst']).set_index('table_name')
 def add(table,column,rule,checked,failed,detail):
  checks.append(dict(table_name=table,column_name=column,rule_id=rule,checked_rows=int(checked),failed_rows=int(failed),compliance_pct=round(100*(checked-failed)/checked,8) if checked else None,status='PASS' if failed==0 and checked else 'NO_VALUES' if not checked else 'FAIL',definition=detail))
 for t,cs in schemas.items():
  df=frame(prefix+t+'.csv',[c['column_name'] for c in cs]);dfs[t]=df;n=len(df);add(t,'*','ROW_COUNT',1,int(n!=int(manifest.loc[t,'actual_rows'])),'최종 추출 목록의 실제 행 수 대조')
  for c in cs:
   name=c['column_name'];s=df[name];nonnull=s.dropna();typ=c['column_type'];valid=pd.Series(True,index=nonnull.index)
   if c['is_nullable']=='NO':add(t,name,'REQUIRED',n,int(s.isna().sum()),'SQL NULL 허용 여부. 빈 문자열은 별도 집계')
   length=re.search(r'^(?:var)?char\((\d+)\)',typ)
   if length:valid=nonnull.str.len()<=int(length[1])
   elif typ in ['date','datetime']:
    fmt='%Y-%m-%d' if typ=='date' else '%Y-%m-%d %H:%M:%S';pat=r'\d{4}-\d{2}-\d{2}' if typ=='date' else r'\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}'
    valid=nonnull.str.fullmatch(pat)&pd.to_datetime(nonnull,format=fmt,errors='coerce').notna()
   elif typ.startswith('decimal'):
    p,scale=map(int,re.search(r'\((\d+),(\d+)\)',typ).groups())
    def dec_ok(v):
     try:return bool(re.fullmatch(r'-?\d+(?:\.\d+)?',v)) and len(v.split('.')[1] if '.' in v else '')<=scale and abs(Decimal(v))<Decimal(10)**(p-scale)
     except Exception:return False
    valid=nonnull.map(dec_ok)
   elif typ.startswith(('bigint','int','tinyint')):
    bits=64 if typ.startswith('bigint') else 8 if typ.startswith('tinyint') else 32;unsigned='unsigned' in typ;lo=0 if unsigned else -(2**(bits-1));hi=2**(bits if unsigned else bits-1)-1
    valid=nonnull.map(lambda v:bool(re.fullmatch(r'-?\d+',v)) and lo<=int(v)<=hi)
   elif typ in ['text','longtext','mediumtext']:
    limit={'text':65535,'mediumtext':16777215,'longtext':4294967295}[typ];valid=nonnull.map(lambda v:len(v.encode('utf-8'))<=limit)
   add(t,name,'PHYSICAL_DOMAIN',len(nonnull),int((~valid).sum()),typ+' 형식·길이·범위. NULL은 별도 검사')
   profiles.append(dict(table_name=t,column_name=name,rows=n,sql_null_rows=int(s.isna().sum()),empty_string_rows=int((s=='').fillna(False).sum()),distinct_nonnull=int(s.nunique(dropna=True)),max_char_length=int(nonnull.str.len().max()) if len(nonnull) else None))
  grouped={}
  for c in catalog['documentation_constraint_catalog_v1']:
   if c['table_name']==t and c['constraint_type'] in ['PRIMARY KEY','UNIQUE']:grouped.setdefault((c['constraint_type'],c['constraint_name']),[]).append(c)
  for (kind,key),kc in grouped.items():
   columns=[c['column_name'] for c in sorted(kc,key=lambda x:int(x['column_position']))];sub=df.dropna(subset=columns);add(t,','.join(columns),kind+':'+key,len(sub),int(sub.duplicated(columns).sum()),'키가 같은 두 번째 이후 행 수. UNIQUE의 NULL은 MySQL 규칙 적용')
  print(t,n,flush=True)
 def enum(t,c,values):
  s=dfs[t][c].dropna();add(t,c,'ALLOWED_CODES',len(s),int((~s.isin(values)).sum()),' | '.join(values));business.append(dict(table_name=t,column_name=c,domain_rule='ALLOWED_CODES',allowed_values=' | '.join(values),source='명세·합의된 정제 정책과 실제 CHECK 제약조건'))
 enum('silver_category_parent_lookup','CAT_LEVEL',['TOP_LEVEL','BRAND_LINE']);enum('silver_inspector_master','ACTIVE_YN',['Y','N']);enum('silver_product_std_dict','BANNED_WORD_YN',['Y','N']);enum('silver_product_std_dict','CODE_TYPE',['ITEM_MODEL','BANNED_WORD','INSP_RESULT','DEPT_STD','BANNED_DEPT'])
 for t in ['silver_inspection','silver_inspection_join_ready']:enum(t,'INSP_RESULT',['PASS','FAKE_REJECT','CLAIM_FAKE_PASS','BOX_DMG_HOLD'])
 patterns={'INSP_ID':r'INSP_[0-9]{6}','INSPECTOR_EMP_NO':r'KRM[0-9]{6}','EMP_NO':r'KRM[0-9]{6}','CAT_ID':r'CAT_[0-9]{5}','PARENT_CAT_ID':r'CAT_[0-9]{5}'}
 for t in scope:
  df=dfs[t]
  for c,pat in patterns.items():
   if c in df:
    s=df[c].dropna();add(t,c,'IDENTIFIER_FORMAT',len(s),int((~s.str.fullmatch(pat)).sum()),pat);business.append(dict(table_name=t,column_name=c,domain_rule='IDENTIFIER_FORMAT',allowed_values=pat,source='확정된 ID 정규화 및 표준 형식'))
  for c in df:
   if (c.endswith(('_rows','_minutes','_duration_min')) or c in ['TRADE_PRICE_KRW','INSP_DURATION_MIN','COMPENSATION_LOSS_KRW','BASE_RETAIL_KRW','FAKE_PENALTY_MULTIPLIER','duration_min','available_minutes_per_person','estimated_required_people']) and c not in ['inspection_error','duration_error_min']:
    s=df[c].dropna();add(t,c,'NONNEGATIVE',len(s),int(s.map(lambda v:Decimal(v)<0).sum()),'행 수·금액·소요시간·배수는 0 이상')
  if 'claim_rate_pct' in df:
   s=df['claim_rate_pct'].dropna();add(t,'claim_rate_pct','CLAIM_RATE_RANGE',len(s),int(s.map(lambda v:not Decimal(0)<=Decimal(v)<=Decimal(100)).sum()),'청구 건수 비율 0부터 100. 손실률은 100을 넘을 수 있음')
 fact=dfs['silver_inspection'];joined=dfs['silver_inspection_join_ready'];emp=dfs['silver_inspector_master'];cat=dfs['silver_category_parent_lookup'];dictionary=dfs['silver_product_std_dict']
 for c,master,key in [('INSPECTOR_EMP_NO',emp,'EMP_NO'),('PARENT_CAT_ID',cat,'CAT_ID')]:
  s=fact[c].dropna();add('silver_inspection',c,'REFERENCE',len(s),int((~s.isin(master[key])).sum()),'정상 마스터 키 참조')
 items=dictionary[dictionary.CODE_TYPE=='ITEM_MODEL'];s=fact.ITEM_STD_CODE.dropna();add('silver_inspection','ITEM_STD_CODE','PRODUCT_DICTIONARY',len(s),int((~s.isin(items.STD_CODE)).sum()),'ITEM_MODEL 유형의 표준 코드 대조')
 add('silver_product_std_dict','CODE_TYPE,STD_CODE','SCOPED_CODE_UNIQUENESS',len(dictionary),int(dictionary.duplicated(['CODE_TYPE','STD_CODE']).sum()),'유형별 코드 유일성. 물리 UNIQUE 제약과 구분')
 itemmap=items.set_index('STD_CODE').STD_KOR_NM;add('silver_inspection','ITEM_NM','STANDARD_PRODUCT_NAME',len(fact),int((fact.ITEM_NM!=fact.ITEM_STD_CODE.map(itemmap)).fillna(True).sum()),'유효 상품 코드의 표준명과 일치')
 add('silver_inspection','INBOUND_DT,INSP_DONE_DT,EXTRACTED_AT','TIME_ORDER',len(fact),int((~((fact.INBOUND_DT<=fact.INSP_DONE_DT)&(fact.INSP_DONE_DT<=fact.EXTRACTED_AT))).sum()),'KST 입고 <= 완료 <= 추출')
 add('silver_inspection','REV_NO','REVISION_RANGE',len(fact),int(fact.REV_NO.map(lambda v:int(v)<1).sum()),'개정 번호는 1 이상')
 shared=[c for c in fact if c not in ['source_bronze_row_id','source_file','rule_version']];comp=joined[shared].merge(fact[shared],on=['INSP_ID','REV_NO'],how='outer',suffixes=('_join','_fact'),indicator=True,validate='one_to_one');bad=comp['_merge']!='both'
 for c in shared:
  if c in ['INSP_ID','REV_NO']:continue
  bad|=comp[c+'_join'].fillna('__SQL_NULL__')!=comp[c+'_fact'].fillna('__SQL_NULL__')
 add('silver_inspection_join_ready',','.join(shared),'REJOIN_FACT',len(comp),int(bad.sum()),'공유 업무 컬럼 전체가 정상 검수와 일치')
 for source_column,master,key,fields in [('INSPECTOR_EMP_NO',emp,'EMP_NO',{'INSPECTOR_EMP_NM':'EMP_NM','INSPECTOR_DEPT_NM':'DEPT_NM','INSPECTOR_POSITION_NM':'POSITION_NM'}),('PARENT_CAT_ID',cat,'CAT_ID',{'PARENT_CAT_NM':'CAT_NM'})]:
  lookup=master.set_index(key)
  for c,mc in fields.items():
   expected=joined[source_column].map(lookup[mc]);add('silver_inspection_join_ready',c,'REJOIN_MASTER',len(joined),int((joined[c].fillna('__SQL_NULL__')!=expected.fillna('__SQL_NULL__')).sum()),'사번 또는 카테고리 키로 정규 마스터 재조인')
 loss=[Decimal(p)*3 if r=='CLAIM_FAKE_PASS' else Decimal(0) for p,r in zip(joined.TRADE_PRICE_KRW,joined.INSP_RESULT)];add('silver_inspection_join_ready','COMPENSATION_LOSS_KRW','COMPENSATION',len(joined),sum(Decimal(x)!=y for x,y in zip(joined.COMPENSATION_LOSS_KRW,loss)),'CLAIM_FAKE_PASS이면 거래가 × 3, 그 외 0. Decimal로 검증')
 grouped={}
 for c in catalog['documentation_constraint_catalog_v1']:
  if c['constraint_type']=='FOREIGN KEY':grouped.setdefault((c['table_name'],c['constraint_name'],c['referenced_table']),[]).append(c)
 for (t,name,target),cs in grouped.items():
  cs.sort(key=lambda c:int(c['column_position']));left=[c['column_name'] for c in cs];right=[c['referenced_column'] for c in cs];sub=dfs[t].dropna(subset=left);keys=pd.MultiIndex.from_frame(dfs[target][right]);idx=pd.MultiIndex.from_frame(sub[left]);add(t,','.join(left),'PHYSICAL_FK:'+name,len(sub),int((~idx.isin(keys)).sum()),target+'('+','.join(right)+')')
 cutoff='2026-08-31 23:59:59';d=dfs['gold_prediction_input_record_v1'];add('gold_prediction_input_record_v1','insp_done_dt_kst,extracted_at_kst','CUTOFF_LEAKAGE',len(d),int(((d.insp_done_dt_kst>cutoff)|(d.extracted_at_kst>cutoff)|(d.prediction_cutoff_kst!=cutoff)).sum()),'검수 완료와 추출 시각 모두 예측 기준 시각 이내')
 d=dfs['gold_inspection_workload_hourly_v1'];add('gold_inspection_workload_hourly_v1','done_hour_kst','HOUR_RANGE',len(d),int(d.done_hour_kst.map(lambda v:not 0<=int(v)<=23).sum()),'시간대 0부터 23')
 out=ROOT/'reports';out.mkdir(exist_ok=True)
 pd.DataFrame(checks).to_csv(out/'pandas_standard_checks.csv',index=False,encoding='utf-8-sig');pd.DataFrame(profiles).to_csv(out/'pandas_column_profile.csv',index=False,encoding='utf-8-sig');pd.DataFrame(business).to_csv(ROOT/'dictionaries/business_domains.csv',index=False,encoding='utf-8-sig');dictionary.to_csv(ROOT/'dictionaries/standard_codes.csv',index=False,encoding='utf-8-sig')
 results=pd.DataFrame(checks);summary=dict(executed_at_kst=datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=9))).isoformat(),source_sha256=hashlib.file_digest(open(source,'rb'),'sha256').hexdigest(),pandas_version=pd.__version__,tables=len(dfs),columns=len(profiles),physical_table_rows=sum(len(x) for x in dfs.values()),checks=len(checks),failed_checks=int((results.failed_rows>0).sum()),failed_rule_row_evaluations=int(results.failed_rows.sum()),checked_rule_row_evaluations=int(results.checked_rows.sum()),standard_compliance_pct=100*(1-results.failed_rows.sum()/results.checked_rows.sum()),scope=scope,quality_snapshot=catalog['data_quality_check_results_v1'],per_table_rows={t:len(d) for t,d in dfs.items()})
 (out/'pandas_verification_summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps({k:v for k,v in summary.items() if k not in ['scope','quality_snapshot','per_table_rows']},ensure_ascii=False));return summary
if __name__ == '__main__':
 p = argparse.ArgumentParser()
 p.add_argument('--source', type=Path, required=True)
 args = p.parse_args()
 summary = run(args.source)
 # 검사 실패를 명령 실행의 실패 상태로 전달한다.
 raise SystemExit(1 if summary['failed_checks'] > 0 else 0)
