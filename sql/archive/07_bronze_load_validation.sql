-- 작업 07-1: 06번 파일 재실행 후 적재 상태 확인
-- 목적: CSV가 추가로 적재됐는지 건수로 확인
-- 데이터 변경 없이 조회만 수행

SELECT
    COUNT(*) AS loaded_rows,
    COUNT(DISTINCT INSP_ID) AS distinct_inspection_ids
FROM kream_project.bronze_inspection_join_ready;

-- 작업 07-2: 원본 CSV와 Bronze 전체 건수 대조
-- 목적: 5개 테이블의 적재 누락·추가 적재 여부를 건수로 확인
-- 근거: 원본 CSV에서 확인한 물리 행 수
-- 데이터 변경 없이 조회만 수행

WITH load_counts AS (
    SELECT
        'bronze_product_std_dict' AS table_name,
        32 AS expected_rows,
        COUNT(*) AS actual_rows
    FROM kream_project.bronze_product_std_dict

    UNION ALL

    SELECT
        'bronze_category_parent_lookup', 1050, COUNT(*)
    FROM kream_project.bronze_category_parent_lookup

    UNION ALL

    SELECT
        'bronze_inspector_master', 3150, COUNT(*)
    FROM kream_project.bronze_inspector_master

    UNION ALL

    SELECT
        'bronze_inspection', 335000, COUNT(*)
    FROM kream_project.bronze_inspection

    UNION ALL

    SELECT
        'bronze_inspection_join_ready', 335000, COUNT(*)
    FROM kream_project.bronze_inspection_join_ready
)
SELECT
    table_name,
    expected_rows,
    actual_rows,
    CAST(actual_rows AS SIGNED) - expected_rows AS row_difference,
    CASE
        WHEN actual_rows = expected_rows THEN 'PASS'
        ELSE 'CHECK'
    END AS validation_result
FROM load_counts
ORDER BY table_name;