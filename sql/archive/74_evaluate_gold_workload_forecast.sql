-- 작업 74-1: 평가 테이블 존재 여부와 실제값 확인

SELECT
    TABLE_NAME
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'kream_project'
  AND TABLE_NAME IN (
      'gold_prediction_actual_daily_v1',
      'gold_workload_forecast_evaluation_v1'
  );


SELECT
    COUNT(DISTINCT DATE(insp_done_dt_kst)) AS actual_days,
    COUNT(*) AS actual_inspection_rows,
    SUM(duration_min_candidate) AS actual_duration_min
FROM kream_project.asis_inspection_disposition_stage_v2
WHERE integrated_missing_check_flag = 0
  AND record_error_flag = 0
  AND valid_occurrence_no = 1
  AND normalized_rev_no = 1
  AND insp_done_dt_kst >= '2026-09-01 00:00:00'
  AND insp_done_dt_kst <  '2026-09-08 00:00:00';


  -- 작업 74-2: 평가용 날짜별 실제값 저장

CREATE TABLE kream_project.gold_prediction_actual_daily_v1 (
    inspection_date DATE NOT NULL,
    actual_inspection_rows BIGINT UNSIGNED NOT NULL,
    actual_duration_min DECIMAL(20,8) NOT NULL,
    rule_version VARCHAR(32) NOT NULL,

    PRIMARY KEY (inspection_date)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin;


INSERT INTO kream_project.gold_prediction_actual_daily_v1 (
    inspection_date,
    actual_inspection_rows,
    actual_duration_min,
    rule_version
)
SELECT
    DATE(insp_done_dt_kst),
    COUNT(*),
    SUM(duration_min_candidate),
    '20261014_prediction_v1'
FROM kream_project.asis_inspection_disposition_stage_v2
WHERE integrated_missing_check_flag = 0
  AND record_error_flag = 0
  AND valid_occurrence_no = 1
  AND normalized_rev_no = 1
  AND insp_done_dt_kst >= '2026-09-01 00:00:00'
  AND insp_done_dt_kst <  '2026-09-08 00:00:00'
GROUP BY DATE(insp_done_dt_kst);


-- 작업 74-3: 날짜별 예측값과 실제값의 오차 저장

CREATE TABLE kream_project.gold_workload_forecast_evaluation_v1 (
    forecast_method VARCHAR(32) NOT NULL,
    forecast_date DATE NOT NULL,

    predicted_inspection_rows DECIMAL(16,4) NOT NULL,
    actual_inspection_rows BIGINT UNSIGNED NOT NULL,
    inspection_error DECIMAL(16,4) NOT NULL,
    inspection_abs_error DECIMAL(16,4) NOT NULL,

    predicted_duration_min DECIMAL(20,4) NOT NULL,
    actual_duration_min DECIMAL(20,8) NOT NULL,
    duration_error_min DECIMAL(20,8) NOT NULL,
    duration_abs_error_min DECIMAL(20,8) NOT NULL,

    prediction_cutoff_kst DATETIME NOT NULL,
    rule_version VARCHAR(32) NOT NULL,

    PRIMARY KEY (forecast_method, forecast_date)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin;


INSERT INTO kream_project.gold_workload_forecast_evaluation_v1 (
    forecast_method,
    forecast_date,
    predicted_inspection_rows,
    actual_inspection_rows,
    inspection_error,
    inspection_abs_error,
    predicted_duration_min,
    actual_duration_min,
    duration_error_min,
    duration_abs_error_min,
    prediction_cutoff_kst,
    rule_version
)
SELECT
    f.forecast_method,
    f.forecast_date,

    f.predicted_inspection_rows,
    a.actual_inspection_rows,
    f.predicted_inspection_rows
        - CAST(a.actual_inspection_rows AS DECIMAL(16,4)),
    ABS(
        f.predicted_inspection_rows
            - CAST(a.actual_inspection_rows AS DECIMAL(16,4))
    ),

    f.predicted_duration_min,
    a.actual_duration_min,
    f.predicted_duration_min - a.actual_duration_min,
    ABS(f.predicted_duration_min - a.actual_duration_min),

    f.prediction_cutoff_kst,
    '20261014_prediction_v1'
FROM kream_project.gold_workload_forecast_v1 AS f
JOIN kream_project.gold_prediction_actual_daily_v1 AS a
  ON a.inspection_date = f.forecast_date;



  -- 작업 74-4: 저장 결과 검증과 방법별 오차 평가

-- 결과 1: 실제값 저장 합계

SELECT
    COUNT(*) AS actual_days,
    MIN(inspection_date) AS first_actual_date,
    MAX(inspection_date) AS last_actual_date,
    SUM(actual_inspection_rows) AS actual_inspection_rows,
    SUM(actual_duration_min) AS actual_duration_min
FROM kream_project.gold_prediction_actual_daily_v1;


-- 결과 2: 예측 기록의 평가 누락과 저장값 차이

SELECT
    COUNT(*) AS missing_or_mismatched_evaluation_rows
FROM kream_project.gold_workload_forecast_v1 AS f
LEFT JOIN kream_project.gold_prediction_actual_daily_v1 AS a
  ON a.inspection_date = f.forecast_date
LEFT JOIN kream_project.gold_workload_forecast_evaluation_v1 AS e
  ON e.forecast_method = f.forecast_method
 AND e.forecast_date = f.forecast_date
WHERE a.inspection_date IS NULL
   OR e.forecast_date IS NULL
   OR NOT (
       e.predicted_inspection_rows
           <=> f.predicted_inspection_rows
   )
   OR NOT (
       e.actual_inspection_rows
           <=> a.actual_inspection_rows
   )
   OR NOT (
       e.inspection_error
           <=> (
               f.predicted_inspection_rows
                   - CAST(a.actual_inspection_rows AS DECIMAL(16,4))
           )
   )
   OR NOT (
       e.inspection_abs_error
           <=> ABS(
               f.predicted_inspection_rows
                   - CAST(a.actual_inspection_rows AS DECIMAL(16,4))
           )
   )
   OR NOT (
       e.predicted_duration_min
           <=> f.predicted_duration_min
   )
   OR NOT (
       e.actual_duration_min
           <=> a.actual_duration_min
   )
   OR NOT (
       e.duration_error_min
           <=> (f.predicted_duration_min - a.actual_duration_min)
   )
   OR NOT (
       e.duration_abs_error_min
           <=> ABS(f.predicted_duration_min - a.actual_duration_min)
   )
   OR NOT (
       e.prediction_cutoff_kst <=> f.prediction_cutoff_kst
   )
   OR e.rule_version <> '20261014_prediction_v1';


-- 결과 3: 예상하지 않은 평가 기록

SELECT
    COUNT(*) AS unexpected_evaluation_rows
FROM kream_project.gold_workload_forecast_evaluation_v1 AS e
LEFT JOIN kream_project.gold_workload_forecast_v1 AS f
  ON f.forecast_method = e.forecast_method
 AND f.forecast_date = e.forecast_date
WHERE f.forecast_date IS NULL;


-- 결과 4: 방법별 예측 오차

SELECT
    forecast_method,
    COUNT(*) AS evaluated_days,

    SUM(actual_inspection_rows) AS actual_week_rows,
    SUM(predicted_inspection_rows) AS predicted_week_rows,
    ROUND(AVG(inspection_error), 4) AS inspection_mean_error,
    ROUND(AVG(inspection_abs_error), 4) AS inspection_mae,
    ROUND(
        SUM(inspection_abs_error) * 100.0
            / NULLIF(SUM(actual_inspection_rows), 0),
        4
    ) AS inspection_wape_pct,

    SUM(actual_duration_min) AS actual_week_duration_min,
    SUM(predicted_duration_min) AS predicted_week_duration_min,
    ROUND(AVG(duration_error_min), 4) AS duration_mean_error_min,
    ROUND(AVG(duration_abs_error_min), 4) AS duration_mae_min,
    ROUND(
        SUM(duration_abs_error_min) * 100.0
            / NULLIF(SUM(actual_duration_min), 0),
        4
    ) AS duration_wape_pct

FROM kream_project.gold_workload_forecast_evaluation_v1
GROUP BY forecast_method
ORDER BY forecast_method;


-- 결과 5: 날짜별 예측값과 실제값 비교

SELECT
    forecast_date,
    forecast_method,
    actual_inspection_rows,
    predicted_inspection_rows,
    inspection_error,
    inspection_abs_error,
    actual_duration_min,
    predicted_duration_min,
    duration_error_min,
    duration_abs_error_min
FROM kream_project.gold_workload_forecast_evaluation_v1
ORDER BY
    forecast_date,
    forecast_method;