# -*- coding: utf-8 -*-
from data_loader import load_analysis_data, load_staff_data, load_workload_ratio
"""
[부록 1] 상품별 오판정률
- 19개 상품 × 8개 부서 오판정률(%) 매트릭스 (외주야간팀 1.46%~3.18% 집중 리스크)
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

# 2. 가품 오판정 플래그 생성 (사후 클레임 발생 건)
df_q1['IS_CLAIM'] = df_q1['INSP_RESULT'] == 'CLAIM_FAKE_PASS'

# 3. [히트맵 행렬 집계] 가로축: 8개 부서, 세로축: 19개 상품, 값: 오판정률(%)
heatmap_matrix = df_q1.pivot_table(
    index='ITEM_NM', 
    columns='INSPECTOR_DEPT_NM', 
    values='IS_CLAIM', 
    aggfunc='mean'
) * 100
heatmap_matrix = heatmap_matrix.round(2)

# 4. 부서 순서 지정 (차트 X축 순서와 일치)
dept_order = [
    '스니커즈검수1팀', '스니커즈검수2팀', '명품백감정팀', '스트릿의류검수팀',
    '외주야간검수팀', '럭셔리워치감정팀', '테크레고검수팀', '클레임재검수팀'
]
heatmap_matrix = heatmap_matrix[dept_order]

# 5. 최종 19 × 8 오판정률 히트맵 테이블 출력
print(heatmap_matrix)
