"""입력 기간·예측·평가 오차·가용시간 시나리오를 원자료에서 독립 검산한다."""
from pathlib import Path
from decimal import Decimal,ROUND_HALF_UP,ROUND_CEILING
import argparse,json
import pandas as pd
from evidence_csv import Export,ROOT
D=Decimal
Q=lambda v:D(v).quantize(D('.0001'),rounding=ROUND_HALF_UP)
def run(source):
 x=Export(source);checks=[]
 def check(name,a,b):
  row={'check':name,'actual':str(a),'expected':str(b),'passed':a==b};checks.append(row)
  if not row['passed']:raise AssertionError(row)
 rec=x.read('gold_prediction_input_record_v1');daily=x.read('gold_prediction_input_daily_v1');actual=x.read('gold_prediction_actual_daily_v1');forecast=x.read('gold_workload_forecast_v1');summary=x.read('gold_workload_forecast_summary_v1');evaluation=x.read('gold_workload_forecast_evaluation_v1');staff=x.read('gold_staffing_scenario_v1')
 check('INPUT_RECORDS',len(rec),8173);check('INPUT_MINUTES',sum(rec.duration_min.map(D)),D('126839'));check('INPUT_DAYS',len(daily),28);check('TRAINING_START',daily.inspection_date.min(),'2026-08-04');check('TRAINING_END',daily.inspection_date.max(),'2026-08-31')
 check('CUTOFF',int(((rec.insp_done_dt_kst>'2026-08-31 23:59:59')|(rec.extracted_at_kst>'2026-08-31 23:59:59')).sum()),0);check('ACTUAL_RECORDS',sum(actual.actual_inspection_rows.map(int)),2012);check('ACTUAL_MINUTES',sum(actual.actual_duration_min.map(D)),D('30443'))
 daily['weekday']=pd.to_datetime(daily.inspection_date).dt.dayofweek
 for r in forecast.itertuples():
  base=daily if r.forecast_method=='RECENT_28_DAY_MEAN' else daily[daily.weekday==pd.Timestamp(r.forecast_date).dayofweek]
  check(r.forecast_method+'_'+r.forecast_date+'_COUNT',D(r.predicted_inspection_rows),Q(sum(base.inspection_rows.map(D))/len(base)));check(r.forecast_method+'_'+r.forecast_date+'_MINUTES',D(r.predicted_duration_min),Q(sum(base.total_duration_min.map(D))/len(base)))
 lookup=actual.set_index('inspection_date')
 for method,e in evaluation.groupby('forecast_method'):
  for r in e.itertuples():
   check(method+'_'+r.forecast_date+'_ACTUAL_COUNT',int(r.actual_inspection_rows),int(lookup.loc[r.forecast_date,'actual_inspection_rows']));check(method+'_'+r.forecast_date+'_ACTUAL_MINUTES',D(r.actual_duration_min),D(lookup.loc[r.forecast_date,'actual_duration_min']))
  s=summary[summary.forecast_method==method].iloc[0];errors_count=sum(abs(D(r.predicted_inspection_rows)-D(r.actual_inspection_rows)) for r in e.itertuples());errors_time=sum(abs(D(r.predicted_duration_min)-D(r.actual_duration_min)) for r in e.itertuples());den_count=sum(e.actual_inspection_rows.map(D));den_time=sum(e.actual_duration_min.map(D))
  check(method+'_COUNT_WAPE',D(s.inspection_wape_pct),Q(errors_count/den_count*100));check(method+'_TIME_WAPE',D(s.duration_wape_pct),Q(errors_time/den_time*100));check(method+'_COUNT_MAE',D(s.inspection_mae),Q(errors_count/len(e)));check(method+'_TIME_MAE',D(s.duration_mae_min),Q(errors_time/len(e)))
 for r in staff.itertuples():check(r.forecast_method+'_'+r.forecast_date+'_'+r.scenario_name,int(r.estimated_required_people),int((D(r.predicted_duration_min)/D(r.available_minutes_per_person)).to_integral_value(rounding=ROUND_CEILING)))
 report={'checks':checks,'failed_checks':sum(not r['passed'] for r in checks),'count':len(checks)};(ROOT/'evidence/forecast_verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print('forecast checks',len(checks),'failed',report['failed_checks']);x.close()
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);a=p.parse_args();run(a.source)
