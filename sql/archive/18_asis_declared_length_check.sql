-- 작업 18-1: 명세서에 길이가 명시된 문자열 컬럼 검사
-- CHAR_LENGTH로 문자 수를 계산
-- 원본 길이 초과를 조사하며 원본 수정·격리는 하지 않음
-- 표준화 후 길이 검사는 이후 별도로 수행

WITH column_values AS (
    SELECT
        'INSPECTOR_MASTER' AS table_name,
        'EMP_NO' AS column_name,
        20 AS allowed_length,
        bronze_row_id,
        EMP_NO AS raw_value
    FROM kream_project.bronze_inspector_master

    UNION ALL
    SELECT 'INSPECTOR_MASTER', 'EMP_NM', 50,
           bronze_row_id, EMP_NM
    FROM kream_project.bronze_inspector_master

    UNION ALL
    SELECT 'INSPECTOR_MASTER', 'DEPT_NM', 100,
           bronze_row_id, DEPT_NM
    FROM kream_project.bronze_inspector_master

    UNION ALL
    SELECT 'INSPECTOR_MASTER', 'POSITION_NM', 50,
           bronze_row_id, POSITION_NM
    FROM kream_project.bronze_inspector_master

    UNION ALL
    SELECT 'INSPECTOR_MASTER', 'ACTIVE_YN', 1,
           bronze_row_id, ACTIVE_YN
    FROM kream_project.bronze_inspector_master

    UNION ALL
    SELECT 'CATEGORY_LOOKUP', 'CAT_ID', 20,
           bronze_row_id, CAT_ID
    FROM kream_project.bronze_category_parent_lookup

    UNION ALL
    SELECT 'CATEGORY_LOOKUP', 'CAT_NM', 100,
           bronze_row_id, CAT_NM
    FROM kream_project.bronze_category_parent_lookup

    UNION ALL
    SELECT 'CATEGORY_LOOKUP', 'CAT_LEVEL', 20,
           bronze_row_id, CAT_LEVEL
    FROM kream_project.bronze_category_parent_lookup

    UNION ALL
    SELECT 'PRODUCT_STD_DICT', 'DICT_ID', 20,
           bronze_row_id, DICT_ID
    FROM kream_project.bronze_product_std_dict

    UNION ALL
    SELECT 'PRODUCT_STD_DICT', 'CODE_TYPE', 20,
           bronze_row_id, CODE_TYPE
    FROM kream_project.bronze_product_std_dict

    UNION ALL
    SELECT 'PRODUCT_STD_DICT', 'STD_CODE', 50,
           bronze_row_id, STD_CODE
    FROM kream_project.bronze_product_std_dict

    UNION ALL
    SELECT 'PRODUCT_STD_DICT', 'STD_KOR_NM', 150,
           bronze_row_id, STD_KOR_NM
    FROM kream_project.bronze_product_std_dict

    UNION ALL
    SELECT 'PRODUCT_STD_DICT', 'SYNONYM_LIST', 1000,
           bronze_row_id, SYNONYM_LIST
    FROM kream_project.bronze_product_std_dict

    UNION ALL
    SELECT 'PRODUCT_STD_DICT', 'BANNED_WORD_YN', 1,
           bronze_row_id, BANNED_WORD_YN
    FROM kream_project.bronze_product_std_dict
)
SELECT
    table_name,
    column_name,
    allowed_length,
    COUNT(*) AS inspected_rows,
    MAX(CHAR_LENGTH(raw_value)) AS max_raw_length,
    SUM(
        CASE WHEN CHAR_LENGTH(raw_value) > allowed_length
             THEN 1 ELSE 0 END
    ) AS raw_length_exceeded_rows,
    MIN(
        CASE WHEN CHAR_LENGTH(raw_value) > allowed_length
             THEN bronze_row_id ELSE NULL END
    ) AS first_exceeded_row_id
FROM column_values
GROUP BY table_name, column_name, allowed_length
ORDER BY table_name, column_name;