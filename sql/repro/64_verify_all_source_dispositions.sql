-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 64-1: 조인 통합본 분류 테이블 존재 여부 확인

SELECT COUNT(*) AS existing_tables
FROM information_schema.tables
WHERE table_schema = 'kream_project_repro'
  AND table_name = 'asis_join_ready_disposition_snapshot_v1';


-- 작업 64-2: 조인 통합본의 원천 행별 분류 테이블 생성
-- 두 파일의 공통 원본값 일치가 검증된 연결을 사용

CREATE TABLE kream_project_repro.asis_join_ready_disposition_snapshot_v1 (
    join_ready_bronze_row_id BIGINT UNSIGNED NOT NULL,
    inspection_bronze_row_id BIGINT UNSIGNED NOT NULL,
    disposition VARCHAR(32) NOT NULL,
    primary_reason VARCHAR(64) NOT NULL,
    rule_version VARCHAR(32) NOT NULL,

    PRIMARY KEY (join_ready_bronze_row_id),

    UNIQUE KEY uq_join_disposition_inspection (
        inspection_bronze_row_id
    ),

    CONSTRAINT ck_join_disposition
        CHECK (
            disposition IN (
                'SILVER',
                'QUARANTINE',
                'EXCLUDED'
            )
        )
)
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin;


-- 작업 64-3: 검수 원천의 확정된 분류 연결
-- 조인 통합본의 추가 컬럼은 정규 마스터와 공식으로 복구함

INSERT INTO kream_project_repro.asis_join_ready_disposition_snapshot_v1 (
    join_ready_bronze_row_id,
    inspection_bronze_row_id,
    disposition,
    primary_reason,
    rule_version
)
SELECT
    p.join_ready_bronze_row_id,
    p.inspection_bronze_row_id,

    CASE
        WHEN s.disposition = 'SILVER_CANDIDATE'
        THEN 'SILVER'
        ELSE s.disposition
    END,

    s.primary_reason,
    s.rule_version

FROM kream_project_repro.asis_inspection_join_row_pair_v1 AS p

JOIN kream_project_repro.asis_inspection_disposition_stage_v2 AS s
  ON s.bronze_row_id = p.inspection_bronze_row_id;

SHOW WARNINGS;


-- 작업 64-4: 조인 통합본의 분류 건수 확인

SELECT
    disposition,
    COUNT(*) AS source_rows
FROM kream_project_repro.asis_join_ready_disposition_snapshot_v1
GROUP BY disposition
ORDER BY disposition;


-- 작업 64-5: 조인 통합본 원천과 실제 정상 데이터 연결 검증
-- 원천 건수 외의 네 값은 모두 0이어야 함

SELECT
    COUNT(*) AS bronze_join_rows,

    SUM(
        CASE WHEN d.join_ready_bronze_row_id IS NULL
             THEN 1 ELSE 0 END
    ) AS missing_disposition_rows,

    SUM(
        CASE
            WHEN d.disposition = 'SILVER'
             AND j.source_bronze_row_id IS NULL
            THEN 1 ELSE 0
        END
    ) AS missing_silver_rows,

    SUM(
        CASE
            WHEN j.source_bronze_row_id IS NOT NULL
             AND d.disposition <> 'SILVER'
            THEN 1 ELSE 0
        END
    ) AS unexpected_silver_rows,

    (
        SELECT COUNT(*)
        FROM kream_project_repro.asis_join_ready_disposition_snapshot_v1 AS x

        LEFT JOIN kream_project_repro.bronze_inspection_join_ready AS original
          ON original.bronze_row_id = x.join_ready_bronze_row_id

        WHERE original.bronze_row_id IS NULL
    ) AS unknown_source_rows

FROM kream_project_repro.bronze_inspection_join_ready AS b

LEFT JOIN kream_project_repro.asis_join_ready_disposition_snapshot_v1 AS d
  ON d.join_ready_bronze_row_id = b.bronze_row_id

LEFT JOIN kream_project_repro.silver_inspection_join_ready AS j
  ON j.source_bronze_row_id = d.inspection_bronze_row_id;


-- 작업 64-6: 원본 파일 5개의 수신 건수와 처리 건수 대조
-- 사전은 전체 정상 처리되어 제외와 격리가 없음
-- 조인 통합본의 격리와 제외는 원천 행별 분류 연결로 집계
-- unaccounted_rows는 모든 행에서 0이어야 함

WITH source_counts AS (
    SELECT
        'PRODUCT_DICTIONARY' AS source_name,

        (SELECT COUNT(*)
         FROM kream_project_repro.bronze_product_std_dict) AS bronze_rows,

        (SELECT COUNT(*)
         FROM kream_project_repro.silver_product_std_dict) AS silver_rows,

        0 AS excluded_rows,
        0 AS quarantine_rows

    UNION ALL

    SELECT
        'CATEGORY_MASTER',

        (SELECT COUNT(*)
         FROM kream_project_repro.bronze_category_parent_lookup),

        (SELECT COUNT(*)
         FROM kream_project_repro.silver_category_parent_lookup),

        (SELECT COUNT(*)
         FROM kream_project_repro.excluded_category_parent_lookup),

        (SELECT COUNT(*)
         FROM kream_project_repro.quarantine_category_parent_lookup)

    UNION ALL

    SELECT
        'INSPECTOR_MASTER',

        (SELECT COUNT(*)
         FROM kream_project_repro.bronze_inspector_master),

        (SELECT COUNT(*)
         FROM kream_project_repro.silver_inspector_master),

        (SELECT COUNT(*)
         FROM kream_project_repro.excluded_inspector_master),

        (SELECT COUNT(*)
         FROM kream_project_repro.quarantine_inspector_master)

    UNION ALL

    SELECT
        'INSPECTION',

        (SELECT COUNT(*)
         FROM kream_project_repro.bronze_inspection),

        (SELECT COUNT(*)
         FROM kream_project_repro.silver_inspection),

        (SELECT COUNT(*)
         FROM kream_project_repro.excluded_inspection),

        (SELECT COUNT(*)
         FROM kream_project_repro.quarantine_inspection)

    UNION ALL

    SELECT
        'JOIN_READY',

        (SELECT COUNT(*)
         FROM kream_project_repro.bronze_inspection_join_ready),

        (SELECT COUNT(*)
         FROM kream_project_repro.silver_inspection_join_ready),

        (SELECT COUNT(*)
         FROM kream_project_repro.asis_join_ready_disposition_snapshot_v1
         WHERE disposition = 'EXCLUDED'),

        (SELECT COUNT(*)
         FROM kream_project_repro.asis_join_ready_disposition_snapshot_v1
         WHERE disposition = 'QUARANTINE')
)
SELECT
    source_name,
    bronze_rows,
    silver_rows,
    excluded_rows,
    quarantine_rows,

    CAST(bronze_rows AS SIGNED)
        - CAST(silver_rows AS SIGNED)
        - CAST(excluded_rows AS SIGNED)
        - CAST(quarantine_rows AS SIGNED) AS unaccounted_rows

FROM source_counts

UNION ALL

SELECT
    'ALL_INPUT_FILES',
    SUM(bronze_rows),
    SUM(silver_rows),
    SUM(excluded_rows),
    SUM(quarantine_rows),

    SUM(
        CAST(bronze_rows AS SIGNED)
            - CAST(silver_rows AS SIGNED)
            - CAST(excluded_rows AS SIGNED)
            - CAST(quarantine_rows AS SIGNED)
    )

FROM source_counts

ORDER BY source_name;