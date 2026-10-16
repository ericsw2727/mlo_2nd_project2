-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 32-1: 상품별 단일 카테고리 매핑 근거 저장
-- 31-4와 동일한 근거 조건 사용
-- 실제 검수 원본의 결측값은 변경하지 않음

CREATE TABLE kream_project_repro.asis_product_category_mapping_v1 (
    item_std_code VARCHAR(50) NOT NULL,
    standard_item_name VARCHAR(150) NOT NULL,
    proposed_category_id VARCHAR(20) NOT NULL,
    evidence_rows BIGINT UNSIGNED NOT NULL,

    PRIMARY KEY (item_std_code)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin;


INSERT INTO kream_project_repro.asis_product_category_mapping_v1 (
    item_std_code,
    standard_item_name,
    proposed_category_id,
    evidence_rows
)
SELECT
    b.ITEM_STD_CODE,
    d.STD_KOR_NM,
    MIN(p.proposed_id),
    COUNT(*)

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

GROUP BY b.ITEM_STD_CODE, d.STD_KOR_NM
HAVING COUNT(DISTINCT p.proposed_id) = 1;

SHOW WARNINGS;


-- 작업 32-2: 매핑 저장 건수 확인
-- 예상: 20행

SELECT COUNT(*) AS mapping_rows
FROM kream_project_repro.asis_product_category_mapping_v1;


-- 작업 32-3: 부모 카테고리 결측 행의 복구 가능 여부
-- 상품명 근거가 확인된 경우에만 복구 후보 제시
-- 금칙 상품은 복구 후보에서 제외
-- 원본 수정·실제 복구 없음

CREATE OR REPLACE VIEW
    kream_project_repro.asis_parent_category_recovery_check_v1 AS
SELECT
    b.bronze_row_id,
    b.INSP_ID,
    b.REV_NO,
    b.ITEM_STD_CODE,
    b.ITEM_NM,
    p.raw_value AS parent_category_raw,

    CASE
        WHEN d.CODE_TYPE = 'ITEM_MODEL'
         AND d.BANNED_WORD_YN = 'N'
         AND nm.evidence_id IS NOT NULL
         AND m.item_std_code IS NOT NULL
        THEN m.proposed_category_id
        ELSE NULL
    END AS proposed_category_id,

    CASE
        WHEN d.BANNED_WORD_YN = 'Y'
        THEN 'BANNED_PRODUCT'

        WHEN d.DICT_ID IS NULL
          OR d.CODE_TYPE <> 'ITEM_MODEL'
        THEN 'PRODUCT_CODE_REVIEW'

        WHEN nm.evidence_id IS NULL
        THEN 'PRODUCT_NAME_REVIEW'

        WHEN m.item_std_code IS NULL
        THEN 'NO_SINGLE_CATEGORY_MAPPING'

        WHEN d.BANNED_WORD_YN <> 'N'
          OR d.BANNED_WORD_YN IS NULL
        THEN 'DICTIONARY_FLAG_REVIEW'

        ELSE 'RECOVERABLE_CANDIDATE'
    END AS recovery_status

FROM kream_project_repro.asis_reference_id_snapshot_v1 AS p

JOIN kream_project_repro.bronze_inspection AS b
  ON b.bronze_row_id = p.bronze_row_id

LEFT JOIN kream_project_repro.bronze_product_std_dict AS d
  ON d.STD_CODE = b.ITEM_STD_CODE
 AND d.CODE_TYPE IN ('ITEM_MODEL', 'BANNED_WORD')

LEFT JOIN kream_project_repro.asis_product_name_evidence_v1 AS nm
  ON nm.raw_item_code = b.ITEM_STD_CODE
 AND nm.raw_item_name = b.ITEM_NM

LEFT JOIN kream_project_repro.asis_product_category_mapping_v1 AS m
  ON m.item_std_code = b.ITEM_STD_CODE

WHERE p.source_name = 'INSPECTION'
  AND p.column_name = 'PARENT_CAT_ID'
  AND p.normalization_status = 'MISSING_CANDIDATE';


-- 작업 32-4: 결측 행의 복구 후보 집계
-- row_count 합계는 1,000이어야 함

SELECT
    recovery_status,
    COUNT(*) AS row_count
FROM kream_project_repro.asis_parent_category_recovery_check_v1
GROUP BY recovery_status
ORDER BY recovery_status;


-- 작업 32-5: 상태별 샘플
-- 상태별 최대 3행

WITH samples AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY recovery_status
            ORDER BY bronze_row_id
        ) AS sample_no
    FROM kream_project_repro.asis_parent_category_recovery_check_v1
)
SELECT
    bronze_row_id,
    INSP_ID,
    REV_NO,
    ITEM_STD_CODE,
    ITEM_NM,
    parent_category_raw,
    proposed_category_id,
    recovery_status
FROM samples
WHERE sample_no <= 3
ORDER BY recovery_status, sample_no;



-- 작업 32-6: 카테고리 복구 후보 정합성 검증
-- 매핑 수, 후보 행 중복, 복구값 누락, 마스터 참조 검사
-- 실제 원본 수정 없음

SELECT
    (
        SELECT COUNT(*)
        FROM kream_project_repro.asis_product_category_mapping_v1
    ) AS mapping_rows,

    COUNT(*) AS candidate_rows,

    COUNT(DISTINCT r.bronze_row_id)
        AS distinct_source_rows,

    SUM(
        CASE WHEN r.proposed_category_id IS NULL
             THEN 1 ELSE 0 END
    ) AS missing_proposed_category_rows,

    SUM(
        CASE WHEN cm.normalized_id IS NULL
             THEN 1 ELSE 0 END
    ) AS proposed_category_not_found_rows

FROM kream_project_repro.asis_parent_category_recovery_check_v1 AS r

LEFT JOIN kream_project_repro.asis_master_key_snapshot_v1 AS cm
  ON cm.source_name = 'CATEGORY_MASTER'
 AND cm.normalized_id = r.proposed_category_id

WHERE r.recovery_status = 'RECOVERABLE_CANDIDATE';