-- 작업 26-1: ID 보정 결과를 검사 전용 테이블에 저장
-- 기존 23번과 동일한 보정 후보를 사용
-- 검수 INSP_ID는 이번 참조 검사에 필요하지 않으므로 저장하지 않음
-- Bronze 원본은 변경하지 않음

CREATE TABLE kream_project.asis_reference_id_snapshot_v1 (
    source_name VARCHAR(32) NOT NULL,
    column_name VARCHAR(32) NOT NULL,
    bronze_row_id BIGINT UNSIGNED NOT NULL,
    raw_value TEXT,
    proposed_id VARCHAR(20),
    normalization_status VARCHAR(32) NOT NULL,

    PRIMARY KEY (source_name, column_name, bronze_row_id),

    INDEX ix_reference_candidate (
        source_name,
        column_name,
        proposed_id
    )
)
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin;


INSERT INTO kream_project.asis_reference_id_snapshot_v1 (
    source_name,
    column_name,
    bronze_row_id,
    raw_value,
    proposed_id,
    normalization_status
)
SELECT
    source_name,
    column_name,
    bronze_row_id,
    raw_value,
    proposed_id,
    normalization_status
FROM kream_project.asis_identifier_normalization_v1
WHERE source_name IN (
    'CATEGORY_MASTER',
    'INSPECTOR_MASTER'
)
   OR (
       source_name = 'INSPECTION'
       AND column_name IN (
           'INSPECTOR_EMP_NO',
           'PARENT_CAT_ID'
       )
   );

-- INSERT 직후 적재 경고 확인
SHOW WARNINGS;


-- 작업 26-2: 저장 건수 확인
SELECT
    source_name,
    column_name,
    COUNT(*) AS snapshot_rows
FROM kream_project.asis_reference_id_snapshot_v1
GROUP BY source_name, column_name
ORDER BY source_name, column_name;


-- 작업 26-3: 마스터 키별 집계 결과 저장
-- 24번과 동일하게 원본 ID 표기와 나머지 내용의 차이를 계산
-- 기본키 인덱스로 검수 참조 조회에 사용

