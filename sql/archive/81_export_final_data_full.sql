-- 작업 81: 전체 행 저장을 명시한 내보내기 수정본
-- 파일: 81_export_final_data_full.sql
-- 앞선 파일에서 1001행 제한이 확인되어 모든 SELECT에 명시적 LIMIT 적용
-- 출력 이름은 kream_full_ 접두어로 기존 파일과 구분
-- 기존 데이터와 테이블은 변경하지 않음
-- 81-1만 먼저 실행하고 Output의 저장 행 수가 2960인지 확인
-- 2960행이 확인된 뒤 81-2부터 나머지를 실행
-- 이미 성공한 저장 문장은 다시 실행하지 않음
-- UTF-8, 헤더 없음, MySQL 역슬래시 이스케이프 형식, NULL은 \N

-- 작업 81-1: silver_inspector_master 전체 행 저장

SELECT *
FROM kream_project.`silver_inspector_master`
ORDER BY `EMP_NO`
LIMIT 18446744073709551615
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_full_silver_inspector_master.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 81-2: asis_inspection_join_row_pair_v1 전체 행 저장

SELECT *
FROM kream_project.`asis_inspection_join_row_pair_v1`
ORDER BY `inspection_bronze_row_id`
LIMIT 18446744073709551615
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_full_asis_inspection_join_row_pair_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 81-3: asis_join_ready_disposition_snapshot_v1 전체 행 저장

SELECT *
FROM kream_project.`asis_join_ready_disposition_snapshot_v1`
ORDER BY `join_ready_bronze_row_id`
LIMIT 18446744073709551615
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_full_asis_join_ready_disposition_snapshot_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 81-4: data_quality_check_results_v1 전체 행 저장

SELECT *
FROM kream_project.`data_quality_check_results_v1`
ORDER BY `check_id`
LIMIT 18446744073709551615
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_full_data_quality_check_results_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 81-5: excluded_category_parent_lookup 전체 행 저장

SELECT *
FROM kream_project.`excluded_category_parent_lookup`
ORDER BY `source_bronze_row_id`
LIMIT 18446744073709551615
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_full_excluded_category_parent_lookup.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 81-6: excluded_inspection 전체 행 저장

SELECT *
FROM kream_project.`excluded_inspection`
ORDER BY `bronze_row_id`
LIMIT 18446744073709551615
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_full_excluded_inspection.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 81-7: excluded_inspector_master 전체 행 저장

SELECT *
FROM kream_project.`excluded_inspector_master`
ORDER BY `source_bronze_row_id`
LIMIT 18446744073709551615
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_full_excluded_inspector_master.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 81-8: gold_department_risk_summary_v1 전체 행 저장

SELECT *
FROM kream_project.`gold_department_risk_summary_v1`
ORDER BY `department_name`
LIMIT 18446744073709551615
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_full_gold_department_risk_summary_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 81-9: gold_inspection_result_daily_v1 전체 행 저장

SELECT *
FROM kream_project.`gold_inspection_result_daily_v1`
ORDER BY `done_date_kst`
LIMIT 18446744073709551615
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_full_gold_inspection_result_daily_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 81-10: gold_inspection_workload_daily_v1 전체 행 저장

SELECT *
FROM kream_project.`gold_inspection_workload_daily_v1`
ORDER BY `done_date_kst`, `event_type`
LIMIT 18446744073709551615
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_full_gold_inspection_workload_daily_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 81-11: gold_inspection_workload_hourly_v1 전체 행 저장

SELECT *
FROM kream_project.`gold_inspection_workload_hourly_v1`
ORDER BY `done_date_kst`, `done_hour_kst`, `department_name`, `event_type`
LIMIT 18446744073709551615
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_full_gold_inspection_workload_hourly_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 81-12: gold_prediction_actual_daily_v1 전체 행 저장

SELECT *
FROM kream_project.`gold_prediction_actual_daily_v1`
ORDER BY `inspection_date`
LIMIT 18446744073709551615
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_full_gold_prediction_actual_daily_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 81-13: gold_prediction_input_daily_v1 전체 행 저장

SELECT *
FROM kream_project.`gold_prediction_input_daily_v1`
ORDER BY `inspection_date`
LIMIT 18446744073709551615
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_full_gold_prediction_input_daily_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 81-14: gold_prediction_input_record_v1 전체 행 저장

SELECT *
FROM kream_project.`gold_prediction_input_record_v1`
ORDER BY `source_bronze_row_id`
LIMIT 18446744073709551615
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_full_gold_prediction_input_record_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 81-15: gold_product_risk_summary_v1 전체 행 저장

