-- 작업 40-1: 검수원 Silver 처리 후보 저장
-- 검사 결과와 원본값을 함께 보존
-- 아직 최종 Silver 테이블에 적재하지 않음

CREATE TABLE kream_project.asis_inspector_silver_stage_v1 AS
WITH prepared AS (
    SELECT
        b.bronze_row_id AS source_bronze_row_id,
        b.source_file,

        b.EMP_NO AS raw_emp_no,
        b.EMP_NM AS raw_emp_name,
        b.DEPT_NM AS raw_department,
        b.POSITION_NM AS raw_position,
        b.HIRE_DT AS raw_hire_dt,
        b.ACTIVE_YN AS raw_active_yn,

        n.proposed_id AS normalized_emp_no,
        b.EMP_NM AS normalized_emp_name,
        b.POSITION_NM AS normalized_position,

        CAST(LEFT(b.HIRE_DT, 10) AS DATE)
            AS normalized_hire_date,

        CASE
            WHEN HEX(b.ACTIVE_YN) = '59' THEN 'Y'
            ELSE 'N'
        END AS normalized_active_yn,

        CASE
            WHEN HEX(b.ACTIVE_YN) IN ('59', '4E')
            THEN 'STANDARD'
            ELSE 'NONSTANDARD'
        END AS raw_active_status,

        CASE
            WHEN d.department_status IN (
                'STANDARD_DEPARTMENT',
                'NORMALIZABLE_DEPARTMENT'
            )
            THEN d.proposed_department_name

            WHEN d.department_status = 'UNMAPPED_DEPARTMENT'
             AND b.DEPT_NM IN (
                 '럭셔리워치감정팀',
                 '스니커즈검수2팀',
                 '스트릿의류검수팀',
                 '클레임재검수팀',
                 '테크레고검수팀'
             )
            THEN b.DEPT_NM

            ELSE NULL
        END AS normalized_department,

        CASE
            WHEN d.department_status = 'BANNED_DEPARTMENT'
            THEN 'BANNED'

            WHEN d.department_status IN (
                'STANDARD_DEPARTMENT',
                'NORMALIZABLE_DEPARTMENT'
            )
            THEN 'DICTIONARY'

            WHEN d.department_status = 'UNMAPPED_DEPARTMENT'
             AND b.DEPT_NM IN (
                 '럭셔리워치감정팀',
                 '스니커즈검수2팀',
                 '스트릿의류검수팀',
                 '클레임재검수팀',
                 '테크레고검수팀'
             )
            THEN 'MASTER_CROSSCHECK'

            ELSE 'UNRESOLVED'
        END AS department_rule_source

    FROM kream_project.bronze_inspector_master AS b

    LEFT JOIN kream_project.asis_reference_id_snapshot_v1 AS n
      ON n.source_name = 'INSPECTOR_MASTER'
     AND n.column_name = 'EMP_NO'
     AND n.bronze_row_id = b.bronze_row_id

    LEFT JOIN kream_project.asis_inspector_department_check_v1 AS d
      ON d.raw_department_hex = HEX(b.DEPT_NM)
),
ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY normalized_emp_no
            ORDER BY source_bronze_row_id
        ) AS occurrence_no
    FROM prepared
)
SELECT
    ranked.*,

    CASE
        WHEN normalized_emp_no IS NULL
        THEN 'REVIEW_REQUIRED'

        WHEN department_rule_source = 'BANNED'
        THEN 'QUARANTINE_CANDIDATE'

        WHEN normalized_department IS NULL
        THEN 'REVIEW_REQUIRED'

        WHEN occurrence_no > 1
        THEN 'EXCLUDED_CANDIDATE'

        ELSE 'SILVER_CANDIDATE'
    END AS disposition,

    CASE
        WHEN normalized_emp_no IS NULL
        THEN 'UNRESOLVED_EMPLOYEE_KEY'

        WHEN department_rule_source = 'BANNED'
        THEN 'BANNED_DEPARTMENT'

        WHEN normalized_department IS NULL
        THEN 'UNRESOLVED_DEPARTMENT'

        WHEN occurrence_no > 1
        THEN 'IDENTICAL_REPEAT'

        ELSE 'MASTER_CHECKS_PASSED'
    END AS primary_reason

FROM ranked;

SHOW WARNINGS;


-- 작업 40-2: 원본 행 추적과 인덱스 추가

ALTER TABLE kream_project.asis_inspector_silver_stage_v1
    ADD PRIMARY KEY (source_bronze_row_id),
    ADD INDEX ix_inspector_stage_key (normalized_emp_no),
    ADD INDEX ix_inspector_stage_disposition (disposition);


-- 작업 40-3: 원본과 후보 저장 건수 확인

SELECT
    'Bronze' AS dataset_name,
    COUNT(*) AS row_count
FROM kream_project.bronze_inspector_master

UNION ALL

SELECT
    'Processing stage',
    COUNT(*)
FROM kream_project.asis_inspector_silver_stage_v1;


-- 작업 40-4: 처리 후보와 대표 사유별 건수

SELECT
    disposition,
    primary_reason,
    COUNT(*) AS row_count
FROM kream_project.asis_inspector_silver_stage_v1
GROUP BY disposition, primary_reason
ORDER BY disposition, primary_reason;


-- 작업 40-5: 재직 규칙 및 부서 처리 근거 확인
-- 중복을 포함한 전체 수신 행 기준

SELECT
    department_rule_source,
    raw_active_status,
    normalized_active_yn,
    COUNT(*) AS row_count
FROM kream_project.asis_inspector_silver_stage_v1
GROUP BY
    department_rule_source,
    raw_active_status,
    normalized_active_yn
ORDER BY
    department_rule_source,
    raw_active_status,
    normalized_active_yn;