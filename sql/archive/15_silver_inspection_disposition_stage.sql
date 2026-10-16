-- 작업 15-1: 1차 처리 구분 뷰
-- NORMAL_CANDIDATE는 최종 정상 확정이 아님
-- 날짜·참조 관계·업무 규칙 검사는 이후 추가
-- 원본 수정·삭제 없음

CREATE OR REPLACE VIEW
    kream_project.silver_inspection_disposition_stage_v1 AS
WITH key_summary AS (
    SELECT
        HEX(INSP_ID) AS id_hex,
        HEX(REV_NO) AS revision_hex,
        COUNT(*) AS key_row_count,

        -- 키를 제외한 원본 11개 컬럼 비교
        COUNT(DISTINCT
            COALESCE(HEX(ITEM_STD_CODE), 'NULL'),
            COALESCE(HEX(ITEM_NM), 'NULL'),
            COALESCE(HEX(PARENT_CAT_ID), 'NULL'),
            COALESCE(HEX(TRADE_PRICE_KRW), 'NULL'),
            COALESCE(HEX(INSP_DURATION_MIN), 'NULL'),
            COALESCE(HEX(INSP_RESULT), 'NULL'),
            COALESCE(HEX(INSPECTOR_EMP_NO), 'NULL'),
            COALESCE(HEX(INBOUND_DT), 'NULL'),
            COALESCE(HEX(INSP_DONE_DT), 'NULL'),
            COALESCE(HEX(EXTRACTED_AT), 'NULL'),
            COALESCE(HEX(INSP_MEMO), 'NULL')
        ) AS raw_content_versions

    FROM kream_project.bronze_inspection
    GROUP BY HEX(INSP_ID), HEX(REV_NO)
),
ranked AS (
    SELECT
        s.*,
        ROW_NUMBER() OVER (
            PARTITION BY HEX(INSP_ID), HEX(REV_NO)
            ORDER BY bronze_row_id
        ) AS occurrence_no
    FROM kream_project.silver_inspection_unit_stage_v1 AS s
),
evaluated AS (
    SELECT
        r.*,
        k.key_row_count,
        k.raw_content_versions,

        CASE
            WHEN NULLIF(TRIM(r.INSP_ID), '') IS NULL
              OR NULLIF(TRIM(r.REV_NO), '') IS NULL
              OR NOT REGEXP_LIKE(r.REV_NO, '^[1-9][0-9]*$')
            THEN 'KEY_REVIEW'

            WHEN k.raw_content_versions > 1
            THEN 'REVISION_CONFLICT'

            WHEN r.occurrence_no > 1
            THEN 'IDENTICAL_REPEAT'

            WHEN r.unit_stage_status = 'REVIEW_REQUIRED'
            THEN 'UNIT_REVIEW'

            ELSE 'PENDING_OTHER_CHECKS'
        END AS primary_reason

    FROM ranked AS r
    JOIN key_summary AS k
      ON HEX(r.INSP_ID) <=> k.id_hex
     AND HEX(r.REV_NO) <=> k.revision_hex
)
SELECT
    evaluated.*,
    CASE
        WHEN primary_reason = 'IDENTICAL_REPEAT'
        THEN 'EXCLUDED'

        WHEN primary_reason IN (
            'KEY_REVIEW',
            'REVISION_CONFLICT',
            'UNIT_REVIEW'
        )
        THEN 'QUARANTINED'

        ELSE 'NORMAL_CANDIDATE'
    END AS disposition
FROM evaluated;


-- 작업 15-2: 처리 결과 및 대표 사유별 건수
-- 이 결과의 row_count 합계는 335,000이어야 함

SELECT
    disposition,
    primary_reason,
    COUNT(*) AS row_count
FROM kream_project.silver_inspection_disposition_stage_v1
GROUP BY disposition, primary_reason
ORDER BY disposition, primary_reason;


-- 작업 15-3: 전체 건수 정합성 확인

SELECT
    COUNT(*) AS total_rows,
    SUM(disposition = 'NORMAL_CANDIDATE')
        AS normal_candidate_rows,
    SUM(disposition = 'QUARANTINED')
        AS quarantined_rows,
    SUM(disposition = 'EXCLUDED')
        AS excluded_rows
FROM kream_project.silver_inspection_disposition_stage_v1;


-- 작업 15-4: 격리·제외 샘플
-- 유형별 최대 3행

WITH samples AS (
    SELECT
        bronze_row_id,
        INSP_ID,
        REV_NO,
        TRADE_PRICE_KRW AS price_raw,
        trade_price_krw_clean,
        INSP_DURATION_MIN AS duration_raw,
        insp_duration_min_clean,
        INSP_RESULT,
        disposition,
        primary_reason,
        ROW_NUMBER() OVER (
            PARTITION BY primary_reason
            ORDER BY bronze_row_id
        ) AS sample_no
    FROM kream_project.silver_inspection_disposition_stage_v1
    WHERE disposition <> 'NORMAL_CANDIDATE'
)
SELECT *
FROM samples
WHERE sample_no <= 3
ORDER BY primary_reason, sample_no;