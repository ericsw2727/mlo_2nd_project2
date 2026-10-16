-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 원문 보완용 복원본. 현재 kream_project_repro에서 다시 실행하지 않음.
-- 기존 업무 규칙과 분류는 변경하지 않음.
-- 별도 재현 스키마용 복제본은 repro_sql 폴더에 제공.
-- 작업 79 복원: 실제 내보내기 대상과 기준 건수
CREATE TABLE kream_project_repro.documentation_export_manifest_v1 (
    export_order INT UNSIGNED NOT NULL,
    table_name VARCHAR(64) NOT NULL,
    output_file_name VARCHAR(128) NOT NULL,
    table_role VARCHAR(32) NOT NULL,
    actual_rows BIGINT UNSIGNED NOT NULL,
    expected_rows BIGINT UNSIGNED NOT NULL,
    column_count INT UNSIGNED NOT NULL,
    row_count_status VARCHAR(16) NOT NULL,
    export_version VARCHAR(32) NOT NULL,
    captured_at_kst DATETIME NOT NULL,
    PRIMARY KEY (table_name),
    UNIQUE KEY uq_export_manifest_file (output_file_name),
    UNIQUE KEY uq_export_manifest_order (export_order)
)
ENGINE = InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_bin;

INSERT INTO kream_project_repro.documentation_export_manifest_v1 (
    export_order, table_name, output_file_name, table_role,
    actual_rows, expected_rows, column_count, row_count_status,
    export_version, captured_at_kst
)
SELECT
    ROW_NUMBER() OVER (ORDER BY a.table_name),
    a.table_name,
    CONCAT('kream_repro_', a.table_name, '.csv'),
    p.table_role,
    a.actual_rows,
    a.expected_rows,
    (SELECT COUNT(*) FROM information_schema.COLUMNS AS c
     WHERE c.TABLE_SCHEMA = 'kream_project_repro' AND c.TABLE_NAME = a.table_name),
    CASE WHEN a.actual_rows = a.expected_rows THEN 'MATCH' ELSE 'DIFFERENT' END,
    '20261015_export_v1',
    DATE_ADD(UTC_TIMESTAMP(), INTERVAL 9 HOUR)
