-- 작업 16-1: 실제 Bronze 컬럼 구조 확인
-- 목적: 명세의 49개 원본 컬럼과 관리 컬럼을 대조
-- 데이터·테이블 구조 변경 없음

SELECT
    TABLE_NAME,
    ORDINAL_POSITION,
    COLUMN_NAME,
    COLUMN_TYPE,
    IS_NULLABLE,
    COLUMN_DEFAULT,
    COLUMN_KEY,
    CHARACTER_SET_NAME,
    COLLATION_NAME,
    EXTRA
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = 'kream_project'
  AND TABLE_NAME IN (
      'bronze_inspector_master',
      'bronze_category_parent_lookup',
      'bronze_product_std_dict',
      'bronze_inspection',
      'bronze_inspection_join_ready'
  )
ORDER BY TABLE_NAME, ORDINAL_POSITION;