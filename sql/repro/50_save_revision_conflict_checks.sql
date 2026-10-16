-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 50-1: 저장 테이블 존재 여부 확인

SELECT COUNT(*) AS existing_tables
FROM information_schema.tables
WHERE table_schema = 'kream_project_repro'
  AND table_name = 'asis_revision_group_snapshot_v1';


-- 작업 50-2: 동일 검수 ID와 개정 번호의 집계 테이블 생성

CREATE TABLE kream_project_repro.asis_revision_group_snapshot_v1 (
    normalized_insp_id VARCHAR(20) NOT NULL,
    normalized_rev_no INT NOT NULL,
    rows_per_key BIGINT UNSIGNED NOT NULL,
    raw_payload_versions BIGINT UNSIGNED NOT NULL,

    PRIMARY KEY (
        normalized_insp_id,
        normalized_rev_no
    )
)
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin;


-- 작업 50-3: 원본 내용의 차이를 계산하여 저장
-- HEX로 원본 값의 차이를 비교
-- NULL도 별도 값으로 포함
-- 원본 데이터와 기존 정규화 기준은 변경하지 않음

INSERT INTO kream_project_repro.asis_revision_group_snapshot_v1 (
    normalized_insp_id,
    normalized_rev_no,
    rows_per_key,
    raw_payload_versions
)
SELECT
    k.normalized_insp_id,
    k.normalized_rev_no,
    COUNT(*) AS rows_per_key,

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

FROM kream_project_repro.asis_inspection_key_snapshot_v1 AS k
JOIN kream_project_repro.bronze_inspection AS b
  ON b.bronze_row_id = k.bronze_row_id

GROUP BY
    k.normalized_insp_id,
    k.normalized_rev_no;

SHOW WARNINGS;


-- 작업 50-4: 단일 행, 동일 내용 중복, 개정 충돌 구분

SELECT
    CASE
        WHEN raw_payload_versions > 1
            THEN 'REVISION_CONFLICT'
        WHEN rows_per_key > 1
            THEN 'IDENTICAL_DUPLICATE'
        ELSE 'SINGLE_RECORD'
    END AS revision_group_status,

    COUNT(*) AS key_groups,
    SUM(rows_per_key) AS source_rows

FROM kream_project_repro.asis_revision_group_snapshot_v1

GROUP BY
    CASE
        WHEN raw_payload_versions > 1
            THEN 'REVISION_CONFLICT'
        WHEN rows_per_key > 1
            THEN 'IDENTICAL_DUPLICATE'
        ELSE 'SINGLE_RECORD'
    END

ORDER BY revision_group_status;


-- 작업 50-5: 원천 행에 연결되는 검사 결과의 누락 확인
-- missing_group_rows는 0이어야 함

SELECT
    COUNT(*) AS checked_source_rows,

    SUM(
        CASE
            WHEN g.normalized_insp_id IS NULL
            THEN 1 ELSE 0
        END
    ) AS missing_group_rows,

    SUM(
        CASE
            WHEN g.raw_payload_versions > 1
            THEN 1 ELSE 0
        END
    ) AS conflict_source_rows

FROM kream_project_repro.asis_inspection_key_snapshot_v1 AS k

LEFT JOIN kream_project_repro.asis_revision_group_snapshot_v1 AS g
  ON g.normalized_insp_id = k.normalized_insp_id
 AND g.normalized_rev_no = k.normalized_rev_no;


-- 작업 50-6: 전체 집계 건수 확인

SELECT
    COUNT(*) AS saved_key_groups,
    SUM(rows_per_key) AS represented_source_rows
FROM kream_project_repro.asis_revision_group_snapshot_v1;