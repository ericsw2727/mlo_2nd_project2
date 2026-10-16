# -*- coding: utf-8 -*-
from data_loader import load_analysis_data, load_staff_data, load_workload_ratio
"""
[부록 4] 상품별 검수 대상 건수
- 19개 상품(세로축) × 8개 부서(가로축) 검수 대상 건수 히트맵 집계
"""
import pandas as pd

# 1. 정제 데이터 로드 및 1차 검수 분석 모수 필터링
df = load_analysis_data()
df['INSP_DONE_DT'] = pd.to_datetime(df['INSP_DONE_DT'], errors='coerce')

df_q1 = df[
    (df['REV_NO'] == 1) & 
    (df['INSP_DONE_DT'] >= '2022-01-01') & 
    (df['INSP_DONE_DT'] <= '2026-08-31 23:59:59')
].copy()

# 2. 19개 상품 × 8개 부서 검수 대상 건수 피벗
col_order = ['스니커즈검수1팀', '스니커즈검수2팀', '명품백감정팀', '스트릿의류검수팀', 
             '외주야간검수팀', '럭셔리워치감정팀', '테크레고검수팀', '클레임재검수팀']

count_matrix = df_q1.pivot_table(
    index='ITEM_NM', 
    columns='INSPECTOR_DEPT_NM', 
    values='INSP_ID', 
    aggfunc='count'
)[col_order]

# 전체 검수량 기준 상품 내림차순 정렬
count_matrix['전체합계'] = count_matrix.sum(axis=1)
count_matrix = count_matrix.sort_values(by='전체합계', ascending=False).drop(columns='전체합계')

print(count_matrix)
