-- 작업 80: 주요 결과 데이터 28개와 내보내기 목록 1개 저장
-- 파일: 80_export_final_data.sql
-- 저장 경로: C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/
-- UTF-8, 헤더 없음, MySQL 역슬래시 이스케이프 형식
-- NULL은 \N으로 저장. 문자열의 쉼표와 따옴표 등은 이스케이프 처리.
-- 실제 파일 검증에서는 일반 줄 수가 아닌 이 형식으로 해석한 레코드 수를 사용.
-- 기본키 순서로 정렬하며 컬럼 순서는 77번 구조 목록과 같음.
-- 같은 이름의 파일이 존재하면 덮어쓰지 않고 오류가 발생.
-- 중간에 오류가 나면 중지하고 오류 메시지를 확인. 성공한 문장을 다시 실행하지 않음.
-- 전체 실행 전에 80-1만 선택 실행하여 허용 경로와 목록을 확인.

-- 작업 80-1: 허용 경로와 목록 확인

SELECT @@GLOBAL.secure_file_priv AS export_directory;

SELECT
    COUNT(*) AS export_table_count,
    SUM(row_count_status = 'MATCH') AS matched_table_count,
    SUM(row_count_status = 'DIFFERENT') AS different_table_count,
    SUM(column_count) AS total_column_count
FROM kream_project.documentation_export_manifest_v1;

-- 정상 기준: 테이블 28, 일치 28, 차이 0, 컬럼 합계 393
-- 아래 작업은 저장을 실행하는 문장. 결과 표가 아니라 Output에 완료가 표시됨.

-- 작업 80-2: asis_inspection_join_row_pair_v1 저장

SELECT *
FROM kream_project.`asis_inspection_join_row_pair_v1`
ORDER BY `inspection_bronze_row_id`
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_asis_inspection_join_row_pair_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 80-3: asis_join_ready_disposition_snapshot_v1 저장

SELECT *
FROM kream_project.`asis_join_ready_disposition_snapshot_v1`
ORDER BY `join_ready_bronze_row_id`
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_asis_join_ready_disposition_snapshot_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 80-4: data_quality_check_results_v1 저장

SELECT *
FROM kream_project.`data_quality_check_results_v1`
ORDER BY `check_id`
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_data_quality_check_results_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 80-5: excluded_category_parent_lookup 저장

SELECT *
FROM kream_project.`excluded_category_parent_lookup`
ORDER BY `source_bronze_row_id`
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_excluded_category_parent_lookup.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 80-6: excluded_inspection 저장

SELECT *
FROM kream_project.`excluded_inspection`
ORDER BY `bronze_row_id`
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_excluded_inspection.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 80-7: excluded_inspector_master 저장

SELECT *
FROM kream_project.`excluded_inspector_master`
ORDER BY `source_bronze_row_id`
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_excluded_inspector_master.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 80-8: gold_department_risk_summary_v1 저장

SELECT *
FROM kream_project.`gold_department_risk_summary_v1`
ORDER BY `department_name`
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_gold_department_risk_summary_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 80-9: gold_inspection_result_daily_v1 저장

SELECT *
FROM kream_project.`gold_inspection_result_daily_v1`
ORDER BY `done_date_kst`
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_gold_inspection_result_daily_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 80-10: gold_inspection_workload_daily_v1 저장

SELECT *
FROM kream_project.`gold_inspection_workload_daily_v1`
ORDER BY `done_date_kst`, `event_type`
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_gold_inspection_workload_daily_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 80-11: gold_inspection_workload_hourly_v1 저장

SELECT *
FROM kream_project.`gold_inspection_workload_hourly_v1`
ORDER BY `done_date_kst`, `done_hour_kst`, `department_name`, `event_type`
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_gold_inspection_workload_hourly_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 80-12: gold_prediction_actual_daily_v1 저장

SELECT *
FROM kream_project.`gold_prediction_actual_daily_v1`
ORDER BY `inspection_date`
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_gold_prediction_actual_daily_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 80-13: gold_prediction_input_daily_v1 저장

