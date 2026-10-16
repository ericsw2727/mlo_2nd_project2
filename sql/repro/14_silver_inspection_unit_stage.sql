-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 14-1: 금액·소요시간 1차 정제 뷰
-- 원본은 유지하고 정제값을 별도 컬럼으로 제공
-- 달러·음수·결측·해석 불가 값은 임의로 채우지 않음

CREATE OR REPLACE VIEW
    kream_project_repro.silver_inspection_unit_stage_v1 AS
WITH converted AS (
    SELECT
        b.*,

        -- 금액: 원 단위로 통일
        -- 숫자 자릿수를 제한해 변환 범위 초과를 방지
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
                 REPLACE(REPLACE(TRADE_PRICE_KRW, '원', ''), ',', '')
             ) <= 12
            THEN CAST(
                REPLACE(REPLACE(TRADE_PRICE_KRW, '원', ''), ',', '')
                AS DECIMAL(24,4)
            )

            WHEN REGEXP_LIKE(
                TRADE_PRICE_KRW,
                '^[0-9]{1,12}([.][0-9]{1,4})?만원$'
            )
            THEN CAST(
                REPLACE(TRADE_PRICE_KRW, '만원', '')
                AS DECIMAL(24,4)
            ) * 10000

            ELSE NULL
        END AS trade_price_krw_clean,

        -- 소요시간: 분 단위로 통일
        -- -999는 정상 시간으로 변환하지 않음
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
                INSP_DURATION_MIN, '^[0-9]{1,9}s$', 'c'
            )
            THEN CAST(
                REPLACE(INSP_DURATION_MIN, 's', '')
                AS DECIMAL(20,4)
            ) / 60

            ELSE NULL
        END AS insp_duration_min_clean

    FROM kream_project_repro.bronze_inspection AS b
)
SELECT
    converted.*,
    CASE
        WHEN trade_price_krw_clean IS NULL
          OR insp_duration_min_clean IS NULL
        THEN 'REVIEW_REQUIRED'
        ELSE 'UNIT_CONVERSION_OK'
    END AS unit_stage_status
FROM converted;


-- 작업 14-2: 단위 정제 결과 집계
-- UNIT_CONVERSION_OK는 단위 변환 성공만 의미함
-- 중복·충돌·참조·업무 규칙 검증 통과를 의미하지 않음

SELECT
    COUNT(*) AS total_rows,
    COUNT(trade_price_krw_clean) AS price_converted_rows,
    COUNT(insp_duration_min_clean) AS duration_converted_rows,
    SUM(unit_stage_status = 'UNIT_CONVERSION_OK')
        AS both_converted_rows,
    SUM(unit_stage_status = 'REVIEW_REQUIRED')
        AS review_required_rows
FROM kream_project_repro.silver_inspection_unit_stage_v1;


-- 작업 14-3: 원본과 정제값 비교
-- 단위 표기가 포함된 데이터에서 20행 확인

SELECT
    bronze_row_id,
    INSP_ID,
    REV_NO,
    TRADE_PRICE_KRW AS price_raw,
    trade_price_krw_clean,
    INSP_DURATION_MIN AS duration_raw,
    insp_duration_min_clean,
    unit_stage_status
FROM kream_project_repro.silver_inspection_unit_stage_v1
WHERE TRADE_PRICE_KRW LIKE '%원'
   OR INSP_DURATION_MIN LIKE '%분(min)'
   OR INSP_DURATION_MIN LIKE '%초(sec)'
   OR REGEXP_LIKE(INSP_DURATION_MIN, '^[0-9]+s$', 'c')
ORDER BY bronze_row_id
LIMIT 20;