SELECT *
FROM kream_project.`gold_product_risk_summary_v1`
ORDER BY `item_std_code`
LIMIT 18446744073709551615
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_full_gold_product_risk_summary_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 81-16: gold_risk_cross_summary_v1 전체 행 저장

SELECT *
FROM kream_project.`gold_risk_cross_summary_v1`
ORDER BY `item_std_code`, `department_name`, `final_revision_type`, `analysis_period`
LIMIT 18446744073709551615
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_full_gold_risk_cross_summary_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 81-17: gold_staffing_scenario_v1 전체 행 저장

SELECT *
FROM kream_project.`gold_staffing_scenario_v1`
ORDER BY `forecast_method`, `forecast_date`, `scenario_name`
LIMIT 18446744073709551615
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_full_gold_staffing_scenario_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 81-18: gold_workload_forecast_evaluation_v1 전체 행 저장

SELECT *
FROM kream_project.`gold_workload_forecast_evaluation_v1`
ORDER BY `forecast_method`, `forecast_date`
LIMIT 18446744073709551615
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_full_gold_workload_forecast_evaluation_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 81-19: gold_workload_forecast_summary_v1 전체 행 저장

SELECT *
FROM kream_project.`gold_workload_forecast_summary_v1`
ORDER BY `forecast_method`
LIMIT 18446744073709551615
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_full_gold_workload_forecast_summary_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 81-20: gold_workload_forecast_v1 전체 행 저장

SELECT *
FROM kream_project.`gold_workload_forecast_v1`
ORDER BY `forecast_method`, `forecast_date`
LIMIT 18446744073709551615
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_full_gold_workload_forecast_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 81-21: quarantine_category_parent_lookup 전체 행 저장

SELECT *
FROM kream_project.`quarantine_category_parent_lookup`
ORDER BY `source_bronze_row_id`
LIMIT 18446744073709551615
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_full_quarantine_category_parent_lookup.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 81-22: quarantine_inspection 전체 행 저장

SELECT *
FROM kream_project.`quarantine_inspection`
ORDER BY `bronze_row_id`
LIMIT 18446744073709551615
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_full_quarantine_inspection.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 81-23: quarantine_inspector_master 전체 행 저장

SELECT *
FROM kream_project.`quarantine_inspector_master`
ORDER BY `source_bronze_row_id`
LIMIT 18446744073709551615
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_full_quarantine_inspector_master.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 81-24: silver_category_parent_lookup 전체 행 저장

SELECT *
FROM kream_project.`silver_category_parent_lookup`
ORDER BY `CAT_ID`
LIMIT 18446744073709551615
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_full_silver_category_parent_lookup.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 81-25: silver_inspection 전체 행 저장

SELECT *
FROM kream_project.`silver_inspection`
ORDER BY `INSP_ID`, `REV_NO`
LIMIT 18446744073709551615
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_full_silver_inspection.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 81-26: silver_inspection_correction_log 전체 행 저장

SELECT *
FROM kream_project.`silver_inspection_correction_log`
ORDER BY `source_name`, `source_bronze_row_id`, `column_name`
LIMIT 18446744073709551615
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_full_silver_inspection_correction_log.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 81-27: silver_inspection_join_ready 전체 행 저장

SELECT *
FROM kream_project.`silver_inspection_join_ready`
ORDER BY `INSP_ID`, `REV_NO`
LIMIT 18446744073709551615
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_full_silver_inspection_join_ready.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 81-28: silver_product_std_dict 전체 행 저장

SELECT *
FROM kream_project.`silver_product_std_dict`
ORDER BY `DICT_ID`
LIMIT 18446744073709551615
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_full_silver_product_std_dict.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 81-29: 수정된 파일 이름에 대응하는 기준 목록 저장
-- DB의 기존 목록을 수정하지 않고 출력 파일 이름만 새 접두어로 구성

SELECT
    export_order,
    table_name,
    CONCAT('kream_full_', table_name, '.csv') AS output_file_name,
    table_role,
    actual_rows,
    expected_rows,
    column_count,
    row_count_status,
    export_version,
    captured_at_kst
FROM kream_project.documentation_export_manifest_v1
ORDER BY export_order
LIMIT 18446744073709551615
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_full_export_manifest_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 수정본은 이름이 kream_full_로 시작하는 CSV 29개만 묶어 압축
-- ZIP 이름: KREAM_Final_Data_Full_20261015.zip
-- 파일 검증이 끝나기 전까지 최종 검증 통과로 기록하지 않음
