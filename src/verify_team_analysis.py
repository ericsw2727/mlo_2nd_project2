"""팀 발표의 기간·분모별 지표를 최종 CSV에서 다시 계산하고 원자료를 저장한다."""
from pathlib import Path
import argparse,datetime,hashlib,json
from decimal import Decimal
import pandas as pd
from evidence_csv import Export,ROOT

def run(source):
 out=ROOT/'reports/team_analysis';out.mkdir(parents=True,exist_ok=True);x=Export(source);checks=[]
 def check(key,actual,expected):
  passed=actual==expected;checks.append({'check':key,'actual':str(actual),'expected':str(expected),'passed':passed})
  if not passed:raise AssertionError(checks[-1])
 def save(df,name,index=False):df.to_csv(out/(name+'.csv'),index=index,encoding='utf-8-sig')
 a=x.read('silver_inspection_join_ready');a['REV_NO']=a.REV_NO.astype(int);a['duration']=pd.to_numeric(a.INSP_DURATION_MIN);a['claim']=(a.INSP_RESULT=='CLAIM_FAKE_PASS').astype(int);a['loss']=a.COMPENSATION_LOSS_KRW.map(Decimal)
 general=a[(a.REV_NO==1)&(a.INSP_DONE_DT>='2022-01-01')&(a.INSP_DONE_DT<'2026-09-01')].copy();reinspect=a[(a.REV_NO>=2)&(a.INSP_DONE_DT>='2026-10-01')&(a.INSP_DONE_DT<'2026-11-01')].copy()
 def risk(df):
  t=df.groupby('INSPECTOR_DEPT_NM').agg(inspection_rows=('INSP_ID','size'),claim_rows=('claim','sum'),compensation_krw=('loss','sum'));t['claim_rate_pct']=t.claim_rows/t.inspection_rows*100;return t
 g,r=risk(general),risk(reinspect);save(g,'general_department_risk',True);save(r,'reinspection_department_risk',True)
 check('GENERAL_COHORT_ROWS',len(general),243454);check('REINSPECTION_COHORT_ROWS',len(reinspect),21656)
 expected_g={'외주야간검수팀':(633,'59.20'),'스니커즈검수1팀':(445,'36.11'),'명품백감정팀':(327,'27.40'),'스니커즈검수2팀':(313,'22.99'),'클레임재검수팀':(212,'17.10'),'스트릿의류검수팀':(217,'17.02'),'럭셔리워치감정팀':(167,'12.51'),'테크레고검수팀':(132,'10.55')}
 expected_r={'스니커즈검수1팀':(4804,3753,'298.88'),'스니커즈검수2팀':(3733,2903,'223.50'),'명품백감정팀':(3012,2353,'188.31'),'외주야간검수팀':(2448,1928,'152.69'),'스트릿의류검수팀':(2655,2063,'146.93'),'럭셔리워치감정팀':(1766,1378,'126.06'),'테크레고검수팀':(1637,1263,'98.26'),'클레임재검수팀':(1601,1255,'99.95')}
 for dept,(count,money) in expected_g.items():
  check('FIG01_CLAIMS_'+dept,int(g.loc[dept,'claim_rows']),count);check('FIG01_AMOUNT_'+dept,f"{g.loc[dept,'compensation_krw']/Decimal(10**8):.2f}",money)
 for dept,(count,claim,money) in expected_r.items():
  check('FIG04_ROWS_'+dept,int(r.loc[dept,'inspection_rows']),count);check('FIG04_CLAIMS_'+dept,int(r.loc[dept,'claim_rows']),claim);check('FIG04_AMOUNT_'+dept,f"{r.loc[dept,'compensation_krw']/Decimal(10**8):.2f}",money)
 check('SNK1_REINSPECTION_RATE',round(float(r.loc['스니커즈검수1팀','claim_rate_pct']),2),78.12);check('SNK2_REINSPECTION_RATE',round(float(r.loc['스니커즈검수2팀','claim_rate_pct']),2),77.77)
 short=general.assign(short=(general.duration<10).astype(int)).groupby('INSPECTOR_DEPT_NM').agg(rows=('INSP_ID','size'),under10=('short','sum'));short['under10_pct']=short.under10/short.rows*100;save(short,'general_duration_under10',True)
 external=general[general.INSPECTOR_DEPT_NM=='외주야간검수팀'];others=general[general.INSPECTOR_DEPT_NM!='외주야간검수팀'];check('OUTSOURCE_UNDER10_PCT',round(float((external.duration<10).mean()*100),2),93.65);check('OTHER_UNDER10_PCT',round(float((others.duration<10).mean()*100),2),28.78)
 save(general.groupby('INSPECTOR_DEPT_NM').duration.describe(percentiles=[.25,.5,.75]),'general_duration_distribution',True)
 product_counts=pd.crosstab(general.ITEM_STD_CODE,general.INSPECTOR_DEPT_NM);product_claims=pd.crosstab(general.ITEM_STD_CODE,general.INSPECTOR_DEPT_NM,values=general.claim,aggfunc='sum').fillna(0).astype(int);product_rates=product_claims/product_counts*100;product_share=product_counts.div(product_counts.sum(axis=0),axis=1)*100
 save(product_counts,'product_department_counts',True);save(product_claims,'product_department_claims',True);save(product_rates,'product_department_error_rate_pct',True);save(product_share,'product_department_share_pct',True)
 check('ALL_TEAMS_19_OBSERVED_MODELS',bool(((product_counts>0).sum()==19).all()),True);check('PRODUCT_COUNTS_MATCH_GENERAL',int(product_counts.to_numpy().sum()),len(general))
 independently=general.groupby(['ITEM_STD_CODE','INSPECTOR_DEPT_NM']).agg(n=('INSP_ID','size'),claims=('claim','sum')).unstack('INSPECTOR_DEPT_NM');check('HEATMAP_COUNTS_SECOND_CALCULATION',bool(independently['n'].equals(product_counts)),True);check('HEATMAP_CLAIMS_SECOND_CALCULATION',bool(independently['claims'].equals(product_claims)),True)
 emp=x.read('silver_inspector_master');check('CURRENT_MASTER_ROWS',len(emp),2960);staff=pd.crosstab(emp.DEPT_NM,emp.POSITION_NM);save(staff,'department_position_counts',True);save(staff.div(staff.sum(axis=1),axis=0)*100,'department_position_share_pct',True)
 expected_staff={'스니커즈검수1팀':641,'스니커즈검수2팀':491,'명품백감정팀':411,'스트릿의류검수팀':387,'외주야간검수팀':387,'럭셔리워치감정팀':232,'테크레고검수팀':221,'클레임재검수팀':190}
 for dept,count in expected_staff.items():check('FIG06_HEADCOUNT_'+dept,int(staff.loc[dept].sum()),count)
 latest=pd.crosstab(a.INSPECTOR_DEPT_NM,a.REV_NO);latest.columns=['FIRST' if int(c)==1 else 'REINSPECTION' for c in latest.columns];save(latest,'latest_revision_mix_counts',True);save(latest.div(latest.sum(axis=1),axis=0)*100,'latest_revision_mix_pct',True)
 hourly=x.read('gold_inspection_workload_hourly_v1');hourly['inspection_event_rows']=hourly.inspection_event_rows.astype(int);work=hourly.pivot_table(index='department_name',columns='event_type',values='inspection_event_rows',aggfunc='sum',fill_value=0);save(work,'valid_workload_mix_counts',True);save(work.div(work.sum(axis=1),axis=0)*100,'valid_workload_mix_pct',True)
 check('VALID_WORK_EVENT_ROWS',int(work.to_numpy().sum()),291548);check('FIRST_WORK_ROWS',int(work.FIRST_INSPECTION.sum()),269892);check('REINSPECTION_WORK_ROWS',int(work.REINSPECTION.sum()),21656)
 q=x.read('quarantine_inspection');e=x.read('excluded_inspection');check('ROW_ACCOUNTING',len(a)+len(q)+len(e),335000)
 reason=e.primary_reason.value_counts();check('EXCLUDED_DUPLICATE',int(reason['IDENTICAL_DUPLICATE']),9598);check('EXCLUDED_SUPERSEDED',int(reason['SUPERSEDED_VALID_REVISION']),19761)
 quality=x.read('data_quality_check_results_v1');save(quality,'sql_quality_snapshot');status=quality.check_status.value_counts().to_dict();check('SQL_QUALITY_PASS',int(status.get('PASS',0)),14);check('SQL_NOT_CHECKED',int(status.get('NOT_CHECKED',0)),1);check('SQL_RECORDED_DIFFERENCE',int(status.get('RECORDED_DIFFERENCE',0)),1)
 report={'executed_at_kst':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=9))).isoformat(),'source_sha256':hashlib.file_digest(open(source,'rb'),'sha256').hexdigest(),'checks':checks,'failed_checks':sum(not c['passed'] for c in checks),'scope':{'general':'최종 Silver, REV_NO=1, 2022-01-01 이상 2026-09-01 미만, 현재 마스터 소속','reinspection':'최종 Silver, REV_NO>=2, 2026-10-01 이상 2026-11-01 미만, 현재 마스터 소속','latest_mix':'전체 최종 Silver 271787건의 개정 구분','workload_mix':'유효 최초·재검수 작업 이력 291548건','staff':'현재 정상 검수원 마스터 2960명. Y와 N 모두 포함'},'general_rows':len(general),'general_claims':int(general.claim.sum()),'reinspection_rows':len(reinspect),'reinspection_claims':int(reinspect.claim.sum()),'outsource_under10_pct':float((external.duration<10).mean()*100),'other_under10_pct':float((others.duration<10).mean()*100),'staff':expected_staff}
 (out/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps({k:v for k,v in report.items() if k not in ['checks','staff']},ensure_ascii=False,indent=2));print('checks',len(checks));x.close()
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);a=p.parse_args();run(a.source)
