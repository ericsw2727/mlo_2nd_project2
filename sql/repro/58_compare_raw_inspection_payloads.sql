-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 58-1: 비교용 테이블 존재 여부 확인

SELECT COUNT(*) AS existing_tables
FROM information_schema.tables
WHERE table_schema = 'kream_project_repro'
  AND table_name = 'asis_raw_payload_signature_v1';


-- 작업 58-2: 원본값 비교용 테이블 생성
-- 원본 테이블과 값은 변경하지 않음
-- 파일별 원천 행 번호와 공통 업무 컬럼의 비교값 저장

CREATE TABLE kream_project_repro.asis_raw_payload_signature_v1 (
    source_name VARCHAR(32) NOT NULL,
    bronze_row_id BIGINT UNSIGNED NOT NULL,
    payload_sha256 CHAR(64)
        CHARACTER SET ascii COLLATE ascii_bin NOT NULL,

    PRIMARY KEY (source_name, bronze_row_id),

    INDEX ix_raw_payload_signature (
        payload_sha256,
        source_name
    )
)
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin;


-- 작업 58-3: 두 파일의 공통 원본 컬럼 13개 비교값 저장
-- HEX로 원본 바이트를 반영
-- NULL과 빈 문자열도 서로 구분
-- 출처 파일명과 조인 통합본의 추가 5개 컬럼은 비교 대상에서 제외

INSERT INTO kream_project_repro.asis_raw_payload_signature_v1 (
    source_name,
    bronze_row_id,
    payload_sha256
)
SELECT
    'INSPECTION',
    b.bronze_row_id,

    SHA2(
        CAST(
            JSON_ARRAY(
                HEX(b.INSP_ID),
                HEX(b.REV_NO),
                HEX(b.ITEM_STD_CODE),
                HEX(b.ITEM_NM),
                HEX(b.PARENT_CAT_ID),
                HEX(b.TRADE_PRICE_KRW),
                HEX(b.INSP_DURATION_MIN),
                HEX(b.INSP_RESULT),
                HEX(b.INSPECTOR_EMP_NO),
                HEX(b.INBOUND_DT),
                HEX(b.INSP_DONE_DT),
                HEX(b.EXTRACTED_AT),
                HEX(b.INSP_MEMO)
            ) AS CHAR CHARACTER SET utf8mb4
        ),
        256
    )

FROM kream_project_repro.bronze_inspection AS b

UNION ALL

SELECT
    'JOIN_READY',
    b.bronze_row_id,

    SHA2(
        CAST(
            JSON_ARRAY(
                HEX(b.INSP_ID),
                HEX(b.REV_NO),
                HEX(b.ITEM_STD_CODE),
                HEX(b.ITEM_NM),
                HEX(b.PARENT_CAT_ID),
                HEX(b.TRADE_PRICE_KRW),
                HEX(b.INSP_DURATION_MIN),
                HEX(b.INSP_RESULT),
                HEX(b.INSPECTOR_EMP_NO),
                HEX(b.INBOUND_DT),
                HEX(b.INSP_DONE_DT),
                HEX(b.EXTRACTED_AT),
                HEX(b.INSP_MEMO)
            ) AS CHAR CHARACTER SET utf8mb4
        ),
        256
    )

FROM kream_project_repro.bronze_inspection_join_ready AS b;

SHOW WARNINGS;


-- 작업 58-4: 파일별 비교 대상 저장 건수 확인

SELECT
    source_name,
    COUNT(*) AS saved_rows,
    COUNT(DISTINCT bronze_row_id) AS distinct_source_rows
FROM kream_project_repro.asis_raw_payload_signature_v1
GROUP BY source_name
ORDER BY source_name;


-- 작업 58-5: 같은 원본 내용의 등장 횟수 비교
-- 내용뿐 아니라 동일 중복의 개수도 같아야 함
-- 세 오류 값 모두 0이면 두 파일의 비교값과 등장 횟수가 일치

WITH payload_counts AS (
    SELECT
        payload_sha256,

        SUM(
            CASE WHEN source_name = 'INSPECTION'
                 THEN 1 ELSE 0 END
        ) AS inspection_rows,

        SUM(
            CASE WHEN source_name = 'JOIN_READY'
                 THEN 1 ELSE 0 END
        ) AS join_ready_rows

    FROM kream_project_repro.asis_raw_payload_signature_v1
    GROUP BY payload_sha256
)
SELECT
    COUNT(*) AS distinct_payload_groups,

    SUM(
        CASE WHEN inspection_rows <> join_ready_rows
             THEN 1 ELSE 0 END
    ) AS different_count_groups,

    SUM(
        CASE
            WHEN inspection_rows > join_ready_rows
            THEN inspection_rows - join_ready_rows
            ELSE 0
        END
    ) AS inspection_unmatched_rows,

    SUM(
        CASE
            WHEN join_ready_rows > inspection_rows
            THEN join_ready_rows - inspection_rows
            ELSE 0
        END
    ) AS join_ready_unmatched_rows

FROM payload_counts;


-- 작업 58-6: 차이가 있는 비교 그룹 확인
-- 일치하면 결과 행 없이 컬럼만 표시됨

WITH payload_counts AS (
    SELECT
        payload_sha256,

        SUM(
            CASE WHEN source_name = 'INSPECTION'
                 THEN 1 ELSE 0 END
        ) AS inspection_rows,

        SUM(
            CASE WHEN source_name = 'JOIN_READY'
                 THEN 1 ELSE 0 END
        ) AS join_ready_rows

    FROM kream_project_repro.asis_raw_payload_signature_v1
    GROUP BY payload_sha256
)
SELECT
    payload_sha256,
    inspection_rows,
    join_ready_rows
FROM payload_counts
WHERE inspection_rows <> join_ready_rows
ORDER BY
    ABS(inspection_rows - join_ready_rows) DESC,
    payload_sha256
LIMIT 20;