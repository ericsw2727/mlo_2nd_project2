-- 작업 41-0: 기존 테이블 확인

SELECT TABLE_NAME
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'kream_project'
  AND TABLE_NAME IN (
      'silver_inspector_master',
      'quarantine_inspector_master',
      'excluded_inspector_master',
      'silver_inspector_correction_log'
  );

-- 작업 41-1: Silver 검수원 마스터 생성

CREATE TABLE kream_project.silver_inspector_master (
    EMP_NO VARCHAR(20) NOT NULL,
    EMP_NM VARCHAR(50) NOT NULL,
    DEPT_NM VARCHAR(100) NOT NULL,
    POSITION_NM VARCHAR(50) NOT NULL,
    HIRE_DT DATE NOT NULL,
    ACTIVE_YN CHAR(1) NOT NULL,

    source_bronze_row_id BIGINT UNSIGNED NOT NULL,
    department_rule_source VARCHAR(32) NOT NULL,
    raw_active_status VARCHAR(16) NOT NULL,
    rule_version VARCHAR(32) NOT NULL,

    PRIMARY KEY (EMP_NO),
    UNIQUE KEY uq_silver_inspector_source (source_bronze_row_id),

    CONSTRAINT chk_silver_inspector_active
        CHECK (ACTIVE_YN IN ('Y', 'N'))
)
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin;


-- 작업 41-2: 정상 후보 적재

INSERT INTO kream_project.silver_inspector_master (
    EMP_NO,
    EMP_NM,
    DEPT_NM,
    POSITION_NM,
    HIRE_DT,
    ACTIVE_YN,
    source_bronze_row_id,
    department_rule_source,
    raw_active_status,
    rule_version
)
SELECT
    normalized_emp_no,
    normalized_emp_name,
    normalized_department,
    normalized_position,
    normalized_hire_date,
    normalized_active_yn,
    source_bronze_row_id,
    department_rule_source,
    raw_active_status,
    '20261014_v1'
FROM kream_project.asis_inspector_silver_stage_v1
WHERE disposition = 'SILVER_CANDIDATE';

SHOW WARNINGS;


-- 작업 41-3: 격리·제외 데이터 저장
-- 원본값·변환 후보·처리 사유를 함께 보존

CREATE TABLE kream_project.quarantine_inspector_master AS
SELECT *
FROM kream_project.asis_inspector_silver_stage_v1
WHERE disposition = 'QUARANTINE_CANDIDATE';

ALTER TABLE kream_project.quarantine_inspector_master
    ADD PRIMARY KEY (source_bronze_row_id);


CREATE TABLE kream_project.excluded_inspector_master AS
SELECT *
FROM kream_project.asis_inspector_silver_stage_v1
WHERE disposition = 'EXCLUDED_CANDIDATE';

ALTER TABLE kream_project.excluded_inspector_master
    ADD PRIMARY KEY (source_bronze_row_id);


-- 작업 41-4: 실제 Silver 반영값의 보정 로그