CREATE TABLE kream_project.asis_master_key_snapshot_v1 (
    source_name VARCHAR(32) NOT NULL,
    normalized_id VARCHAR(20) NOT NULL,
    rows_per_key BIGINT UNSIGNED NOT NULL,
    raw_id_versions BIGINT UNSIGNED NOT NULL,
    raw_payload_versions BIGINT UNSIGNED NOT NULL,

    PRIMARY KEY (source_name, normalized_id)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin;


INSERT INTO kream_project.asis_master_key_snapshot_v1 (
    source_name,
    normalized_id,
    rows_per_key,
    raw_id_versions,
    raw_payload_versions
)
SELECT
    'CATEGORY_MASTER',
    n.proposed_id,
    COUNT(*),
    COUNT(DISTINCT HEX(b.CAT_ID)),
    COUNT(DISTINCT
        COALESCE(HEX(b.CAT_NM), 'NULL'),
        COALESCE(HEX(b.CAT_LEVEL), 'NULL'),
        COALESCE(HEX(b.REG_DT), 'NULL')
    )
FROM kream_project.asis_reference_id_snapshot_v1 AS n
JOIN kream_project.bronze_category_parent_lookup AS b
  ON b.bronze_row_id = n.bronze_row_id
WHERE n.source_name = 'CATEGORY_MASTER'
  AND n.column_name = 'CAT_ID'
  AND n.proposed_id IS NOT NULL
GROUP BY n.proposed_id

UNION ALL

SELECT
    'INSPECTOR_MASTER',
    n.proposed_id,
    COUNT(*),
    COUNT(DISTINCT HEX(b.EMP_NO)),
    COUNT(DISTINCT
        COALESCE(HEX(b.EMP_NM), 'NULL'),
        COALESCE(HEX(b.DEPT_NM), 'NULL'),
        COALESCE(HEX(b.POSITION_NM), 'NULL'),
        COALESCE(HEX(b.HIRE_DT), 'NULL'),
        COALESCE(HEX(b.ACTIVE_YN), 'NULL')
    )
FROM kream_project.asis_reference_id_snapshot_v1 AS n
JOIN kream_project.bronze_inspector_master AS b
  ON b.bronze_row_id = n.bronze_row_id
WHERE n.source_name = 'INSPECTOR_MASTER'
  AND n.column_name = 'EMP_NO'
  AND n.proposed_id IS NOT NULL
GROUP BY n.proposed_id;

-- 기존 마스터 저장 상태 확인
SELECT
    source_name,
    COUNT(*) AS normalized_unique_ids,
    SUM(rows_per_key) AS inspected_rows
FROM kream_project.asis_master_key_snapshot_v1
GROUP BY source_name
ORDER BY source_name;

-- 작업 26-4: 저장된 마스터 키 집계 검증
-- 24번 검사 결과와 동일한지 확인

SELECT
    source_name,
    SUM(rows_per_key) AS inspected_rows,
    COUNT(*) AS normalized_unique_ids,
    SUM(
        CASE WHEN rows_per_key > 1
             THEN 1 ELSE 0 END
    ) AS repeated_key_groups,
    SUM(rows_per_key - 1) AS additional_rows,
    SUM(
        CASE WHEN raw_payload_versions > 1
             THEN 1 ELSE 0 END
    ) AS different_payload_groups,
    SUM(
        CASE WHEN raw_id_versions > 1
             THEN 1 ELSE 0 END
    ) AS multiple_raw_id_spellings_groups
FROM kream_project.asis_master_key_snapshot_v1
GROUP BY source_name
ORDER BY source_name;


-- 작업 26-5: 저장된 후보와 마스터로 참조 검사 뷰 생성
-- 문자열 보정과 마스터 집계를 다시 계산하지 않음
-- 인덱스가 있는 저장 테이블끼리 연결
-- Bronze 원본 수정 없음

CREATE OR REPLACE VIEW
    kream_project.asis_inspection_reference_check_fast_v1 AS
SELECT
    n.bronze_row_id,
    n.column_name,
    n.raw_value,
    n.proposed_id,
    n.normalization_status,
    m.normalized_id AS matched_master_id,

    CASE
        WHEN n.normalization_status = 'MISSING_CANDIDATE'
        THEN 'MISSING_REFERENCE'

        WHEN n.proposed_id IS NULL
        THEN 'UNRESOLVED_REFERENCE'

        WHEN m.normalized_id IS NULL
        THEN 'MASTER_KEY_NOT_FOUND'

        WHEN m.raw_payload_versions > 1
        THEN 'MASTER_PAYLOAD_REVIEW'

        ELSE 'MASTER_KEY_FOUND'
    END AS reference_status

FROM kream_project.asis_reference_id_snapshot_v1 AS n

LEFT JOIN kream_project.asis_master_key_snapshot_v1 AS m
  ON m.source_name =
        CASE n.column_name
            WHEN 'INSPECTOR_EMP_NO' THEN 'INSPECTOR_MASTER'
            WHEN 'PARENT_CAT_ID' THEN 'CATEGORY_MASTER'
        END
 AND m.normalized_id = n.proposed_id

WHERE n.source_name = 'INSPECTION'
  AND n.column_name IN (
      'INSPECTOR_EMP_NO',
      'PARENT_CAT_ID'
  );


-- 작업 26-6: 참조 검사 결과 집계
-- 각 컬럼의 row_count 합계는 335,000이어야 함

SELECT
    column_name,
    reference_status,
    COUNT(*) AS row_count
FROM kream_project.asis_inspection_reference_check_fast_v1
GROUP BY column_name, reference_status
ORDER BY column_name, reference_status;


-- 작업 26-7: 참조 문제 유형별 샘플
-- 컬럼·문제 유형별 최대 3행

WITH samples AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY column_name, reference_status
            ORDER BY bronze_row_id
        ) AS sample_no
    FROM kream_project.asis_inspection_reference_check_fast_v1
    WHERE reference_status <> 'MASTER_KEY_FOUND'
)
SELECT
    s.bronze_row_id,
    b.INSP_ID,
    b.REV_NO,
    s.column_name,
    s.raw_value,
    s.proposed_id,
    s.reference_status
FROM samples AS s
JOIN kream_project.bronze_inspection AS b
  ON b.bronze_row_id = s.bronze_row_id
WHERE s.sample_no <= 3
ORDER BY s.column_name, s.reference_status, s.sample_no;
