-- 작업 59-1: 원천 행 연결 테이블 존재 여부 확인

SELECT COUNT(*) AS existing_tables
FROM information_schema.tables
WHERE table_schema = 'kream_project'
  AND table_name = 'asis_inspection_join_row_pair_v1';


-- 작업 59-2: 두 파일의 원천 행 연결 테이블 생성
-- 각 파일의 원천 행이 한 번만 연결되도록 제한

CREATE TABLE kream_project.asis_inspection_join_row_pair_v1 (
    inspection_bronze_row_id BIGINT UNSIGNED NOT NULL,
    join_ready_bronze_row_id BIGINT UNSIGNED NOT NULL,
    payload_sha256 CHAR(64)
        CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    payload_occurrence_no BIGINT UNSIGNED NOT NULL,

    PRIMARY KEY (inspection_bronze_row_id),

    UNIQUE KEY uq_join_ready_row (
        join_ready_bronze_row_id
    )
)
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin;


-- 작업 59-3: 공통 원본 내용과 중복 순서로 원천 행 연결

INSERT INTO kream_project.asis_inspection_join_row_pair_v1 (
    inspection_bronze_row_id,
    join_ready_bronze_row_id,
    payload_sha256,
    payload_occurrence_no
)
WITH ranked_payloads AS (
    SELECT
        source_name,
        bronze_row_id,
        payload_sha256,

        ROW_NUMBER() OVER (
            PARTITION BY source_name, payload_sha256
            ORDER BY bronze_row_id
        ) AS payload_occurrence_no

    FROM kream_project.asis_raw_payload_signature_v1
)
SELECT
    original_rows.bronze_row_id,
    joined_rows.bronze_row_id,
    original_rows.payload_sha256,
    original_rows.payload_occurrence_no

FROM ranked_payloads AS original_rows

JOIN ranked_payloads AS joined_rows
  ON joined_rows.source_name = 'JOIN_READY'
 AND joined_rows.payload_sha256 = original_rows.payload_sha256
 AND joined_rows.payload_occurrence_no =
        original_rows.payload_occurrence_no

WHERE original_rows.source_name = 'INSPECTION';

SHOW WARNINGS;


-- 작업 59-4: 연결 건수와 양쪽 원천 행 수 확인

SELECT
    COUNT(*) AS paired_rows,

    COUNT(DISTINCT inspection_bronze_row_id)
        AS distinct_inspection_rows,

    COUNT(DISTINCT join_ready_bronze_row_id)
        AS distinct_join_ready_rows

FROM kream_project.asis_inspection_join_row_pair_v1;


-- 작업 59-5: 두 파일의 연결 누락 확인
-- 두 값 모두 0이어야 함

SELECT
    (
        SELECT COUNT(*)
        FROM kream_project.bronze_inspection AS b

        LEFT JOIN
            kream_project.asis_inspection_join_row_pair_v1 AS p
          ON p.inspection_bronze_row_id = b.bronze_row_id

        WHERE p.inspection_bronze_row_id IS NULL
    ) AS unpaired_inspection_rows,

    (
        SELECT COUNT(*)
        FROM kream_project.bronze_inspection_join_ready AS b

        LEFT JOIN
            kream_project.asis_inspection_join_row_pair_v1 AS p
          ON p.join_ready_bronze_row_id = b.bronze_row_id

        WHERE p.join_ready_bronze_row_id IS NULL
    ) AS unpaired_join_ready_rows;


-- 작업 59-6: 연결된 행의 공통 원본 컬럼 13개 직접 비교
-- 앞선 비교값에만 의존하지 않고 원본 바이트를 다시 확인
-- 두 오류 값 모두 0이어야 함

SELECT
    COUNT(*) AS checked_pairs,

    SUM(
        CASE
            WHEN b.bronze_row_id IS NULL
              OR j.bronze_row_id IS NULL
            THEN 1 ELSE 0
        END
    ) AS missing_original_rows,

    SUM(
        CASE
            WHEN b.bronze_row_id IS NOT NULL
             AND j.bronze_row_id IS NOT NULL
             AND NOT (
                    (HEX(b.INSP_ID) <=> HEX(j.INSP_ID))
                AND (HEX(b.REV_NO) <=> HEX(j.REV_NO))
                AND (HEX(b.ITEM_STD_CODE) <=> HEX(j.ITEM_STD_CODE))
                AND (HEX(b.ITEM_NM) <=> HEX(j.ITEM_NM))
                AND (HEX(b.PARENT_CAT_ID) <=> HEX(j.PARENT_CAT_ID))
                AND (HEX(b.TRADE_PRICE_KRW) <=> HEX(j.TRADE_PRICE_KRW))
                AND (HEX(b.INSP_DURATION_MIN) <=> HEX(j.INSP_DURATION_MIN))
                AND (HEX(b.INSP_RESULT) <=> HEX(j.INSP_RESULT))
                AND (HEX(b.INSPECTOR_EMP_NO) <=> HEX(j.INSPECTOR_EMP_NO))
                AND (HEX(b.INBOUND_DT) <=> HEX(j.INBOUND_DT))
                AND (HEX(b.INSP_DONE_DT) <=> HEX(j.INSP_DONE_DT))
                AND (HEX(b.EXTRACTED_AT) <=> HEX(j.EXTRACTED_AT))
                AND (HEX(b.INSP_MEMO) <=> HEX(j.INSP_MEMO))
             )
            THEN 1 ELSE 0
        END
    ) AS shared_value_difference_rows

FROM kream_project.asis_inspection_join_row_pair_v1 AS p

LEFT JOIN kream_project.bronze_inspection AS b
  ON b.bronze_row_id = p.inspection_bronze_row_id

LEFT JOIN kream_project.bronze_inspection_join_ready AS j
  ON j.bronze_row_id = p.join_ready_bronze_row_id;