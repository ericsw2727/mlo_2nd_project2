-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 22-1: 기타 비표준 ID·사번 샘플
-- 21번과 같은 분류 순서를 사용
-- 컬럼별 기타 비표준값 최대 5행 조회
-- 원본값과 HEX는 같은 행의 값
-- 원본 수정 없음

WITH identifier_values AS (
    SELECT
        bronze_row_id,
        'INSP_ID' AS column_name,
        '^INSP_[0-9]{6}$' AS expected_pattern,
        INSP_ID AS raw_value
    FROM kream_project_repro.bronze_inspection

    UNION ALL

    SELECT
        bronze_row_id, 'PARENT_CAT_ID',
        '^CAT_[0-9]{5}$', PARENT_CAT_ID
    FROM kream_project_repro.bronze_inspection

    UNION ALL

    SELECT
        bronze_row_id, 'INSPECTOR_EMP_NO',
        '^KRM[0-9]{6}$', INSPECTOR_EMP_NO
    FROM kream_project_repro.bronze_inspection
),
classified AS (
    SELECT
        *,
        CASE
            WHEN COALESCE(LOWER(TRIM(raw_value)), '') IN (
                '', 'null', 'none', 'na', 'n/a', 'nan', '-'
            )
            THEN 'MISSING_CANDIDATE'

            WHEN REGEXP_LIKE(raw_value, expected_pattern, 'c')
            THEN 'STANDARD'

            WHEN REGEXP_LIKE(
                TRIM(raw_value), expected_pattern, 'c'
            )
            THEN 'EDGE_SPACE'

            WHEN REGEXP_LIKE(
                UPPER(TRIM(raw_value)), expected_pattern, 'c'
            )
            THEN 'CASE_OR_EDGE_SPACE'

            WHEN REGEXP_LIKE(
                REPLACE(UPPER(TRIM(raw_value)), '-', ''),
                expected_pattern, 'c'
            )
            THEN 'HYPHEN_CASE_OR_SPACE'

            WHEN column_name = 'INSPECTOR_EMP_NO'
             AND REGEXP_LIKE(
                 TRIM(raw_value), '^[0-9]{6}$', 'c'
             )
            THEN 'EMPLOYEE_PREFIX_MISSING'

            WHEN REGEXP_LIKE(
                raw_value, '[Ａ-Ｚａ-ｚ０-９＿]', 'c'
            )
            THEN 'FULLWIDTH_CHARACTER'

            WHEN INSTR(raw_value, CHAR(9)) > 0
              OR INSTR(raw_value, CHAR(10)) > 0
              OR INSTR(raw_value, CHAR(13)) > 0
              OR INSTR(
                  raw_value,
                  CHAR(194, 160 USING utf8mb4)
              ) > 0
              OR INSTR(
                  raw_value,
                  CHAR(226, 128, 139 USING utf8mb4)
              ) > 0
              OR INSTR(
                  raw_value,
                  CHAR(227, 128, 128 USING utf8mb4)
              ) > 0
            THEN 'HIDDEN_WHITESPACE'

            ELSE 'OTHER_NONSTANDARD'
        END AS primary_pattern
    FROM identifier_values
),
samples AS (
    SELECT
        *,
        COUNT(*) OVER (
            PARTITION BY column_name
        ) AS other_rows,
        ROW_NUMBER() OVER (
            PARTITION BY column_name
            ORDER BY bronze_row_id
        ) AS sample_no
    FROM classified
    WHERE primary_pattern = 'OTHER_NONSTANDARD'
)
SELECT
    column_name,
    other_rows,
    bronze_row_id,
    raw_value,
    HEX(raw_value) AS raw_hex,
    CHAR_LENGTH(raw_value) AS character_count
FROM samples
WHERE sample_no <= 5
ORDER BY column_name, sample_no;