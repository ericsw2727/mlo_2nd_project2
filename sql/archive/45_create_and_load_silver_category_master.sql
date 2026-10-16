-- 작업 45-0: 기존 테이블 확인

SELECT TABLE_NAME
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'kream_project'
  AND TABLE_NAME IN (
      'silver_category_parent_lookup',
      'quarantine_category_parent_lookup',
      'excluded_category_parent_lookup',
      'silver_category_correction_log'
  );

-- 작업 45-1: Silver 카테고리 마스터 생성

CREATE TABLE kream_project.silver_category_parent_lookup (
    CAT_ID VARCHAR(20) NOT NULL,
    CAT_NM VARCHAR(100) NOT NULL,
    CAT_LEVEL VARCHAR(20) NOT NULL,
    REG_DT DATETIME NOT NULL,

    source_bronze_row_id BIGINT UNSIGNED NOT NULL,
    rule_version VARCHAR(32) NOT NULL,

    PRIMARY KEY (CAT_ID),
    UNIQUE KEY uq_silver_category_source (source_bronze_row_id),

    CONSTRAINT chk_silver_category_level
        CHECK (CAT_LEVEL IN ('TOP_LEVEL', 'BRAND_LINE'))
)
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin;


-- 작업 45-2: 정상 후보 적재

INSERT INTO kream_project.silver_category_parent_lookup (
    CAT_ID,
    CAT_NM,
    CAT_LEVEL,
    REG_DT,
    source_bronze_row_id,
    rule_version
)
SELECT
    normalized_cat_id,
    normalized_cat_name,
    normalized_cat_level,
    normalized_reg_dt,
    source_bronze_row_id,
    '20261014_v1'
FROM kream_project.asis_category_silver_stage_v1
WHERE disposition = 'SILVER_CANDIDATE';

SHOW WARNINGS;


-- 작업 45-3: 격리·제외 데이터 저장
-- 원본값·보정 후보·처리 사유를 함께 보존

CREATE TABLE kream_project.quarantine_category_parent_lookup AS
SELECT *
FROM kream_project.asis_category_silver_stage_v1
WHERE disposition = 'QUARANTINE_CANDIDATE';

ALTER TABLE kream_project.quarantine_category_parent_lookup
    ADD PRIMARY KEY (source_bronze_row_id);


CREATE TABLE kream_project.excluded_category_parent_lookup AS
SELECT *
FROM kream_project.asis_category_silver_stage_v1
WHERE disposition = 'EXCLUDED_CANDIDATE';

ALTER TABLE kream_project.excluded_category_parent_lookup
    ADD PRIMARY KEY (source_bronze_row_id);


-- 작업 45-4: 실제 Silver 반영값의 보정 로그

CREATE TABLE kream_project.silver_category_correction_log (
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


INSERT INTO kream_project.silver_category_correction_log (
    source_bronze_row_id,
    column_name,
    original_value,
    corrected_value,
    rule_id,
    rule_version
)
SELECT
    source_bronze_row_id,
    'CAT_ID',
    raw_cat_id,
    normalized_cat_id,
    'OUR_CATEGORY_ID_NORMALIZATION',
    '20261014_v1'
FROM kream_project.asis_category_silver_stage_v1
WHERE disposition = 'SILVER_CANDIDATE'
  AND NOT (HEX(raw_cat_id) <=> HEX(normalized_cat_id))

UNION ALL

SELECT
    source_bronze_row_id,
    'CAT_LEVEL',
    raw_cat_level,
    normalized_cat_level,
    'OUR_CATEGORY_LEVEL_SPELLING',
    '20261014_v1'
FROM kream_project.asis_category_silver_stage_v1
WHERE disposition = 'SILVER_CANDIDATE'
  AND NOT (HEX(raw_cat_level) <=> HEX(normalized_cat_level))

UNION ALL

SELECT
    source_bronze_row_id,
    'REG_DT',
    raw_reg_dt,
    DATE_FORMAT(normalized_reg_dt, '%Y-%m-%d %H:%i:%s'),
    'OUR_CATEGORY_REGISTRATION_FORMAT',
    '20261014_v1'
FROM kream_project.asis_category_silver_stage_v1
WHERE disposition = 'SILVER_CANDIDATE'
  AND NOT (
      HEX(raw_reg_dt)
      <=> HEX(
          DATE_FORMAT(normalized_reg_dt, '%Y-%m-%d %H:%i:%s')
      )
  );

SHOW WARNINGS;


-- 작업 45-5: 처리 결과 건수

SELECT 'Silver' AS dataset_name, COUNT(*) AS row_count
FROM kream_project.silver_category_parent_lookup

UNION ALL

SELECT 'Quarantine', COUNT(*)
FROM kream_project.quarantine_category_parent_lookup

UNION ALL

SELECT 'Excluded', COUNT(*)
FROM kream_project.excluded_category_parent_lookup;


-- 작업 45-6: 원본 행의 누락·중복 분류 확인

WITH assignments AS (
    SELECT source_bronze_row_id
    FROM kream_project.silver_category_parent_lookup

    UNION ALL

    SELECT source_bronze_row_id
    FROM kream_project.quarantine_category_parent_lookup

    UNION ALL

    SELECT source_bronze_row_id
    FROM kream_project.excluded_category_parent_lookup
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

FROM kream_project.bronze_category_parent_lookup AS b
LEFT JOIN assignment_counts AS a
  ON a.source_bronze_row_id = b.bronze_row_id;


-- 작업 45-7: Silver 전체 업무 컬럼과 처리 후보 대조

SELECT
    COUNT(*) AS silver_rows,

    SUM(
        CASE
            WHEN p.source_bronze_row_id IS NULL
              OR p.disposition <> 'SILVER_CANDIDATE'
              OR NOT (
                  HEX(s.CAT_ID) <=> HEX(p.normalized_cat_id)
              )
              OR NOT (
                  HEX(s.CAT_NM) <=> HEX(p.normalized_cat_name)
              )
              OR NOT (
                  HEX(s.CAT_LEVEL) <=> HEX(p.normalized_cat_level)
              )
              OR NOT (s.REG_DT <=> p.normalized_reg_dt)
            THEN 1 ELSE 0
        END
    ) AS unexpected_difference_rows

FROM kream_project.silver_category_parent_lookup AS s
LEFT JOIN kream_project.asis_category_silver_stage_v1 AS p
  ON p.source_bronze_row_id = s.source_bronze_row_id;


-- 작업 45-8: 컬럼별 실제 보정 로그 건수

SELECT
    column_name,
    rule_id,
    COUNT(*) AS correction_rows
FROM kream_project.silver_category_correction_log
GROUP BY column_name, rule_id
ORDER BY column_name;