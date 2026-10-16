-- 작업 17-1: 검수 원천의 필수 컬럼 전체 기본 결측 검사
-- 명세서상 선택 컬럼 PARENT_CAT_ID, INSP_MEMO는 제외
-- NULL, 빈 문자열, 일반 공백만 있는 값 검사
-- 문자열 NULL/NA 등은 별도의 결측 표기 검사 대상
-- 컬럼별 건수는 같은 행에 중복될 수 있음
-- 원본 수정 없음

SELECT
    COUNT(*) AS total_rows,

    SUM(NULLIF(TRIM(INSP_ID), '') IS NULL)
        AS missing_insp_id_rows,

    SUM(NULLIF(TRIM(REV_NO), '') IS NULL)
        AS missing_rev_no_rows,

    SUM(NULLIF(TRIM(ITEM_STD_CODE), '') IS NULL)
        AS missing_item_code_rows,

    SUM(NULLIF(TRIM(ITEM_NM), '') IS NULL)
        AS missing_item_name_rows,

    SUM(NULLIF(TRIM(TRADE_PRICE_KRW), '') IS NULL)
        AS missing_price_rows,

    SUM(NULLIF(TRIM(INSP_DURATION_MIN), '') IS NULL)
        AS missing_duration_rows,

    SUM(NULLIF(TRIM(INSP_RESULT), '') IS NULL)
        AS missing_result_rows,

    SUM(NULLIF(TRIM(INSPECTOR_EMP_NO), '') IS NULL)
        AS missing_inspector_rows,

    SUM(NULLIF(TRIM(INBOUND_DT), '') IS NULL)
        AS missing_inbound_rows,

    SUM(NULLIF(TRIM(INSP_DONE_DT), '') IS NULL)
        AS missing_done_rows,

    SUM(NULLIF(TRIM(EXTRACTED_AT), '') IS NULL)
        AS missing_extracted_rows

FROM kream_project.bronze_inspection;


-- 작업 17-2: 필수 컬럼의 결측 표기·숨은 공백 검사
-- 입력: 검수 원천의 필수 11개 컬럼
-- 검사:
-- 1. SQL NULL·빈 문자열·일반 공백
-- 2. 탭·줄바꿈·특수 공백만 있는 값
-- 3. NULL, NA 등 문자열 결측 후보
-- 원본 수정 없음
-- -999는 별도 소요시간 규칙에서 처리하므로 여기서 제외

WITH required_values AS (
    SELECT bronze_row_id, 'INSP_ID' AS column_name,
           INSP_ID AS raw_value
    FROM kream_project.bronze_inspection
    UNION ALL
    SELECT bronze_row_id, 'REV_NO', REV_NO
    FROM kream_project.bronze_inspection
    UNION ALL
    SELECT bronze_row_id, 'ITEM_STD_CODE', ITEM_STD_CODE
    FROM kream_project.bronze_inspection
    UNION ALL
    SELECT bronze_row_id, 'ITEM_NM', ITEM_NM
    FROM kream_project.bronze_inspection
    UNION ALL
    SELECT bronze_row_id, 'TRADE_PRICE_KRW', TRADE_PRICE_KRW
    FROM kream_project.bronze_inspection
    UNION ALL
    SELECT bronze_row_id, 'INSP_DURATION_MIN', INSP_DURATION_MIN
    FROM kream_project.bronze_inspection
    UNION ALL
    SELECT bronze_row_id, 'INSP_RESULT', INSP_RESULT
    FROM kream_project.bronze_inspection
    UNION ALL
    SELECT bronze_row_id, 'INSPECTOR_EMP_NO', INSPECTOR_EMP_NO
    FROM kream_project.bronze_inspection
    UNION ALL
    SELECT bronze_row_id, 'INBOUND_DT', INBOUND_DT
    FROM kream_project.bronze_inspection
    UNION ALL
    SELECT bronze_row_id, 'INSP_DONE_DT', INSP_DONE_DT
    FROM kream_project.bronze_inspection
    UNION ALL
    SELECT bronze_row_id, 'EXTRACTED_AT', EXTRACTED_AT
    FROM kream_project.bronze_inspection
),
cleaned_for_check AS (
    SELECT
        *,
        TRIM(
            REPLACE(
                REPLACE(
                    REPLACE(
                        REPLACE(
                            REPLACE(
                                REPLACE(
                                    raw_value,
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
        ) AS check_value
    FROM required_values
),
classified AS (
    SELECT
        *,
        CASE
            WHEN NULLIF(TRIM(raw_value), '') IS NULL
            THEN 'BASIC_MISSING'

            WHEN check_value = ''
            THEN 'HIDDEN_WHITESPACE_ONLY'

            WHEN LOWER(check_value) IN (
                'null', 'none', 'na', 'n/a', 'nan', '-'
            )
            THEN 'MISSING_TOKEN_CANDIDATE'

            ELSE 'PRESENT'
        END AS value_status
    FROM cleaned_for_check
)
SELECT
    column_name,
    COUNT(*) AS inspected_rows,
    SUM(value_status = 'BASIC_MISSING')
        AS basic_missing_rows,
    SUM(value_status = 'HIDDEN_WHITESPACE_ONLY')
        AS hidden_whitespace_only_rows,
    SUM(value_status = 'MISSING_TOKEN_CANDIDATE')
        AS missing_token_candidate_rows,
    SUM(value_status <> 'PRESENT')
        AS missing_candidate_rows
FROM classified
GROUP BY column_name
ORDER BY column_name;


-- 작업 17-3: 사번·금액 결측 표기와 행별 중첩 확인
-- 모든 수신 행을 두 컬럼의 상태 조합으로 분류
-- 원본 수정 없음
-- 결측 후보는 검토 대상이며 여기서 격리하지 않음

WITH source_values AS (
    SELECT
        bronze_row_id,
        'PRICE' AS column_name,
        TRADE_PRICE_KRW AS raw_value
    FROM kream_project.bronze_inspection

    UNION ALL

    SELECT
        bronze_row_id,
        'INSPECTOR',
        INSPECTOR_EMP_NO
    FROM kream_project.bronze_inspection
),
cleaned_for_check AS (
    SELECT
        bronze_row_id,
        column_name,
        TRIM(
            REPLACE(
                REPLACE(
                    REPLACE(
                        REPLACE(
                            REPLACE(
                                REPLACE(
                                    raw_value,
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
        ) AS check_value
    FROM source_values
),
classified AS (
    SELECT
        bronze_row_id,
        column_name,
        CASE
            WHEN check_value IS NULL THEN 'SQL_NULL'
            WHEN check_value = '' THEN 'EMPTY'
            WHEN LOWER(check_value) IN (
                'null', 'none', 'na', 'n/a', 'nan', '-'
            )
            THEN CONCAT('TOKEN:', LOWER(check_value))
            ELSE 'PRESENT'
        END AS value_status
    FROM cleaned_for_check
),
row_status AS (
    SELECT
        bronze_row_id,
        MAX(CASE WHEN column_name = 'PRICE'
                 THEN value_status END) AS price_status,
        MAX(CASE WHEN column_name = 'INSPECTOR'
                 THEN value_status END) AS inspector_status
    FROM classified
    GROUP BY bronze_row_id
)
SELECT
    price_status,
    inspector_status,
    COUNT(*) AS row_count,
    MIN(bronze_row_id) AS example_row_id
FROM row_status
GROUP BY price_status, inspector_status
ORDER BY price_status, inspector_status;

