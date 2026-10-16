-- 작업 76-1: 프로젝트 전체 테이블과 뷰 목록
-- TABLE_ROWS는 추정치이므로 최종 건수 검증에 사용하지 않음

SELECT
    TABLE_NAME,
    TABLE_TYPE,
    ENGINE,
    TABLE_COLLATION
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'kream_project'
ORDER BY TABLE_NAME;


-- 작업 76-2: 주요 결과 테이블 존재 여부
-- 예상 목록과 실제 DB를 대조

WITH expected_tables AS (
    SELECT 'silver_product_std_dict' AS table_name
    UNION ALL SELECT 'silver_inspector_master'
    UNION ALL SELECT 'silver_category_parent_lookup'
    UNION ALL SELECT 'silver_inspection'
    UNION ALL SELECT 'silver_inspection_join_ready'

    UNION ALL SELECT 'quarantine_inspector_master'
    UNION ALL SELECT 'quarantine_category_parent_lookup'
    UNION ALL SELECT 'quarantine_inspection'

    UNION ALL SELECT 'excluded_inspector_master'
    UNION ALL SELECT 'excluded_category_parent_lookup'
    UNION ALL SELECT 'excluded_inspection'

    UNION ALL SELECT 'silver_inspection_correction_log'
    UNION ALL SELECT 'asis_inspection_join_row_pair_v1'
    UNION ALL SELECT 'asis_join_ready_disposition_snapshot_v1'
    UNION ALL SELECT 'data_quality_check_results_v1'

    UNION ALL SELECT 'gold_inspection_result_daily_v1'
    UNION ALL SELECT 'gold_inspection_workload_daily_v1'
    UNION ALL SELECT 'gold_inspection_workload_hourly_v1'
    UNION ALL SELECT 'gold_product_risk_summary_v1'
    UNION ALL SELECT 'gold_department_risk_summary_v1'
    UNION ALL SELECT 'gold_risk_cross_summary_v1'

    UNION ALL SELECT 'gold_prediction_input_record_v1'
    UNION ALL SELECT 'gold_prediction_input_daily_v1'
    UNION ALL SELECT 'gold_workload_forecast_v1'
    UNION ALL SELECT 'gold_prediction_actual_daily_v1'
    UNION ALL SELECT 'gold_workload_forecast_evaluation_v1'
    UNION ALL SELECT 'gold_workload_forecast_summary_v1'
    UNION ALL SELECT 'gold_staffing_scenario_v1'
)
SELECT
    e.table_name,
    t.TABLE_TYPE,
    CASE
        WHEN t.TABLE_NAME IS NULL THEN 'MISSING'
        ELSE 'FOUND'
    END AS existence_status
FROM expected_tables AS e
LEFT JOIN information_schema.TABLES AS t
  ON t.TABLE_SCHEMA = 'kream_project'
 AND t.TABLE_NAME = e.table_name
ORDER BY e.table_name;


-- 작업 76-3: Silver 컬럼과 자료형
-- COLUMN_KEY는 간단한 표시이며 복합 키 전체는 76-5에서 확인

SELECT
    TABLE_NAME,
    ORDINAL_POSITION,
    COLUMN_NAME,
    COLUMN_TYPE,
    IS_NULLABLE,
    COLUMN_DEFAULT,
    COLUMN_KEY,
    COLLATION_NAME,
    EXTRA
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = 'kream_project'
  AND TABLE_NAME IN (
      'silver_product_std_dict',
      'silver_inspector_master',
      'silver_category_parent_lookup',
      'silver_inspection',
      'silver_inspection_join_ready'
  )
ORDER BY
    TABLE_NAME,
    ORDINAL_POSITION;


-- 작업 76-4: Gold 컬럼과 자료형

SELECT
    TABLE_NAME,
    ORDINAL_POSITION,
    COLUMN_NAME,
    COLUMN_TYPE,
    IS_NULLABLE,
    COLUMN_DEFAULT,
    COLUMN_KEY,
    COLLATION_NAME,
    EXTRA
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = 'kream_project'
  AND LEFT(TABLE_NAME, 5) = 'gold_'
ORDER BY
    TABLE_NAME,
    ORDINAL_POSITION;


-- 작업 76-5: 실제 기본키와 고유키 구성
-- 복합 키의 컬럼 순서까지 확인

SELECT
    t.TABLE_NAME,
    t.CONSTRAINT_NAME,
    t.CONSTRAINT_TYPE,
    k.ORDINAL_POSITION,
    k.COLUMN_NAME
FROM information_schema.TABLE_CONSTRAINTS AS t
JOIN information_schema.KEY_COLUMN_USAGE AS k
  ON k.CONSTRAINT_SCHEMA = t.CONSTRAINT_SCHEMA
 AND k.TABLE_NAME = t.TABLE_NAME
 AND k.CONSTRAINT_NAME = t.CONSTRAINT_NAME
WHERE t.TABLE_SCHEMA = 'kream_project'
  AND t.CONSTRAINT_TYPE IN (
      'PRIMARY KEY',
      'UNIQUE'
  )
ORDER BY
    t.TABLE_NAME,
    t.CONSTRAINT_TYPE,
    t.CONSTRAINT_NAME,
    k.ORDINAL_POSITION;


-- 작업 76-6: 실제 외래키 관계와 CHECK 조건

-- 결과 6: 실제 외래키 관계

SELECT
    k.TABLE_NAME AS child_table,
    k.CONSTRAINT_NAME,
    k.ORDINAL_POSITION,
    k.COLUMN_NAME AS child_column,
    k.REFERENCED_TABLE_NAME AS parent_table,
    k.REFERENCED_COLUMN_NAME AS parent_column,
    r.UPDATE_RULE,
    r.DELETE_RULE
FROM information_schema.KEY_COLUMN_USAGE AS k
JOIN information_schema.REFERENTIAL_CONSTRAINTS AS r
  ON r.CONSTRAINT_SCHEMA = k.CONSTRAINT_SCHEMA
 AND r.TABLE_NAME = k.TABLE_NAME
 AND r.CONSTRAINT_NAME = k.CONSTRAINT_NAME
WHERE k.TABLE_SCHEMA = 'kream_project'
  AND k.REFERENCED_TABLE_NAME IS NOT NULL
ORDER BY
    k.TABLE_NAME,
    k.CONSTRAINT_NAME,
    k.ORDINAL_POSITION;


-- 결과 7: 실제 CHECK 조건

SELECT
    t.TABLE_NAME,
    t.CONSTRAINT_NAME,
    c.CHECK_CLAUSE,
    t.ENFORCED
FROM information_schema.TABLE_CONSTRAINTS AS t
JOIN information_schema.CHECK_CONSTRAINTS AS c
  ON c.CONSTRAINT_SCHEMA = t.CONSTRAINT_SCHEMA
 AND c.CONSTRAINT_NAME = t.CONSTRAINT_NAME
WHERE t.TABLE_SCHEMA = 'kream_project'
  AND t.CONSTRAINT_TYPE = 'CHECK'
ORDER BY
    t.TABLE_NAME,
    t.CONSTRAINT_NAME;