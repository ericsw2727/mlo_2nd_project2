# -*- coding: utf-8 -*-
from data_loader import load_analysis_data, load_staff_data, load_workload_ratio
"""
[과제 1] 외주팀 품질 위험 (1/2)
- 외주야간검수팀 배상 위험액 59.20억 원(전사 1위) 및 오판정률 2.28% 산출
"""
import pandas as pd

# 1. 정제 데이터 로드
df = load_analysis_data()

# 2. 분석 모수 필터링 (2022.01~2026.08, 최초개정본 243,454건)
df['INSP_DONE_DT'] = pd.to_datetime(df['INSP_DONE_DT'], errors='coerce')
df_q1 = df[
    (df['REV_NO'] == 1) & 
    (df['INSP_DONE_DT'] >= '2022-01-01') & 
    (df['INSP_DONE_DT'] <= '2026-08-31 23:59:59')
].copy()

# 3. 부서별 핵심 통계 집계 (총 검수량, 가품 오판정 건수, 300% 배상 위험액)
dept_stats = df_q1.groupby('INSPECTOR_DEPT_NM').agg(
    총검수건수=('INSP_ID', 'count'),
    오판건수=('INSP_RESULT', lambda s: (s == 'CLAIM_FAKE_PASS').sum()),
    배상위험_원=('COMPENSATION_LOSS_KRW', 'sum')
).reset_index()

# 4. 통계 파생 지표 산출 (X축 단위: 억 원 환산, 오판정률: %)
dept_stats['배상위험_억원'] = (dept_stats['배상위험_원'] / 1e8).round(2)
dept_stats['오판정률(%)'] = ((dept_stats['오판건수'] / dept_stats['총검수건수']) * 100).round(2)

# 5. 시각화 기준 배상 위험액 내림차순 정렬 (차트 막대 순서 확정)
dept_stats = dept_stats.sort_values(by='배상위험_억원', ascending=False).reset_index(drop=True)

# 6. 최종 통계 집계 데이터프레임 (차트에 매핑되는 원천 통계표)
stat_table = dept_stats[['INSPECTOR_DEPT_NM', '오판건수', '배상위험_억원', '오판정률(%)', '총검수건수']]
print(stat_table)
