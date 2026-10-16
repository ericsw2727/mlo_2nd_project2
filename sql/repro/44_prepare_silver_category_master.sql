-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 44-1: 카테고리 Silver 처리 후보 저장
-- 검증된 ID 보정 후보 사용
-- 계층 코드는 표기 통일 후 허용값 검사
-- 1단계와 INVALID_SUB_DEPTH_99는 임의 복구하지 않음
-- 날짜 형식과 유효성은 36번에서 확인
-- Bronze 원본 변경 없음

CREATE TABLE kream_project_repro.asis_category_silver_stage_v1 AS
WITH prepared AS (
    SELECT
        b.bronze_row_id AS source_bronze_row_id,
        b.source_file,

        b.CAT_ID AS raw_cat_id,
        b.CAT_NM AS raw_cat_name,
        b.CAT_LEVEL AS raw_cat_level,
        b.REG_DT AS raw_reg_dt,

        n.proposed_id AS normalized_cat_id,
        b.CAT_NM AS normalized_cat_name,

        UPPER(
            REPLACE(TRIM(b.CAT_LEVEL), ' ', '_')
        ) AS normalized_cat_level,

        STR_TO_DATE(
            REPLACE(b.REG_DT, '/', '-'),
            '%Y-%m-%d %H:%i:%s'
        ) AS normalized_reg_dt

    FROM kream_project_repro.bronze_category_parent_lookup AS b

    LEFT JOIN kream_project_repro.asis_reference_id_snapshot_v1 AS n
      ON n.source_name = 'CATEGORY_MASTER'
     AND n.column_name = 'CAT_ID'
     AND n.bronze_row_id = b.bronze_row_id
),
ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY normalized_cat_id
            ORDER BY source_bronze_row_id
        ) AS occurrence_no
    FROM prepared
),
reasoned AS (
    SELECT
        *,
        CASE
            WHEN normalized_cat_id IS NULL
            THEN 'UNRESOLVED_CATEGORY_ID'

            WHEN NULLIF(TRIM(normalized_cat_name), '') IS NULL
            THEN 'MISSING_CATEGORY_NAME'

            WHEN CHAR_LENGTH(normalized_cat_id) > 20
              OR CHAR_LENGTH(normalized_cat_name) > 100
            THEN 'DECLARED_LENGTH_EXCEEDED'

            WHEN normalized_cat_level IS NULL
              OR normalized_cat_level NOT IN (
                  'TOP_LEVEL',
                  'BRAND_LINE'
              )
            THEN 'UNSUPPORTED_CATEGORY_LEVEL'

            WHEN normalized_reg_dt IS NULL
            THEN 'UNRESOLVED_REGISTRATION_DATETIME'

            WHEN occurrence_no > 1
            THEN 'IDENTICAL_REPEAT'

            ELSE 'MASTER_CHECKS_PASSED'
        END AS primary_reason
    FROM ranked
)
SELECT
    reasoned.*,

    CASE
        WHEN primary_reason = 'MASTER_CHECKS_PASSED'
        THEN 'SILVER_CANDIDATE'

        WHEN primary_reason = 'IDENTICAL_REPEAT'
        THEN 'EXCLUDED_CANDIDATE'

        ELSE 'QUARANTINE_CANDIDATE'
    END AS disposition

FROM reasoned;

SHOW WARNINGS;

-- 작업 44-2: 원본 행 추적과 검색 인덱스 추가

ALTER TABLE kream_project_repro.asis_category_silver_stage_v1
    ADD PRIMARY KEY (source_bronze_row_id),
    ADD INDEX ix_category_stage_key (normalized_cat_id),
    ADD INDEX ix_category_stage_disposition (disposition);


-- 작업 44-3: 원본과 처리 후보 건수 확인

SELECT
    'Bronze' AS dataset_name,
    COUNT(*) AS row_count
FROM kream_project_repro.bronze_category_parent_lookup

UNION ALL

SELECT
    'Processing stage',
    COUNT(*)
FROM kream_project_repro.asis_category_silver_stage_v1;


-- 작업 44-4: 처리 후보와 대표 사유별 건수

SELECT
    disposition,
    primary_reason,
    COUNT(*) AS row_count
FROM kream_project_repro.asis_category_silver_stage_v1
GROUP BY disposition, primary_reason
ORDER BY disposition, primary_reason;


-- 작업 44-5: 격리 후보의 원본 계층 값 확인

SELECT
    raw_cat_level,
    normalized_cat_level,
    primary_reason,
    COUNT(*) AS row_count
FROM kream_project_repro.asis_category_silver_stage_v1
WHERE disposition = 'QUARANTINE_CANDIDATE'
GROUP BY
    raw_cat_level,
    normalized_cat_level,
    primary_reason
ORDER BY raw_cat_level, primary_reason;