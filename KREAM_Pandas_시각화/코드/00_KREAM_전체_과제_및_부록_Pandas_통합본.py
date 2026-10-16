# -*- coding: utf-8 -*-
from data_loader import load_analysis_data, load_staff_data, load_workload_ratio
"""
KREAM 검수운영 개선 기획 - 과제 1부터 부록 5까지 전체 Pandas 집계 코드 통합본
"""

# ===========================================================================
# 01_과제1_외주팀_품질위험_1-2
# ===========================================================================

# -*- coding: utf-8 -*-
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

# ===========================================================================
# 02_과제1_외주팀_품질위험_2-2
# ===========================================================================

# -*- coding: utf-8 -*-
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

# ===========================================================================
# 03_과제2_스니커즈팀_재검수부담_1-2
# ===========================================================================

# -*- coding: utf-8 -*-
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

# ===========================================================================
# 04_과제2_스니커즈팀_재검수부담_2-2
# ===========================================================================

# -*- coding: utf-8 -*-
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

# ===========================================================================
# 05_과제3_품목_전문화
# ===========================================================================

# -*- coding: utf-8 -*-
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

# ===========================================================================
# 06_부록1_상품별_오판정률
# ===========================================================================

# -*- coding: utf-8 -*-
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

# ===========================================================================
# 07_부록2_팀별_인원과_직급
# ===========================================================================

# -*- coding: utf-8 -*-
"""
[부록 2] 팀별 인원과 직급
- 검수원 사번 기준 유일 인원 2,960명 추출 및 부서별 직급 7단계 누적 인원 집계
"""
import pandas as pd

# 1. 정제 데이터 로드
df = load_analysis_data()

# 2. [검수원 마스터 기준] 검수원 사번(INSPECTOR_EMP_NO) 기준 유일 인원 2,960명 추출
emp_master = load_staff_data()

# 3. 부서별 직급 분포 교차 집계 (피벗 테이블)
pos_order = ['주니어검수원', '일반검수원', '선임검수원', '책임감정사', '수석감정사', '파트장', '팀장']
dept_emp_pivot = pd.crosstab(
    emp_master['INSPECTOR_DEPT_NM'], 
    emp_master['INSPECTOR_POSITION_NM']
)[pos_order]

# 4. 부서별 총 등록 인원 산출 및 내림차순 정렬 (차트 Y축 순서 확정)
dept_emp_pivot['등록인원(명)'] = dept_emp_pivot.sum(axis=1)
dept_emp_pivot = dept_emp_pivot.sort_values(by='등록인원(명)', ascending=False)

# 5. 누적 막대 그래프용 최종 통계 데이터프레임 출력
print(dept_emp_pivot)

# ===========================================================================
# 08_부록3_팀별_직급_구성비
# ===========================================================================

# -*- coding: utf-8 -*-
"""
[부록 3] 팀별 직급 구성비
- 부서별 직급 7단계 100% 누적 가로막대 비율(%) 집계
"""
import pandas as pd

# 1. 정제 데이터 로드
df = load_analysis_data()

# 2. 사번 기준 검수원 고유 마스터(2,960명) 추출
emp_master = load_staff_data()

# 3. 직급 7단계 정의
pos_order = ['주니어검수원', '일반검수원', '선임검수원', '책임감정사', '수석감정사', '파트장', '팀장']

# 4. 부서별 직급 구성비(%) 교차 집계 (행 기준 정규화 100%)
dept_emp_ratio = (pd.crosstab(
    emp_master['INSPECTOR_DEPT_NM'], 
    emp_master['INSPECTOR_POSITION_NM'], 
    normalize='index'
) * 100)[pos_order]

# 5. 총 등록인원 기준 내림차순 정렬
dept_counts = emp_master.groupby('INSPECTOR_DEPT_NM')['INSPECTOR_EMP_NO'].count()
dept_emp_ratio['총인원'] = dept_counts
dept_emp_ratio = dept_emp_ratio.sort_values(by='총인원', ascending=False).drop(columns='총인원').round(1)

print(dept_emp_ratio)

# ===========================================================================
# 09_부록4_상품별_검수_대상_건수
# ===========================================================================

# -*- coding: utf-8 -*-
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

# ===========================================================================
# 10_부록5_상품_구성비
# ===========================================================================

# -*- coding: utf-8 -*-
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

