-- 작업 42-1: 표기 통일 후 허용 코드에 연결되지 않는 계층 값
-- 상품별 카테고리 매핑에 사용된 ID인지 함께 확인
-- 상품에서 사용됐다는 사실만으로 계층을 확정하지 않음
-- 원본 수정·코드 보정·격리 없음

WITH product_category_usage AS (
    SELECT
        proposed_category_id,
        COUNT(*) AS mapped_product_count
    FROM kream_project.asis_product_category_mapping_v1
    GROUP BY proposed_category_id
),
category_candidates AS (
    SELECT
        b.bronze_row_id,
        b.CAT_ID AS raw_cat_id,
        n.proposed_id AS normalized_cat_id,
        b.CAT_NM,
        b.CAT_LEVEL AS raw_cat_level,

        UPPER(
            REPLACE(TRIM(b.CAT_LEVEL), ' ', '_')
        ) AS level_spelling_candidate,

        b.REG_DT
    FROM kream_project.bronze_category_parent_lookup AS b

    JOIN kream_project.asis_reference_id_snapshot_v1 AS n
      ON n.source_name = 'CATEGORY_MASTER'
     AND n.column_name = 'CAT_ID'
     AND n.bronze_row_id = b.bronze_row_id
)
SELECT
    c.bronze_row_id,
    c.raw_cat_id,
    c.normalized_cat_id,
    c.CAT_NM,
    c.raw_cat_level,
    c.level_spelling_candidate,
    COALESCE(u.mapped_product_count, 0)
        AS mapped_product_count
FROM category_candidates AS c

LEFT JOIN product_category_usage AS u
  ON u.proposed_category_id = c.normalized_cat_id

WHERE c.level_spelling_candidate IS NULL
   OR c.level_spelling_candidate NOT IN (
       'TOP_LEVEL',
       'BRAND_LINE'
   )

ORDER BY c.raw_cat_level, c.bronze_row_id;