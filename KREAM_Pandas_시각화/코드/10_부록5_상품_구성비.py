# -*- coding: utf-8 -*-
from data_loader import load_analysis_data, load_staff_data, load_workload_ratio
"""
[부록 5] 상품 구성비
- 19개 상품 × 8개 부서 내 상품 점유율(%) 히트맵 집계
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

# 2. 부서 내(열 기준) 19개 상품 점유율(%) 정규화 교차 집계
col_order = ['스니커즈검수1팀', '스니커즈검수2팀', '명품백감정팀', '스트릿의류검수팀', 
             '외주야간검수팀', '럭셔리워치감정팀', '테크레고검수팀', '클레임재검수팀']

ratio_matrix = (pd.crosstab(
    df_q1['ITEM_NM'], 
    df_q1['INSPECTOR_DEPT_NM'], 
    normalize='columns'
) * 100)[col_order]

item_order = df_q1['ITEM_NM'].value_counts().index
ratio_matrix = ratio_matrix.loc[item_order].round(1)

print(ratio_matrix)
