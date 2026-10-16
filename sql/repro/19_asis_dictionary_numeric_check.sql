-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 19-1: 표준 사전 숫자 범위·소수 자릿수 검사
-- BASE_RETAIL_KRW: 비음수 정수, MySQL SIGNED INT 범위
-- FAKE_PENALTY_MULTIPLIER: 비음수 숫자, NUMERIC(3,1)
-- 형식·변환 가능 범위 확인 후에만 CAST 수행
-- 원본 수정 및 반올림 없음

WITH parsed AS (
    SELECT
        bronze_row_id,
        DICT_ID,
        BASE_RETAIL_KRW,
        FAKE_PENALTY_MULTIPLIER,

        CASE
            WHEN REGEXP_LIKE(BASE_RETAIL_KRW, '^[0-9]+$')
             AND CHAR_LENGTH(BASE_RETAIL_KRW) <= 65
            THEN CAST(BASE_RETAIL_KRW AS DECIMAL(65,0))
            ELSE NULL
        END AS retail_value,

        CASE
            WHEN REGEXP_LIKE(
                FAKE_PENALTY_MULTIPLIER,
                '^[0-9]+([.][0-9]+)?$'
            )
             AND CHAR_LENGTH(FAKE_PENALTY_MULTIPLIER) <= 60
             AND (
                 LOCATE('.', FAKE_PENALTY_MULTIPLIER) = 0
                 OR CHAR_LENGTH(
                     SUBSTRING_INDEX(
                         FAKE_PENALTY_MULTIPLIER, '.', -1
                     )
                 ) <= 1
             )
            THEN CAST(
                FAKE_PENALTY_MULTIPLIER AS DECIMAL(65,1)
            )
            ELSE NULL
        END AS multiplier_value
    FROM kream_project_repro.bronze_product_std_dict
)
SELECT
    COUNT(*) AS inspected_rows,

    SUM(
        CASE WHEN retail_value IS NULL
             THEN 1 ELSE 0 END
    ) AS retail_format_or_parse_review_rows,

    SUM(
        CASE WHEN retail_value > 2147483647
             THEN 1 ELSE 0 END
    ) AS retail_int_range_exceeded_rows,

    SUM(
        CASE
            WHEN LOCATE('.', FAKE_PENALTY_MULTIPLIER) > 0
             AND CHAR_LENGTH(
                 SUBSTRING_INDEX(
                     FAKE_PENALTY_MULTIPLIER, '.', -1
                 )
             ) > 1
            THEN 1 ELSE 0
        END
    ) AS multiplier_scale_review_rows,

    SUM(
        CASE WHEN multiplier_value IS NULL
             THEN 1 ELSE 0 END
    ) AS multiplier_format_or_parse_review_rows,

    SUM(
        CASE WHEN multiplier_value > 99.9
             THEN 1 ELSE 0 END
    ) AS multiplier_numeric_range_exceeded_rows

FROM parsed;