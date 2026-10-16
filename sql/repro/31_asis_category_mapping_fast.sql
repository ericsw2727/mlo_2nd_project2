-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 31-1: 확인된 상품명 매핑을 검사 전용 테이블에 저장
-- TEXT로 원문을 보존하고, 검색용 접두 인덱스 사용
-- 인덱스는 검색을 돕고 실제 비교는 전체 문자열로 수행
-- Bronze 원본 변경 없음

CREATE TABLE kream_project_repro.asis_product_name_evidence_v1 (
    evidence_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    raw_item_code TEXT NOT NULL,
    raw_item_name TEXT NOT NULL,
    standard_item_name VARCHAR(150) NOT NULL,
    name_check_status VARCHAR(40) NOT NULL,
    source_rows BIGINT UNSIGNED NOT NULL,

    PRIMARY KEY (evidence_id),

    INDEX ix_product_name (
        raw_item_code(50),
        raw_item_name(150)
    )
)
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin;


INSERT INTO kream_project_repro.asis_product_name_evidence_v1 (
    raw_item_code,
    raw_item_name,
    standard_item_name,
    name_check_status,
    source_rows
)
SELECT
    raw_item_code,
    raw_item_name,
    code_standard_name,
    name_check_status,
    source_rows
FROM kream_project_repro.asis_product_name_mapping_check_v1
WHERE name_check_status IN (
    'STANDARD_NAME',
    'STANDARD_NAME_SPELLING_VARIANT',
    'REGISTERED_ALIAS'
);

SHOW WARNINGS;


SELECT
    name_check_status,
    COUNT(*) AS name_groups,
    SUM(source_rows) AS source_rows
FROM kream_project_repro.asis_product_name_evidence_v1
GROUP BY name_check_status
ORDER BY name_check_status;


-- 작업 31-2: 저장된 상품명 근거 검증

SELECT
    name_check_status,
    COUNT(*) AS name_groups,
    SUM(source_rows) AS source_rows
FROM kream_project_repro.asis_product_name_evidence_v1
GROUP BY name_check_status
ORDER BY name_check_status;


-- 작업 31-3: 동일 코드·원문 이름의 중복 저장 검사
-- 결과가 0행이어야 다음 조회의 행 증식이 없음

SELECT
    HEX(raw_item_code) AS raw_code_hex,
    HEX(raw_item_name) AS raw_name_hex,
    COUNT(*) AS duplicate_rows
FROM kream_project_repro.asis_product_name_evidence_v1
GROUP BY HEX(raw_item_code), HEX(raw_item_name)
HAVING COUNT(*) > 1;

SELECT COUNT(*) AS duplicate_name_groups
FROM (
    SELECT
        HEX(raw_item_code),
        HEX(raw_item_name)
    FROM kream_project_repro.asis_product_name_evidence_v1
    GROUP BY HEX(raw_item_code), HEX(raw_item_name)
    HAVING COUNT(*) > 1
) AS duplicates;


-- 작업 31-4: 저장된 상품명 근거로 카테고리 후보 조사
-- 기존 30-4와 같은 조건 유지
-- 상품명 검사 뷰 대신 인덱스가 있는 저장 테이블 사용
-- 실제 부모 카테고리 복구는 수행하지 않음

WITH eligible_categories AS (
    SELECT
        b.ITEM_STD_CODE,
        d.STD_KOR_NM AS standard_item_name,
        p.proposed_id AS category_id

    FROM kream_project_repro.bronze_inspection AS b

    JOIN kream_project_repro.asis_product_name_evidence_v1 AS nm
      ON nm.raw_item_code = b.ITEM_STD_CODE
     AND nm.raw_item_name = b.ITEM_NM

    JOIN kream_project_repro.bronze_product_std_dict AS d
      ON d.CODE_TYPE = 'ITEM_MODEL'
     AND d.BANNED_WORD_YN = 'N'
     AND d.STD_CODE = b.ITEM_STD_CODE

    JOIN kream_project_repro.asis_reference_id_snapshot_v1 AS p
      ON p.source_name = 'INSPECTION'
     AND p.column_name = 'PARENT_CAT_ID'
     AND p.bronze_row_id = b.bronze_row_id
     AND p.proposed_id IS NOT NULL

    JOIN kream_project_repro.asis_master_key_snapshot_v1 AS cm
      ON cm.source_name = 'CATEGORY_MASTER'
     AND cm.normalized_id = p.proposed_id
     AND cm.raw_payload_versions = 1
),
category_summary AS (
    SELECT
        ITEM_STD_CODE,
        standard_item_name,
        COUNT(*) AS evidence_rows,
        COUNT(DISTINCT category_id) AS category_count,
        MIN(category_id) AS first_category_id,
        MAX(category_id) AS last_category_id
    FROM eligible_categories
    GROUP BY ITEM_STD_CODE, standard_item_name
)
SELECT
    d.STD_CODE AS item_std_code,
    d.STD_KOR_NM AS standard_item_name,
    COALESCE(s.evidence_rows, 0) AS evidence_rows,
    COALESCE(s.category_count, 0) AS category_count,

    CASE
        WHEN s.category_count = 1
        THEN s.first_category_id
        ELSE NULL
    END AS proposed_category_id,

    CASE
        WHEN s.category_count IS NULL
        THEN 'NO_EVIDENCE'
        WHEN s.category_count = 1
        THEN 'SINGLE_CATEGORY_CANDIDATE'
        ELSE 'MULTIPLE_CATEGORIES_REVIEW'
    END AS mapping_status,

    s.first_category_id,
    s.last_category_id

FROM kream_project_repro.bronze_product_std_dict AS d
LEFT JOIN category_summary AS s
  ON s.ITEM_STD_CODE = d.STD_CODE
WHERE d.CODE_TYPE = 'ITEM_MODEL'
ORDER BY d.STD_CODE;