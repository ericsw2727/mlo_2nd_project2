-- 작업 37-1: 보정된 검수 키의 검사 전용 스냅샷
-- 현재 원본의 REV_NO가 1·2이며 유효함은 13번에서 확인
-- Bronze 원본 변경 없음

CREATE TABLE kream_project.asis_inspection_key_snapshot_v1 (
    bronze_row_id BIGINT UNSIGNED NOT NULL,
    raw_insp_id TEXT,
    normalized_insp_id VARCHAR(20),
    raw_rev_no TEXT,
    normalized_rev_no INT,

    PRIMARY KEY (bronze_row_id),

    INDEX ix_normalized_revision (
        normalized_insp_id,
        normalized_rev_no
    )
)
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin;


INSERT INTO kream_project.asis_inspection_key_snapshot_v1 (
    bronze_row_id,
    raw_insp_id,
    normalized_insp_id,
    raw_rev_no,
    normalized_rev_no
)
SELECT
    b.bronze_row_id,
    b.INSP_ID,
    n.proposed_id,
    b.REV_NO,
    CAST(b.REV_NO AS SIGNED)
FROM kream_project.bronze_inspection AS b
JOIN kream_project.asis_identifier_normalization_v1 AS n
  ON n.source_name = 'INSPECTION'
 AND n.column_name = 'INSP_ID'
 AND n.bronze_row_id = b.bronze_row_id;

SHOW WARNINGS;


-- 작업 37-2: 키 저장 건수 및 누락 확인

SELECT
    COUNT(*) AS snapshot_rows,
    COUNT(DISTINCT normalized_insp_id)
        AS normalized_inspection_ids,
    COUNT(DISTINCT normalized_insp_id, normalized_rev_no)
        AS normalized_revision_keys,
    SUM(
        CASE
            WHEN normalized_insp_id IS NULL
              OR normalized_rev_no IS NULL
            THEN 1 ELSE 0
        END
    ) AS unresolved_key_rows
FROM kream_project.asis_inspection_key_snapshot_v1;


-- 작업 37-3: 보정된 개정키별 원본 내용 비교
-- 보정된 ID 표기와 나머지 원본 내용 차이를 분리
-- 내용 차이는 검토 대상으로 집계
-- 나머지 컬럼 표준화 후의 의미상 비교는 이후 별도 수행
-- 원본 수정·중복 제거·격리 없음

WITH key_groups AS (
    SELECT
        k.normalized_insp_id,
        k.normalized_rev_no,
        COUNT(*) AS rows_per_key,

        COUNT(DISTINCT HEX(b.INSP_ID))
            AS raw_id_versions,

        COUNT(DISTINCT
            COALESCE(HEX(b.ITEM_STD_CODE), 'NULL'),
            COALESCE(HEX(b.ITEM_NM), 'NULL'),
            COALESCE(HEX(b.PARENT_CAT_ID), 'NULL'),
            COALESCE(HEX(b.TRADE_PRICE_KRW), 'NULL'),
            COALESCE(HEX(b.INSP_DURATION_MIN), 'NULL'),
            COALESCE(HEX(b.INSP_RESULT), 'NULL'),
            COALESCE(HEX(b.INSPECTOR_EMP_NO), 'NULL'),
            COALESCE(HEX(b.INBOUND_DT), 'NULL'),
            COALESCE(HEX(b.INSP_DONE_DT), 'NULL'),
            COALESCE(HEX(b.EXTRACTED_AT), 'NULL'),
            COALESCE(HEX(b.INSP_MEMO), 'NULL')
        ) AS raw_payload_versions

    FROM kream_project.asis_inspection_key_snapshot_v1 AS k
    JOIN kream_project.bronze_inspection AS b
      ON b.bronze_row_id = k.bronze_row_id

    WHERE k.normalized_insp_id IS NOT NULL
      AND k.normalized_rev_no IS NOT NULL

    GROUP BY k.normalized_insp_id, k.normalized_rev_no
)
SELECT
    SUM(rows_per_key) AS inspected_rows,
    COUNT(*) AS normalized_revision_keys,

    SUM(
        CASE WHEN rows_per_key > 1
             THEN 1 ELSE 0 END
    ) AS repeated_key_groups,

    SUM(rows_per_key - 1) AS additional_rows,

    SUM(
        CASE
            WHEN rows_per_key > 1
             AND raw_payload_versions = 1
            THEN 1 ELSE 0
        END
    ) AS same_payload_repeated_groups,

    SUM(
        CASE WHEN raw_payload_versions > 1
             THEN 1 ELSE 0 END
    ) AS different_payload_groups,

    SUM(
        CASE WHEN raw_id_versions > 1
             THEN 1 ELSE 0 END
    ) AS multiple_raw_id_spellings_groups

FROM key_groups;