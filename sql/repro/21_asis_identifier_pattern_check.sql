-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 21-1: ID·사번의 전체 원문 표기 유형 조사
-- 정상 형식, 공백, 대소문자, 하이픈, 접두어 누락,
-- 전각 문자, 숨은 문자 등을 분류
-- 여러 문제가 겹치면 아래 CASE의 첫 조건으로 분류
-- 보정 후보 조사이며 원본 수정 없음

WITH identifier_values AS (
    SELECT
        'CATEGORY_MASTER' AS source_name,
        'CAT_ID' AS column_name,
        '^CAT_[0-9]{5}$' AS expected_pattern,
        CAT_ID AS raw_value
    FROM kream_project_repro.bronze_category_parent_lookup

    UNION ALL

    SELECT
        'INSPECTOR_MASTER', 'EMP_NO',
        '^KRM[0-9]{6}$', EMP_NO
    FROM kream_project_repro.bronze_inspector_master

    UNION ALL

    SELECT
        'INSPECTION', 'INSP_ID',
        '^INSP_[0-9]{6}$', INSP_ID
    FROM kream_project_repro.bronze_inspection

    UNION ALL

    SELECT
        'INSPECTION', 'PARENT_CAT_ID',
        '^CAT_[0-9]{5}$', PARENT_CAT_ID
    FROM kream_project_repro.bronze_inspection

    UNION ALL

    SELECT
        'INSPECTION', 'INSPECTOR_EMP_NO',
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

            WHEN column_name IN ('EMP_NO', 'INSPECTOR_EMP_NO')
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
)
SELECT
    source_name,
    column_name,
    primary_pattern,
    COUNT(*) AS row_count,
    MIN(raw_value) AS example_value,
    MIN(HEX(raw_value)) AS example_hex
FROM classified
GROUP BY source_name, column_name, primary_pattern
ORDER BY source_name, column_name, primary_pattern;