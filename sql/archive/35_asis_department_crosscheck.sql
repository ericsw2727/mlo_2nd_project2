-- 작업 35-1: 미매핑 부서의 사번 기준 교차 확인
-- 기존에 확인된 원본 사번 → 보정 사번 대응을 사용
-- 조인 통합본은 먼저 묶어 비교량을 줄임
-- 원본 수정·부서명 치환 없음
-- 조인 통합본의 값을 정답으로 확정하지 않음

WITH employee_lookup AS (
    SELECT DISTINCT
        raw_value AS raw_employee_no,
        proposed_id AS normalized_employee_no
    FROM kream_project.asis_reference_id_snapshot_v1
    WHERE proposed_id IS NOT NULL
      AND (
          (source_name = 'INSPECTOR_MASTER'
           AND column_name = 'EMP_NO')
          OR
          (source_name = 'INSPECTION'
           AND column_name = 'INSPECTOR_EMP_NO')
      )
),
unmapped_employees AS (
    SELECT DISTINCT
        n.proposed_id AS normalized_employee_no,
        b.EMP_NM AS master_employee_name,
        b.DEPT_NM AS master_department
    FROM kream_project.bronze_inspector_master AS b

    JOIN kream_project.asis_reference_id_snapshot_v1 AS n
      ON n.source_name = 'INSPECTOR_MASTER'
     AND n.column_name = 'EMP_NO'
     AND n.bronze_row_id = b.bronze_row_id

    JOIN kream_project.asis_inspector_department_check_v1 AS d
      ON d.raw_department_hex = HEX(b.DEPT_NM)
     AND d.department_status = 'UNMAPPED_DEPARTMENT'

    WHERE n.proposed_id IS NOT NULL
),
join_groups AS (
    SELECT
        INSPECTOR_EMP_NO,
        INSPECTOR_EMP_NM,
        INSPECTOR_DEPT_NM,
        COUNT(*) AS joined_source_rows
    FROM kream_project.bronze_inspection_join_ready
    GROUP BY
        INSPECTOR_EMP_NO,
        INSPECTOR_EMP_NM,
        INSPECTOR_DEPT_NM
),
normalized_join_groups AS (
    SELECT
        e.normalized_employee_no,
        j.INSPECTOR_EMP_NM,
        j.INSPECTOR_DEPT_NM,
        j.joined_source_rows
    FROM join_groups AS j
    JOIN employee_lookup AS e
      ON e.raw_employee_no = j.INSPECTOR_EMP_NO
)
SELECT
    m.master_department,
    j.INSPECTOR_DEPT_NM AS joined_department,

    CASE
        WHEN j.normalized_employee_no IS NULL
        THEN 'NO_COMPARABLE_ROW'

        WHEN HEX(m.master_employee_name)
             <=> HEX(j.INSPECTOR_EMP_NM)
        THEN 'EMPLOYEE_NAME_MATCH'

        ELSE 'EMPLOYEE_NAME_MISMATCH'
    END AS employee_name_check,

    COUNT(DISTINCT m.normalized_employee_no)
        AS distinct_employee_count,

    COALESCE(SUM(j.joined_source_rows), 0)
        AS joined_source_rows

FROM unmapped_employees AS m
LEFT JOIN normalized_join_groups AS j
  ON j.normalized_employee_no = m.normalized_employee_no

GROUP BY
    m.master_department,
    j.INSPECTOR_DEPT_NM,
    employee_name_check

ORDER BY
    m.master_department,
    employee_name_check,
    joined_department;