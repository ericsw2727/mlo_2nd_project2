-- 작업 30-1: 상품명 내부의 금칙 표현 검사 뷰
-- 금칙 사전에 실제 등록된 표준명·동의어만 사용
-- 동물명·인물명이라는 이유만으로 금칙어로 판단하지 않음
-- 부분 일치는 먼저 검토 대상으로 분류

CREATE OR REPLACE VIEW
    kream_project.asis_product_name_banned_check_v1 AS

WITH banned_terms AS (
    SELECT
        DICT_ID,
        STD_CODE,
        LOWER(TRIM(STD_KOR_NM)) AS term_for_check
    FROM kream_project.bronze_product_std_dict
    WHERE CODE_TYPE = 'BANNED_WORD'
      AND BANNED_WORD_YN = 'Y'

    UNION ALL

    SELECT
        d.DICT_ID,
        d.STD_CODE,
        LOWER(TRIM(j.alias_term))
    FROM kream_project.bronze_product_std_dict AS d
    CROSS JOIN JSON_TABLE(
        CONCAT(
            '[',
            REPLACE(
                JSON_QUOTE(COALESCE(d.SYNONYM_LIST, '')),
                ',',
                '","'
            ),
            ']'
        ),
        '$[*]' COLUMNS (
            alias_term VARCHAR(1000) PATH '$'
        )
    ) AS j
    WHERE d.CODE_TYPE = 'BANNED_WORD'
      AND d.BANNED_WORD_YN = 'Y'
      AND TRIM(j.alias_term) <> ''
)
SELECT
    n.raw_item_code,
    n.raw_item_name,
    n.raw_code_hex,
    n.raw_name_hex,
    n.source_rows,
    n.name_check_status,

    CASE
        WHEN n.name_check_status = 'BANNED_PRODUCT_CODE'
        THEN 'BANNED_PRODUCT_CODE'

        WHEN EXISTS (
            SELECT 1
            FROM banned_terms AS t
            WHERE t.term_for_check <> ''
              AND LOCATE(
                  t.term_for_check,
                  LOWER(TRIM(n.raw_item_name))
              ) > 0
        )
        THEN 'BANNED_TERM_CONTAINED_REVIEW'

        ELSE 'NO_REGISTERED_BANNED_TERM_FOUND'
    END AS banned_check_status,

    (
        SELECT GROUP_CONCAT(
            DISTINCT CONCAT(t.DICT_ID, ':', t.term_for_check)
            ORDER BY CONCAT(t.DICT_ID, ':', t.term_for_check)
            SEPARATOR ' | '
        )
        FROM banned_terms AS t
        WHERE t.term_for_check <> ''
          AND LOCATE(
              t.term_for_check,
              LOWER(TRIM(n.raw_item_name))
          ) > 0
    ) AS matched_terms

FROM kream_project.asis_product_name_mapping_check_v1 AS n;




-- 작업 30-2: 금칙 표현 검사 결과 집계
-- source_rows 합계는 335,000이어야 함
-- 코드 금칙과 이름 부분 일치를 서로 겹치지 않게 분류

SELECT
    banned_check_status,
    COUNT(*) AS name_groups,
    SUM(source_rows) AS source_rows
FROM kream_project.asis_product_name_banned_check_v1
GROUP BY banned_check_status
ORDER BY banned_check_status;


-- 작업 30-3: 정상 상품 코드에서 발견된 금칙 표현 샘플
-- 부분 일치만으로 격리를 확정하지 않고 근거 확인
-- 최대 30개 상품명 유형 조회

SELECT
    raw_item_code,
    raw_item_name,
    name_check_status,
    matched_terms,
    source_rows
FROM kream_project.asis_product_name_banned_check_v1
WHERE banned_check_status = 'BANNED_TERM_CONTAINED_REVIEW'
ORDER BY source_rows DESC, raw_code_hex, raw_name_hex
LIMIT 30;


-- 작업 30-4: 상품별 부모 카테고리 복구 후보 조사
-- 근거로 사용할 행의 조건:
-- 1. 상품 코드가 ITEM_MODEL 사전에 존재
-- 2. 상품명이 해당 상품의 표준명 또는 등록 동의어로 확인됨
-- 3. 부모 카테고리 후보가 마스터에 실제 존재
-- 4. 해당 마스터 키에 원본 내용 충돌이 없음
--
-- 하나의 표준 상품에서 카테고리가 한 가지일 때만
-- 복구 후보를 제시
-- 실제 결측 복구는 수행하지 않음

WITH eligible_categories AS (
    SELECT
        b.ITEM_STD_CODE,
        d.STD_KOR_NM AS standard_item_name,
        p.proposed_id AS category_id

    FROM kream_project.bronze_inspection AS b

    JOIN kream_project.bronze_product_std_dict AS d
      ON d.CODE_TYPE = 'ITEM_MODEL'
     AND d.BANNED_WORD_YN = 'N'
     AND d.STD_CODE = b.ITEM_STD_CODE

    JOIN kream_project.asis_product_name_mapping_check_v1 AS nm
      ON nm.raw_code_hex = HEX(b.ITEM_STD_CODE)
     AND nm.raw_name_hex = HEX(b.ITEM_NM)
     AND nm.name_check_status IN (
         'STANDARD_NAME',
         'STANDARD_NAME_SPELLING_VARIANT',
         'REGISTERED_ALIAS'
     )

    JOIN kream_project.asis_reference_id_snapshot_v1 AS p
      ON p.source_name = 'INSPECTION'
     AND p.column_name = 'PARENT_CAT_ID'
     AND p.bronze_row_id = b.bronze_row_id
     AND p.proposed_id IS NOT NULL

    JOIN kream_project.asis_master_key_snapshot_v1 AS cm
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

FROM kream_project.bronze_product_std_dict AS d
LEFT JOIN category_summary AS s
  ON s.ITEM_STD_CODE = d.STD_CODE
WHERE d.CODE_TYPE = 'ITEM_MODEL'
ORDER BY d.STD_CODE;