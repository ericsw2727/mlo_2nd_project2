# -*- coding: utf-8 -*-
from data_loader import load_analysis_data, load_staff_data, load_workload_ratio
"""
[과제 1] 외주팀 품질 위험 (2/2)
- 외주야간팀 10분 미만 검수 비중 93.65% 및 부서별 검수시간 사분위수(IQR) 산출
"""
import pandas as pd
import numpy as np

# 1. 정제 데이터 로드 및 분석 모수 필터링 (최초 검수본 243,454건)
df = load_analysis_data()
df['INSP_DONE_DT'] = pd.to_datetime(df['INSP_DONE_DT'], errors='coerce')

df_q1 = df[
    (df['REV_NO'] == 1) & 
    (df['INSP_DONE_DT'] >= '2022-01-01') & 
    (df['INSP_DONE_DT'] <= '2026-08-31 23:59:59')
].copy()

# 2. [헤드라인 통계] 10분 미만 졸속 검수 비중 비교 (외주팀 vs 타 부서)
df_q1['UNDER_10MIN'] = df_q1['INSP_DURATION_MIN'] < 10
is_outsource = df_q1['INSPECTOR_DEPT_NM'] == '외주야간검수팀'

outsource_ratio = (df_q1[is_outsource]['UNDER_10MIN'].mean() * 100).round(2)  # 93.65%
others_ratio    = (df_q1[~is_outsource]['UNDER_10MIN'].mean() * 100).round(2)  # 28.78%

print(f"10분 미만 검수 비중 -> 외주야간팀: {outsource_ratio}%, 타 부서: {others_ratio}%")

# 3. [상자그림 통계] 부서별 검수 소요시간(분) 사분위수(IQR) 및 기술통계 집계
dept_boxplot_df = df_q1.groupby('INSPECTOR_DEPT_NM')['INSP_DURATION_MIN'].agg(
    최소값='min',
    Q1_25=lambda s: s.quantile(0.25).round(1),
    중앙값_50='median',
    Q3_75=lambda s: s.quantile(0.75).round(1),
    최대값='max',
    비중_10분미만=lambda s: ((s < 10).mean() * 100).round(2)
).reset_index()

# 4. 시각화 순서 정렬 (차트 상단부터 중앙값 기준 내림차순 정렬)
dept_boxplot_df = dept_boxplot_df.sort_values(by='중앙값_50', ascending=False).reset_index(drop=True)

# 5. 최종 시각화 매핑 통계표 출력
print(dept_boxplot_df)