CREATE TABLE kream_project.silver_inspector_correction_log (
    source_bronze_row_id BIGINT UNSIGNED NOT NULL,
    column_name VARCHAR(32) NOT NULL,
    original_value TEXT,
    corrected_value TEXT,
    rule_id VARCHAR(64) NOT NULL,
    rule_version VARCHAR(32) NOT NULL,

    PRIMARY KEY (source_bronze_row_id, column_name)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin;


INSERT INTO kream_project.silver_inspector_correction_log (
    source_bronze_row_id,
    column_name,
    original_value,
    corrected_value,
    rule_id,
    rule_version
)
SELECT
    source_bronze_row_id,
    'EMP_NO',
    raw_emp_no,
    normalized_emp_no,
    'OUR_EMPLOYEE_ID_NORMALIZATION',
    '20261014_v1'
FROM kream_project.asis_inspector_silver_stage_v1
WHERE disposition = 'SILVER_CANDIDATE'
  AND NOT (HEX(raw_emp_no) <=> HEX(normalized_emp_no))

UNION ALL

SELECT
    source_bronze_row_id,
    'DEPT_NM',
    raw_department,
    normalized_department,
    'OUR_DEPARTMENT_DICTIONARY_MAPPING',
    '20261014_v1'
FROM kream_project.asis_inspector_silver_stage_v1
WHERE disposition = 'SILVER_CANDIDATE'
  AND NOT (HEX(raw_department) <=> HEX(normalized_department))

UNION ALL

SELECT
    source_bronze_row_id,
    'HIRE_DT',
    raw_hire_dt,
    CAST(normalized_hire_date AS CHAR),
    'OUR_HIRE_DATE_TO_SPEC_DATE',
    '20261014_v1'
FROM kream_project.asis_inspector_silver_stage_v1
WHERE disposition = 'SILVER_CANDIDATE'
  AND NOT (
      HEX(raw_hire_dt)
      <=> HEX(CAST(normalized_hire_date AS CHAR))
  )

UNION ALL

SELECT
    source_bronze_row_id,
    'ACTIVE_YN',
    raw_active_yn,
    normalized_active_yn,
    'OUR_ACTIVE_EXACT_Y_ELSE_N',
    '20261014_v1'
FROM kream_project.asis_inspector_silver_stage_v1
WHERE disposition = 'SILVER_CANDIDATE'
  AND NOT (HEX(raw_active_yn) <=> HEX(normalized_active_yn));

SHOW WARNINGS;


-- 작업 41-5: 처리 결과 건수

SELECT 'Silver' AS dataset_name, COUNT(*) AS row_count
FROM kream_project.silver_inspector_master

UNION ALL

SELECT 'Quarantine', COUNT(*)
FROM kream_project.quarantine_inspector_master

UNION ALL

SELECT 'Excluded', COUNT(*)
FROM kream_project.excluded_inspector_master;


-- 작업 41-6: 원본 행의 누락·다중 분류 확인
-- 원본마다 정확히 하나의 처리 결과가 있어야 함

WITH assignments AS (
    SELECT source_bronze_row_id
    FROM kream_project.silver_inspector_master

    UNION ALL

    SELECT source_bronze_row_id
    FROM kream_project.quarantine_inspector_master

    UNION ALL

    SELECT source_bronze_row_id
    FROM kream_project.excluded_inspector_master
),
assignment_counts AS (
    SELECT
        source_bronze_row_id,
        COUNT(*) AS assigned_count
    FROM assignments
    GROUP BY source_bronze_row_id
)
SELECT
    COUNT(*) AS bronze_rows,

    SUM(
        CASE WHEN a.source_bronze_row_id IS NULL
             THEN 1 ELSE 0 END
    ) AS unassigned_rows,

    SUM(
        CASE WHEN a.assigned_count > 1
             THEN 1 ELSE 0 END
    ) AS multiply_assigned_rows

FROM kream_project.bronze_inspector_master AS b
LEFT JOIN assignment_counts AS a
  ON a.source_bronze_row_id = b.bronze_row_id;


-- 작업 41-7: Silver 전체 업무 컬럼과 처리 후보 대조

SELECT
    COUNT(*) AS silver_rows,

    SUM(
        CASE
            WHEN p.source_bronze_row_id IS NULL
              OR p.disposition <> 'SILVER_CANDIDATE'
              OR NOT (HEX(s.EMP_NO) <=> HEX(p.normalized_emp_no))
              OR NOT (HEX(s.EMP_NM) <=> HEX(p.normalized_emp_name))
              OR NOT (
                  HEX(s.DEPT_NM) <=> HEX(p.normalized_department)
              )
              OR NOT (
                  HEX(s.POSITION_NM) <=> HEX(p.normalized_position)
              )
              OR NOT (s.HIRE_DT <=> p.normalized_hire_date)
              OR NOT (
                  HEX(s.ACTIVE_YN) <=> HEX(p.normalized_active_yn)
              )
            THEN 1 ELSE 0
        END
    ) AS unexpected_difference_rows

FROM kream_project.silver_inspector_master AS s
LEFT JOIN kream_project.asis_inspector_silver_stage_v1 AS p
  ON p.source_bronze_row_id = s.source_bronze_row_id;


-- 작업 41-8: 컬럼별 실제 보정 로그 건수

SELECT
    column_name,
    rule_id,
    COUNT(*) AS correction_rows
FROM kream_project.silver_inspector_correction_log
GROUP BY column_name, rule_id
ORDER BY column_name;