# -*- coding: utf-8 -*-
from data_loader import load_analysis_data, load_staff_data, load_workload_ratio
"""
[과제 2] 스니커즈팀 재검수 부담 (1/2)
- 2차 재검수 모수(21,656건) 기준 부서별 오판건수 및 배상위험액(스니커즈1팀 298.88억, 2팀 223.50억) 산출
"""
import pandas as pd

# 1. 정제 데이터 로드
df = load_analysis_data()

# 2. [분석 모수] 2차 재검수 대상 데이터 필터링 (총 21,656건)
df_rev2 = df[df['REV_NO'] == 2].copy()

# 3. [핵심 통계] 부서별 2차 재검수 오판정 건수 및 배상 위험액 산출
dept_stats = df_rev2.groupby('INSPECTOR_DEPT_NM').agg(
    재검수건수=('INSP_ID', 'count'),
    오판건수=('INSP_RESULT', lambda s: (s == 'CLAIM_FAKE_PASS').sum()),
    배상위험_원=('COMPENSATION_LOSS_KRW', 'sum')
).reset_index()

# 4. 통계 파생 지표 산출 (배상위험: 억 원 환산, 재검수 오판율: %)
dept_stats['배상위험_억원'] = (dept_stats['배상위험_원'] / 1e8).round(2)
dept_stats['오판율(%)'] = ((dept_stats['오판건수'] / dept_stats['재검수건수']) * 100).round(2)

# 5. 차트 기준별 정렬 및 통계표 출력
# 좌측 차트: 산식 기준 배상액(억 원) 내림차순 정렬 (스니커즈1팀 298.88억 1위)
chart_loss = dept_stats.sort_values(by='배상위험_억원', ascending=False)

# 우측 차트: 가품 오판정 확인 건수(건) 내림차순 정렬 (스니커즈1팀 3,753건 1위)
chart_count = dept_stats.sort_values(by='오판건수', ascending=False)

print(chart_loss[['INSPECTOR_DEPT_NM', '재검수건수', '오판건수', '오판율(%)', '배상위험_억원']])
