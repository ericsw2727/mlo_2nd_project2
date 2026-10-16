# -*- coding: utf-8 -*-
from data_loader import load_analysis_data, load_staff_data, load_workload_ratio
"""
[과제 2] 스니커즈팀 재검수 부담 (2/2)
- 검수 대상별 최신 상태 비율 및 실제 누적 검수 작업량 비율(전 부서 ~8% 수준 균등) 산출
"""
import pandas as pd

# 1. 정제 데이터 로드
df = load_analysis_data()

# 2. [좌측 차트] 검수 대상별 최신 상태 (1차 vs 2차 비율)
# 검수ID(INSP_ID) 기준 최종 확정된 마지막 차수 추출
df_latest = df.sort_values('REV_NO').groupby('INSP_ID').last().reset_index()

target_ratio = pd.crosstab(
    df_latest['INSPECTOR_DEPT_NM'], 
    df_latest['REV_NO'], 
    normalize='index'
) * 100
target_ratio.columns = ['1차_비중(%)', '2차_비중(%)']
target_ratio = target_ratio.round(2)

# 3. [우측 차트] 부서별 실제 수행한 누적 검수 작업량 비율
# 1차 검수 이력 + 2차 재검수 이력 전체 작업량을 반영한 구성비
workload_ratio = load_workload_ratio()
workload_ratio.columns = ['1차_작업량(%)', '2차_작업량(%)']
workload_ratio = workload_ratio.round(2)

# 4. 차트 매핑 통합 결과표 (스니커즈팀 2차 비중 약 7.8%~8.1%로 전 부서 균등)
final_ratio = pd.concat([target_ratio, workload_ratio], axis=1)
print(final_ratio)