FROM (
SELECT 'asis_inspection_join_row_pair_v1' AS table_name, COUNT(*) AS actual_rows, 335000 AS expected_rows FROM kream_project_repro.asis_inspection_join_row_pair_v1
UNION ALL
SELECT 'asis_join_ready_disposition_snapshot_v1' AS table_name, COUNT(*) AS actual_rows, 335000 AS expected_rows FROM kream_project_repro.asis_join_ready_disposition_snapshot_v1
UNION ALL
SELECT 'data_quality_check_results_v1' AS table_name, COUNT(*) AS actual_rows, 16 AS expected_rows FROM kream_project_repro.data_quality_check_results_v1
UNION ALL
SELECT 'excluded_category_parent_lookup' AS table_name, COUNT(*) AS actual_rows, 50 AS expected_rows FROM kream_project_repro.excluded_category_parent_lookup
UNION ALL
SELECT 'excluded_inspection' AS table_name, COUNT(*) AS actual_rows, 29359 AS expected_rows FROM kream_project_repro.excluded_inspection
UNION ALL
SELECT 'excluded_inspector_master' AS table_name, COUNT(*) AS actual_rows, 147 AS expected_rows FROM kream_project_repro.excluded_inspector_master
UNION ALL
SELECT 'gold_department_risk_summary_v1' AS table_name, COUNT(*) AS actual_rows, 8 AS expected_rows FROM kream_project_repro.gold_department_risk_summary_v1
UNION ALL
SELECT 'gold_inspection_result_daily_v1' AS table_name, COUNT(*) AS actual_rows, 1729 AS expected_rows FROM kream_project_repro.gold_inspection_result_daily_v1
UNION ALL
SELECT 'gold_inspection_workload_daily_v1' AS table_name, COUNT(*) AS actual_rows, 1729 AS expected_rows FROM kream_project_repro.gold_inspection_workload_daily_v1
UNION ALL
SELECT 'gold_inspection_workload_hourly_v1' AS table_name, COUNT(*) AS actual_rows, 167859 AS expected_rows FROM kream_project_repro.gold_inspection_workload_hourly_v1
UNION ALL
SELECT 'gold_prediction_actual_daily_v1' AS table_name, COUNT(*) AS actual_rows, 7 AS expected_rows FROM kream_project_repro.gold_prediction_actual_daily_v1
UNION ALL
SELECT 'gold_prediction_input_daily_v1' AS table_name, COUNT(*) AS actual_rows, 28 AS expected_rows FROM kream_project_repro.gold_prediction_input_daily_v1
UNION ALL
SELECT 'gold_prediction_input_record_v1' AS table_name, COUNT(*) AS actual_rows, 8173 AS expected_rows FROM kream_project_repro.gold_prediction_input_record_v1
UNION ALL
SELECT 'gold_product_risk_summary_v1' AS table_name, COUNT(*) AS actual_rows, 20 AS expected_rows FROM kream_project_repro.gold_product_risk_summary_v1
UNION ALL
SELECT 'gold_risk_cross_summary_v1' AS table_name, COUNT(*) AS actual_rows, 604 AS expected_rows FROM kream_project_repro.gold_risk_cross_summary_v1
UNION ALL
SELECT 'gold_staffing_scenario_v1' AS table_name, COUNT(*) AS actual_rows, 42 AS expected_rows FROM kream_project_repro.gold_staffing_scenario_v1
UNION ALL
SELECT 'gold_workload_forecast_evaluation_v1' AS table_name, COUNT(*) AS actual_rows, 14 AS expected_rows FROM kream_project_repro.gold_workload_forecast_evaluation_v1
UNION ALL
SELECT 'gold_workload_forecast_summary_v1' AS table_name, COUNT(*) AS actual_rows, 2 AS expected_rows FROM kream_project_repro.gold_workload_forecast_summary_v1
UNION ALL
SELECT 'gold_workload_forecast_v1' AS table_name, COUNT(*) AS actual_rows, 14 AS expected_rows FROM kream_project_repro.gold_workload_forecast_v1
UNION ALL
SELECT 'quarantine_category_parent_lookup' AS table_name, COUNT(*) AS actual_rows, 30 AS expected_rows FROM kream_project_repro.quarantine_category_parent_lookup
UNION ALL
SELECT 'quarantine_inspection' AS table_name, COUNT(*) AS actual_rows, 33854 AS expected_rows FROM kream_project_repro.quarantine_inspection
UNION ALL
SELECT 'quarantine_inspector_master' AS table_name, COUNT(*) AS actual_rows, 43 AS expected_rows FROM kream_project_repro.quarantine_inspector_master
UNION ALL
SELECT 'silver_category_parent_lookup' AS table_name, COUNT(*) AS actual_rows, 970 AS expected_rows FROM kream_project_repro.silver_category_parent_lookup
UNION ALL
SELECT 'silver_inspection' AS table_name, COUNT(*) AS actual_rows, 271787 AS expected_rows FROM kream_project_repro.silver_inspection
UNION ALL
SELECT 'silver_inspection_correction_log' AS table_name, COUNT(*) AS actual_rows, 880611 AS expected_rows FROM kream_project_repro.silver_inspection_correction_log
UNION ALL
SELECT 'silver_inspection_join_ready' AS table_name, COUNT(*) AS actual_rows, 271787 AS expected_rows FROM kream_project_repro.silver_inspection_join_ready
UNION ALL
SELECT 'silver_inspector_master' AS table_name, COUNT(*) AS actual_rows, 2960 AS expected_rows FROM kream_project_repro.silver_inspector_master
UNION ALL
SELECT 'silver_product_std_dict' AS table_name, COUNT(*) AS actual_rows, 32 AS expected_rows FROM kream_project_repro.silver_product_std_dict
) AS a
JOIN kream_project_repro.documentation_table_catalog_v1 AS p
  ON p.table_name = a.table_name;

SELECT COUNT(*) AS export_table_count,
       SUM(row_count_status = 'MATCH') AS matched_table_count,
       SUM(row_count_status = 'DIFFERENT') AS different_table_count,
       SUM(column_count) AS total_column_count
FROM kream_project_repro.documentation_export_manifest_v1;

SELECT * FROM kream_project_repro.documentation_export_manifest_v1
ORDER BY export_order;
