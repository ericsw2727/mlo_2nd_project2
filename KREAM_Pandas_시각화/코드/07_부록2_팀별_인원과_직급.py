# -*- coding: utf-8 -*-
from data_loader import load_analysis_data, load_staff_data, load_workload_ratio
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