SELECT *
FROM kream_project.`gold_prediction_input_daily_v1`
ORDER BY `inspection_date`
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_gold_prediction_input_daily_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 80-14: gold_prediction_input_record_v1 저장

SELECT *
FROM kream_project.`gold_prediction_input_record_v1`
ORDER BY `source_bronze_row_id`
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_gold_prediction_input_record_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 80-15: gold_product_risk_summary_v1 저장

SELECT *
FROM kream_project.`gold_product_risk_summary_v1`
ORDER BY `item_std_code`
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_gold_product_risk_summary_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 80-16: gold_risk_cross_summary_v1 저장

SELECT *
FROM kream_project.`gold_risk_cross_summary_v1`
ORDER BY `item_std_code`, `department_name`, `final_revision_type`, `analysis_period`
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_gold_risk_cross_summary_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 80-17: gold_staffing_scenario_v1 저장

SELECT *
FROM kream_project.`gold_staffing_scenario_v1`
ORDER BY `forecast_method`, `forecast_date`, `scenario_name`
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_gold_staffing_scenario_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 80-18: gold_workload_forecast_evaluation_v1 저장

SELECT *
FROM kream_project.`gold_workload_forecast_evaluation_v1`
ORDER BY `forecast_method`, `forecast_date`
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_gold_workload_forecast_evaluation_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 80-19: gold_workload_forecast_summary_v1 저장

SELECT *
FROM kream_project.`gold_workload_forecast_summary_v1`
ORDER BY `forecast_method`
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_gold_workload_forecast_summary_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 80-20: gold_workload_forecast_v1 저장

SELECT *
FROM kream_project.`gold_workload_forecast_v1`
ORDER BY `forecast_method`, `forecast_date`
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_gold_workload_forecast_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 80-21: quarantine_category_parent_lookup 저장

SELECT *
FROM kream_project.`quarantine_category_parent_lookup`
ORDER BY `source_bronze_row_id`
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_quarantine_category_parent_lookup.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 80-22: quarantine_inspection 저장

SELECT *
FROM kream_project.`quarantine_inspection`
ORDER BY `bronze_row_id`
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_quarantine_inspection.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 80-23: quarantine_inspector_master 저장

SELECT *
FROM kream_project.`quarantine_inspector_master`
ORDER BY `source_bronze_row_id`
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_quarantine_inspector_master.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 80-24: silver_category_parent_lookup 저장

SELECT *
FROM kream_project.`silver_category_parent_lookup`
ORDER BY `CAT_ID`
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_silver_category_parent_lookup.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 80-25: silver_inspection 저장

SELECT *
FROM kream_project.`silver_inspection`
ORDER BY `INSP_ID`, `REV_NO`
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_silver_inspection.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 80-26: silver_inspection_correction_log 저장

SELECT *
FROM kream_project.`silver_inspection_correction_log`
ORDER BY `source_name`, `source_bronze_row_id`, `column_name`
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_silver_inspection_correction_log.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 80-27: silver_inspection_join_ready 저장

SELECT *
FROM kream_project.`silver_inspection_join_ready`
ORDER BY `INSP_ID`, `REV_NO`
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_silver_inspection_join_ready.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 80-28: silver_inspector_master 저장

SELECT *
FROM kream_project.`silver_inspector_master`
ORDER BY `EMP_NO`
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_silver_inspector_master.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 80-29: silver_product_std_dict 저장

SELECT *
FROM kream_project.`silver_product_std_dict`
ORDER BY `DICT_ID`
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_silver_product_std_dict.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 작업 80-30: 파일별 기준 건수 목록 저장
-- 이 목록은 데이터 파일 28개의 건수와 컬럼 수 대조에 사용

SELECT *
FROM kream_project.documentation_export_manifest_v1
ORDER BY export_order
INTO OUTFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_export_manifest_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

-- 다음 단계: 파일 탐색기에서 생성된 파일 29개를 확인.
-- 파일 29개를 하나의 ZIP으로 압축한 뒤 첨부.
-- 앞서 내보낸 구조 CSV 4개와는 별도 파일 묶음.
-- 내보내기 완료와 파일 내용 검증 완료는 구분.
