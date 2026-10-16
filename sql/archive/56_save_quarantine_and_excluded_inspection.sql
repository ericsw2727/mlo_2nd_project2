-- 작업 56-1: 저장 테이블 존재 여부 확인

SELECT COUNT(*) AS existing_tables
FROM information_schema.tables
WHERE table_schema = 'kream_project'
  AND table_name IN (
      'quarantine_inspection',
      'excluded_inspection'
  );


-- 작업 56-2: 격리 데이터 저장
-- 검사 결과, 격리 근거, 원본 업무 컬럼과 출처를 함께 보존

CREATE TABLE kream_project.quarantine_inspection
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin
AS
SELECT
    s.*,
    b.source_file,
    b.INSP_ID AS original_insp_id,
    b.REV_NO AS original_rev_no,
    b.ITEM_STD_CODE AS original_item_std_code,
    b.ITEM_NM AS original_item_name,
    b.PARENT_CAT_ID AS original_parent_cat_id,
    b.TRADE_PRICE_KRW AS original_trade_price,
    b.INSP_DURATION_MIN AS original_duration,
    b.INSP_RESULT AS original_insp_result,
    b.INSPECTOR_EMP_NO AS original_inspector_emp_no,
    b.INBOUND_DT AS original_inbound_dt,
    b.INSP_DONE_DT AS original_done_dt,
    b.EXTRACTED_AT AS original_extracted_at,
    b.INSP_MEMO AS original_memo

FROM kream_project.asis_inspection_disposition_stage_v2 AS s

JOIN kream_project.bronze_inspection AS b
  ON b.bronze_row_id = s.bronze_row_id

WHERE s.disposition = 'QUARANTINE';

SHOW WARNINGS;

ALTER TABLE kream_project.quarantine_inspection
    ADD PRIMARY KEY (bronze_row_id);


-- 작업 56-3: 제외 데이터 저장
-- 동일 중복과 정상 이전 개정의 원본 내용도 보존

CREATE TABLE kream_project.excluded_inspection
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin
AS
SELECT
    s.*,
    b.source_file,
    b.INSP_ID AS original_insp_id,
    b.REV_NO AS original_rev_no,
    b.ITEM_STD_CODE AS original_item_std_code,
    b.ITEM_NM AS original_item_name,
    b.PARENT_CAT_ID AS original_parent_cat_id,
    b.TRADE_PRICE_KRW AS original_trade_price,
    b.INSP_DURATION_MIN AS original_duration,
    b.INSP_RESULT AS original_insp_result,
    b.INSPECTOR_EMP_NO AS original_inspector_emp_no,
    b.INBOUND_DT AS original_inbound_dt,
    b.INSP_DONE_DT AS original_done_dt,
    b.EXTRACTED_AT AS original_extracted_at,
    b.INSP_MEMO AS original_memo

FROM kream_project.asis_inspection_disposition_stage_v2 AS s

JOIN kream_project.bronze_inspection AS b
  ON b.bronze_row_id = s.bronze_row_id

WHERE s.disposition = 'EXCLUDED';

SHOW WARNINGS;

ALTER TABLE kream_project.excluded_inspection
    ADD PRIMARY KEY (bronze_row_id);


-- 작업 56-4: 세 분류의 실제 저장 건수 확인

SELECT
    'SILVER' AS saved_class,
    COUNT(*) AS saved_rows
FROM kream_project.silver_inspection

UNION ALL

SELECT
    'QUARANTINE',
    COUNT(*)
FROM kream_project.quarantine_inspection

UNION ALL

SELECT
    'EXCLUDED',
    COUNT(*)
FROM kream_project.excluded_inspection;


-- 작업 56-5: 제외 사유별 저장 건수 확인

SELECT
    primary_reason,
    COUNT(*) AS saved_rows
FROM kream_project.excluded_inspection
GROUP BY primary_reason
ORDER BY primary_reason;


-- 작업 56-6: 원천 행마다 정확히 한 분류에 저장됐는지 확인
-- 단순 합계뿐 아니라 누락과 여러 분류에 중복 저장된 행도 확인

WITH saved_rows AS (
    SELECT source_bronze_row_id AS bronze_row_id
    FROM kream_project.silver_inspection

    UNION ALL

    SELECT bronze_row_id
    FROM kream_project.quarantine_inspection

    UNION ALL

    SELECT bronze_row_id
    FROM kream_project.excluded_inspection
),
assigned AS (
    SELECT
        bronze_row_id,
        COUNT(*) AS assignment_count
    FROM saved_rows
    GROUP BY bronze_row_id
)
SELECT
    COUNT(*) AS bronze_rows,

    SUM(
        CASE WHEN a.bronze_row_id IS NULL
             THEN 1 ELSE 0 END
    ) AS unassigned_rows,

    SUM(
        CASE WHEN a.assignment_count > 1
             THEN 1 ELSE 0 END
    ) AS multiple_assignment_rows,

    (
        SELECT COUNT(*)
        FROM assigned AS x
        LEFT JOIN kream_project.bronze_inspection AS original
          ON original.bronze_row_id = x.bronze_row_id
        WHERE original.bronze_row_id IS NULL
    ) AS unknown_source_rows

FROM kream_project.bronze_inspection AS b
LEFT JOIN assigned AS a
  ON a.bronze_row_id = b.bronze_row_id;


-- 작업 56-7 수정: 격리와 제외의 분류 및 원본 값 보존 확인

