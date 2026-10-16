# -*- coding: utf-8 -*-
from data_loader import load_analysis_data, load_staff_data, load_workload_ratio
"""
[과제 3] 품목 전문화
- 8개 부서별 총 검수 작업량 및 19종 상품 점유율(%) 피벗 집계 (비전문화 현상 진단)
"""
import pandas as pd

# 1. 정제 데이터 로드 및 분석 모수 필터링 (최초 검수본 243,454건)
df = load_analysis_data()
df['INSP_DONE_DT'] = pd.to_datetime(df['INSP_DONE_DT'], errors='coerce')

df_q1 = df[
    (df['REV_NO'] == 1) & 
    (df['INSP_DONE_DT'] >= '2022-01-01') & 
    (df['INSP_DONE_DT'] <= '2026-08-31 23:59:59')
].copy()

# 2. 부서별 총 검수 작업량 산출 (8개 패널 상단 총 건수)
dept_totals = df_q1['INSPECTOR_DEPT_NM'].value_counts()
print("=== 8개 부서별 검수 총 건수 ===")
print(dept_totals)

# 3. 부서별 19종 상품 검수 점유율(%) 피벗 테이블 집계
item_composition = pd.crosstab(
    df_q1['INSPECTOR_DEPT_NM'], 
    df_q1['ITEM_NM'], 
    normalize='index'
) * 100
item_composition = item_composition.round(2)

# 4. 각 팀별 상품 점유율 출력
print("=== 팀별 상품 검수 구성비(%) 상위 품목 ===")
print(item_composition.T)
