-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 23-1: ID·사번 표준화 후보 검사 뷰
-- 대상: 카테고리 마스터, 검수원 마스터, 검수 원천
-- 원본값·중간값·보정 후보를 함께 유지
-- 숫자 자르기·임의 사번 생성·유령 코드 복구 금지
-- 최종 참조 유효성은 후속 검사에서 확인

CREATE OR REPLACE VIEW
    kream_project_repro.asis_identifier_normalization_v1 AS
WITH source_values AS (
    SELECT
        'CATEGORY_MASTER' AS source_name,
        bronze_row_id,
        'CAT_ID' AS column_name,
        'CAT' AS id_family,
        '^CAT_[0-9]{5}$' AS expected_pattern,
        CAT_ID AS raw_value
    FROM kream_project_repro.bronze_category_parent_lookup

    UNION ALL
    SELECT
        'INSPECTOR_MASTER', bronze_row_id,
        'EMP_NO', 'KRM', '^KRM[0-9]{6}$', EMP_NO
    FROM kream_project_repro.bronze_inspector_master

    UNION ALL
    SELECT
        'INSPECTION', bronze_row_id,
        'INSP_ID', 'INSP', '^INSP_[0-9]{6}$', INSP_ID
    FROM kream_project_repro.bronze_inspection

    UNION ALL
    SELECT
        'INSPECTION', bronze_row_id,
        'PARENT_CAT_ID', 'CAT', '^CAT_[0-9]{5}$',
        PARENT_CAT_ID
    FROM kream_project_repro.bronze_inspection

    UNION ALL
    SELECT
        'INSPECTION', bronze_row_id,
        'INSPECTOR_EMP_NO', 'KRM', '^KRM[0-9]{6}$',
        INSPECTOR_EMP_NO
    FROM kream_project_repro.bronze_inspection
),
space_cleaned AS (
    SELECT
        *,
        UPPER(
            REPLACE(
                REPLACE(
                    REPLACE(
                        REPLACE(
                            REPLACE(
                                REPLACE(
                                    REPLACE(raw_value, ' ', ''),
                                    CHAR(9), ''
                                ),
                                CHAR(10), ''
                            ),
                            CHAR(13), ''
                        ),
                        CHAR(194, 160 USING utf8mb4), ''
                    ),
                    CHAR(226, 128, 139 USING utf8mb4), ''
                ),
                CHAR(227, 128, 128 USING utf8mb4), ''
            )
        ) AS text_1
    FROM source_values
),
digits_1 AS (
    SELECT
        *,
        REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
            text_1,
            '０', '0'), '１', '1'), '２', '2'), '３', '3'), '４', '4')
            AS text_2
    FROM space_cleaned
),
digits_2 AS (
    SELECT
        *,
        REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
            text_2,
            '５', '5'), '６', '6'), '７', '7'), '８', '8'), '９', '9')
            AS text_3
    FROM digits_1
),
letters_1 AS (
    SELECT
        *,
        REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
            text_3,
            'Ａ', 'A'), 'Ｃ', 'C'), 'Ｔ', 'T'), 'Ｋ', 'K'), 'Ｒ', 'R')
            AS text_4
    FROM digits_2
),
letters_2 AS (
    SELECT
        *,
        REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
            text_4,
            'Ｍ', 'M'), 'Ｉ', 'I'), 'Ｎ', 'N'),
            'Ｓ', 'S'), 'Ｐ', 'P'), '＿', '_')
            AS cleaned_text
    FROM letters_1
),
canonical AS (
    SELECT
        *,
        CASE
            WHEN id_family = 'INSP'
             AND REGEXP_LIKE(
                 cleaned_text, '^INSP-[0-9]{6}$', 'c'
             )
            THEN REPLACE(cleaned_text, '-', '_')

            WHEN id_family = 'INSP'
             AND REGEXP_LIKE(cleaned_text, '^[0-9]{6}$', 'c')
            THEN CONCAT('INSP_', cleaned_text)

            WHEN id_family = 'KRM'
             AND REGEXP_LIKE(
                 cleaned_text, '^KRM-[0-9]{6}$', 'c'
             )
            THEN REPLACE(cleaned_text, '-', '')

            WHEN id_family = 'KRM'
             AND REGEXP_LIKE(cleaned_text, '^[0-9]{6}$', 'c')
            THEN CONCAT('KRM', cleaned_text)

            WHEN id_family = 'CAT'
             AND REGEXP_LIKE(
                 cleaned_text, '^CAT-[0-9]{5}$', 'c'
             )
            THEN REPLACE(cleaned_text, '-', '_')

            ELSE cleaned_text
        END AS canonical_text
    FROM letters_2
)
SELECT
    source_name,
    bronze_row_id,
    column_name,
    raw_value,
    canonical_text,

    CASE
        WHEN REGEXP_LIKE(canonical_text, expected_pattern, 'c')
        THEN canonical_text
        ELSE NULL
    END AS proposed_id,

    CASE
        WHEN COALESCE(canonical_text, '') IN (
            '', 'NULL', 'NONE', 'NA', 'N/A', 'NAN', '-'
        )
        THEN 'MISSING_CANDIDATE'

        WHEN NOT REGEXP_LIKE(
            canonical_text, expected_pattern, 'c'
        )
        THEN 'UNRESOLVED'

        WHEN HEX(raw_value) = HEX(canonical_text)
        THEN 'UNCHANGED'

        ELSE 'NORMALIZED_CANDIDATE'
    END AS normalization_status

FROM canonical;


-- 작업 23-2: 전체 표준화 후보 건수
-- 형식 통과는 실제 존재하는 ID라는 뜻이 아님

SELECT
    source_name,
    column_name,
    normalization_status,
    COUNT(*) AS row_count
FROM kream_project_repro.asis_identifier_normalization_v1
GROUP BY source_name, column_name, normalization_status
ORDER BY source_name, column_name, normalization_status;


-- 작업 23-3: 자동 해결하지 않은 값
-- 동일 원본값별로 묶고 건수 표시

SELECT
    source_name,
    column_name,
    raw_value,
    HEX(raw_value) AS raw_hex,
    canonical_text,
    COUNT(*) AS row_count
FROM kream_project_repro.asis_identifier_normalization_v1
WHERE normalization_status = 'UNRESOLVED'
GROUP BY
    source_name, column_name,
    raw_value, HEX(raw_value), canonical_text
ORDER BY source_name, column_name, row_count DESC, raw_hex
LIMIT 30;