WITH inspection_payload_rows AS (
    SELECT
        'QUARANTINE' AS expected_disposition,
        q.*
    FROM kream_project.quarantine_inspection AS q

    UNION ALL

    SELECT
        'EXCLUDED' AS expected_disposition,
        e.*
    FROM kream_project.excluded_inspection AS e
)
SELECT
    COUNT(*) AS checked_saved_rows,

    SUM(
        CASE WHEN b.bronze_row_id IS NULL
             THEN 1 ELSE 0 END
    ) AS missing_original_rows,

    SUM(
        CASE
            WHEN s.bronze_row_id IS NULL
              OR NOT (s.disposition <=> p.expected_disposition)
              OR NOT (p.disposition <=> p.expected_disposition)
            THEN 1 ELSE 0
        END
    ) AS incorrect_disposition_rows,

    SUM(
        CASE
            WHEN b.bronze_row_id IS NOT NULL
             AND NOT (
                    (HEX(p.original_insp_id) <=> HEX(b.INSP_ID))
                AND (HEX(p.original_rev_no) <=> HEX(b.REV_NO))
                AND (HEX(p.original_item_std_code) <=> HEX(b.ITEM_STD_CODE))
                AND (HEX(p.original_item_name) <=> HEX(b.ITEM_NM))
                AND (HEX(p.original_parent_cat_id) <=> HEX(b.PARENT_CAT_ID))
                AND (HEX(p.original_trade_price) <=> HEX(b.TRADE_PRICE_KRW))
                AND (HEX(p.original_duration) <=> HEX(b.INSP_DURATION_MIN))
                AND (HEX(p.original_insp_result) <=> HEX(b.INSP_RESULT))
                AND (HEX(p.original_inspector_emp_no) <=> HEX(b.INSPECTOR_EMP_NO))
                AND (HEX(p.original_inbound_dt) <=> HEX(b.INBOUND_DT))
                AND (HEX(p.original_done_dt) <=> HEX(b.INSP_DONE_DT))
                AND (HEX(p.original_extracted_at) <=> HEX(b.EXTRACTED_AT))
                AND (HEX(p.original_memo) <=> HEX(b.INSP_MEMO))
                AND (HEX(p.source_file) <=> HEX(b.source_file))
             )
            THEN 1 ELSE 0
        END
    ) AS original_value_difference_rows

FROM inspection_payload_rows AS p

LEFT JOIN kream_project.bronze_inspection AS b
  ON b.bronze_row_id = p.bronze_row_id

LEFT JOIN kream_project.asis_inspection_disposition_stage_v2 AS s
  ON s.bronze_row_id = p.bronze_row_id;


-- 작업 56-7: 격리와 제외의 분류 및 원본 값 보존 확인
-- 원본 13개 컬럼과 출처를 정확한 값으로 비교
-- 세 오류 값 모두 0이어야 함

WITH stored AS (
    SELECT
        'QUARANTINE' AS expected_disposition,
        q.*
    FROM kream_project.quarantine_inspection AS q

    UNION ALL

    SELECT
        'EXCLUDED' AS expected_disposition,
        e.*
    FROM kream_project.excluded_inspection AS e
)
SELECT
    COUNT(*) AS checked_saved_rows,

    SUM(
        CASE WHEN b.bronze_row_id IS NULL
             THEN 1 ELSE 0 END
    ) AS missing_original_rows,

    SUM(
        CASE
            WHEN s.bronze_row_id IS NULL
              OR NOT (s.disposition <=> p.expected_disposition)
              OR NOT (p.disposition <=> p.expected_disposition)
            THEN 1 ELSE 0
        END
    ) AS incorrect_disposition_rows,

    SUM(
        CASE
            WHEN b.bronze_row_id IS NOT NULL
             AND NOT (
                    (HEX(p.original_insp_id) <=> HEX(b.INSP_ID))
                AND (HEX(p.original_rev_no) <=> HEX(b.REV_NO))
                AND (HEX(p.original_item_std_code) <=> HEX(b.ITEM_STD_CODE))
                AND (HEX(p.original_item_name) <=> HEX(b.ITEM_NM))
                AND (HEX(p.original_parent_cat_id) <=> HEX(b.PARENT_CAT_ID))
                AND (HEX(p.original_trade_price) <=> HEX(b.TRADE_PRICE_KRW))
                AND (HEX(p.original_duration) <=> HEX(b.INSP_DURATION_MIN))
                AND (HEX(p.original_insp_result) <=> HEX(b.INSP_RESULT))
                AND (HEX(p.original_inspector_emp_no) <=> HEX(b.INSPECTOR_EMP_NO))
                AND (HEX(p.original_inbound_dt) <=> HEX(b.INBOUND_DT))
                AND (HEX(p.original_done_dt) <=> HEX(b.INSP_DONE_DT))
                AND (HEX(p.original_extracted_at) <=> HEX(b.EXTRACTED_AT))
                AND (HEX(p.original_memo) <=> HEX(b.INSP_MEMO))
                AND (HEX(p.source_file) <=> HEX(b.source_file))
             )
            THEN 1 ELSE 0
        END
    ) AS original_value_difference_rows

FROM stored AS p

LEFT JOIN kream_project.bronze_inspection AS b
  ON b.bronze_row_id = p.bronze_row_id

LEFT JOIN kream_project.asis_inspection_disposition_stage_v2 AS s
  ON s.bronze_row_id = p.bronze_row_id;


