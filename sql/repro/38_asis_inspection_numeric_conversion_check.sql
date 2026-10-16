-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 38-1: 금액·소요시간 변환 후보
-- USD 고정 환율: 1,350원
-- 금액은 원, 소요시간은 분 기준
-- 음수·결측·-999를 0으로 채우지 않음
-- 자릿수 제한은 안전한 후보 변환을 위한 조건이며,
-- 최종 업무상 허용 범위는 별도로 검증
-- 원본 수정 없음

CREATE OR REPLACE VIEW
    kream_project_repro.asis_inspection_numeric_check_v1 AS

WITH converted AS (
    SELECT
        bronze_row_id,
        INSP_ID,
        REV_NO,
        TRADE_PRICE_KRW AS price_raw,
        INSP_DURATION_MIN AS duration_raw,

        CASE
            WHEN REGEXP_LIKE(
                TRADE_PRICE_KRW,
                '^[0-9]{1,12}([.][0-9]{1,4})?$'
            )
            THEN CAST(TRADE_PRICE_KRW AS DECIMAL(24,4))

            WHEN REGEXP_LIKE(
                TRADE_PRICE_KRW,
                '^([0-9]+|[0-9]{1,3}(,[0-9]{3})+)원$'
            )
             AND CHAR_LENGTH(
                 REPLACE(
                     REPLACE(TRADE_PRICE_KRW, '원', ''),
                     ',', ''
                 )
             ) <= 12
            THEN CAST(
                REPLACE(
                    REPLACE(TRADE_PRICE_KRW, '원', ''),
                    ',', ''
                ) AS DECIMAL(24,4)
            )

            WHEN REGEXP_LIKE(
                TRADE_PRICE_KRW,
                '^[0-9]{1,12}([.][0-9]{1,4})?만원$'
            )
            THEN CAST(
                REPLACE(TRADE_PRICE_KRW, '만원', '')
                AS DECIMAL(24,4)
            ) * 10000

            WHEN REGEXP_LIKE(
                TRADE_PRICE_KRW,
                '^[$][0-9]{1,12}([.][0-9]{1,4})?$'
            )
            THEN CAST(
                SUBSTRING(TRADE_PRICE_KRW, 2)
                AS DECIMAL(24,4)
            ) * 1350

            ELSE NULL
        END AS price_krw_candidate,

        CASE
            WHEN REGEXP_LIKE(
                INSP_DURATION_MIN,
                '^[0-9]{1,9}([.][0-9]{1,4})?$'
            )
            THEN CAST(INSP_DURATION_MIN AS DECIMAL(20,4))

            WHEN REGEXP_LIKE(
                INSP_DURATION_MIN,
                '^[0-9]{1,9}분[(]min[)]$', 'c'
            )
            THEN CAST(
                REPLACE(INSP_DURATION_MIN, '분(min)', '')
                AS DECIMAL(20,4)
            )

            WHEN REGEXP_LIKE(
                INSP_DURATION_MIN,
                '^[0-9]{1,9}초[(]sec[)]$', 'c'
            )
            THEN CAST(
                REPLACE(INSP_DURATION_MIN, '초(sec)', '')
                AS DECIMAL(20,4)
            ) / 60

            WHEN REGEXP_LIKE(
                INSP_DURATION_MIN,
                '^[0-9]{1,9}s$', 'c'
            )
            THEN CAST(
                REPLACE(INSP_DURATION_MIN, 's', '')
                AS DECIMAL(20,4)
            ) / 60

            ELSE NULL
        END AS duration_min_candidate

    FROM kream_project_repro.bronze_inspection
)
SELECT
    converted.*,

    CASE
        WHEN COALESCE(LOWER(TRIM(price_raw)), '') IN (
            '', 'null', 'none', 'na', 'n/a', 'nan', '-'
        )
        THEN 'MISSING_PRICE'

        WHEN REGEXP_LIKE(
            price_raw, '^-[0-9]+([.][0-9]+)?$'
        )
        THEN 'NEGATIVE_PRICE'

        WHEN price_krw_candidate IS NULL
        THEN 'PRICE_FORMAT_OR_RANGE_REVIEW'

        ELSE 'CONVERTED'
    END AS price_status,

    CASE
        WHEN TRIM(duration_raw) = '-999'
        THEN 'SENTINEL_MINUS_999'

        WHEN COALESCE(LOWER(TRIM(duration_raw)), '') IN (
            '', 'null', 'none', 'na', 'n/a', 'nan', '-'
        )
        THEN 'MISSING_DURATION'

        WHEN duration_min_candidate IS NULL
        THEN 'DURATION_FORMAT_OR_RANGE_REVIEW'

        ELSE 'CONVERTED'
    END AS duration_status

FROM converted;


-- 작업 38-2: 금액·시간 상태 조합별 건수
-- row_count 합계는 335,000이어야 함
-- 같은 행의 금액·시간 문제 중첩도 확인 가능

SELECT
    price_status,
    duration_status,
    COUNT(*) AS row_count
FROM kream_project_repro.asis_inspection_numeric_check_v1
GROUP BY price_status, duration_status
ORDER BY price_status, duration_status;


-- 작업 38-3: USD 환산 샘플
-- 환율은 시세가 아닌 사용자 지정 고정값

SELECT
    bronze_row_id,
    INSP_ID,
    price_raw,
    1350 AS fixed_usd_krw_rate,
    price_krw_candidate
FROM kream_project_repro.asis_inspection_numeric_check_v1
WHERE price_raw LIKE '$%'
ORDER BY bronze_row_id
LIMIT 5;


-- 작업 38-4: 변환값 범위·소수·0값 조사
-- 0이나 소수가 존재한다고 곧바로 오류로 판단하지 않음
-- 최종 자료형·업무 규칙 설계의 근거로 사용

SELECT
    COUNT(*) AS inspected_rows,
    COUNT(price_krw_candidate) AS price_converted_rows,
    COUNT(duration_min_candidate) AS duration_converted_rows,

    MIN(price_krw_candidate) AS min_price_krw,
    MAX(price_krw_candidate) AS max_price_krw,

    SUM(
        CASE WHEN price_krw_candidate = 0
             THEN 1 ELSE 0 END
    ) AS zero_price_rows,

    SUM(
        CASE
            WHEN price_krw_candidate <> FLOOR(price_krw_candidate)
            THEN 1 ELSE 0
        END
    ) AS fractional_price_rows,

    MIN(duration_min_candidate) AS min_duration_min,
    MAX(duration_min_candidate) AS max_duration_min,

    SUM(
        CASE WHEN duration_min_candidate = 0
             THEN 1 ELSE 0 END
    ) AS zero_duration_rows,

    SUM(
        CASE
            WHEN duration_min_candidate
                 <> FLOOR(duration_min_candidate)
            THEN 1 ELSE 0
        END
    ) AS fractional_duration_rows

FROM kream_project_repro.asis_inspection_numeric_check_v1;