-- 작업 73-1: 예측 테이블 존재 여부와 입력 범위 확인

SELECT
    TABLE_NAME
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'kream_project'
  AND TABLE_NAME = 'gold_workload_forecast_v1';


SELECT
    COUNT(*) AS input_days,
    MIN(inspection_date) AS first_input_date,
    MAX(inspection_date) AS last_input_date,
    SUM(inspection_rows) AS input_inspection_rows,
    SUM(total_duration_min) AS input_duration_min,
    MIN(prediction_cutoff_kst) AS min_cutoff_kst,
    MAX(prediction_cutoff_kst) AS max_cutoff_kst
FROM kream_project.gold_prediction_input_daily_v1;

-- 작업 73-2: 예측 결과 테이블 생성

CREATE TABLE kream_project.gold_workload_forecast_v1 (
    forecast_method VARCHAR(32) NOT NULL,
    forecast_date DATE NOT NULL,

    predicted_inspection_rows DECIMAL(16,4) NOT NULL,
    predicted_duration_min DECIMAL(20,4) NOT NULL,

    training_days INT UNSIGNED NOT NULL,
    training_start_date DATE NOT NULL,
    training_end_date DATE NOT NULL,
    prediction_cutoff_kst DATETIME NOT NULL,
    rule_version VARCHAR(32) NOT NULL,

    PRIMARY KEY (forecast_method, forecast_date)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin;


-- 작업 73-3: 7일에 대해 두 방법의 예측값 저장

INSERT INTO kream_project.gold_workload_forecast_v1 (
    forecast_method,
    forecast_date,
    predicted_inspection_rows,
    predicted_duration_min,
    training_days,
    training_start_date,
    training_end_date,
    prediction_cutoff_kst,
    rule_version
)
WITH RECURSIVE forecast_dates AS (
    SELECT CAST('2026-09-01' AS DATE) AS forecast_date

    UNION ALL

    SELECT DATE_ADD(forecast_date, INTERVAL 1 DAY)
    FROM forecast_dates
    WHERE forecast_date < '2026-09-07'
),
recent_mean AS (
    SELECT
        COUNT(*) AS training_days,
        AVG(inspection_rows) AS predicted_rows,
        AVG(total_duration_min) AS predicted_minutes
    FROM kream_project.gold_prediction_input_daily_v1
    WHERE inspection_date >= '2026-08-04'
      AND inspection_date <  '2026-09-01'
      AND prediction_cutoff_kst = '2026-08-31 23:59:59'
),
weekday_mean AS (
    SELECT
        WEEKDAY(inspection_date) AS weekday_no,
        COUNT(*) AS training_days,
        AVG(inspection_rows) AS predicted_rows,
        AVG(total_duration_min) AS predicted_minutes
    FROM kream_project.gold_prediction_input_daily_v1
    WHERE inspection_date >= '2026-08-04'
      AND inspection_date <  '2026-09-01'
      AND prediction_cutoff_kst = '2026-08-31 23:59:59'
    GROUP BY WEEKDAY(inspection_date)
)
SELECT
    'RECENT_28_DAY_MEAN',
    f.forecast_date,
    ROUND(m.predicted_rows, 4),
    ROUND(m.predicted_minutes, 4),
    m.training_days,
    '2026-08-04',
    '2026-08-31',
    '2026-08-31 23:59:59',
    '20261014_prediction_v1'
FROM forecast_dates AS f
CROSS JOIN recent_mean AS m

UNION ALL

SELECT
    'SAME_WEEKDAY_MEAN',
    f.forecast_date,
    ROUND(w.predicted_rows, 4),
    ROUND(w.predicted_minutes, 4),
    w.training_days,
    '2026-08-04',
    '2026-08-31',
    '2026-08-31 23:59:59',
    '20261014_prediction_v1'
FROM forecast_dates AS f
JOIN weekday_mean AS w
  ON w.weekday_no = WEEKDAY(f.forecast_date);


  -- 작업 73-4: 예측 결과 검증 및 조회

-- 결과 1: 방법별 저장 범위

SELECT
    forecast_method,
    COUNT(*) AS forecast_days,
    MIN(forecast_date) AS first_forecast_date,
    MAX(forecast_date) AS last_forecast_date,
    MIN(training_days) AS min_training_days,
    MAX(training_days) AS max_training_days,
    SUM(predicted_inspection_rows) AS predicted_week_rows,
    SUM(predicted_duration_min) AS predicted_week_duration_min
FROM kream_project.gold_workload_forecast_v1
GROUP BY forecast_method
ORDER BY forecast_method;


-- 결과 2: 날짜, 방법, 입력 기간 및 기준 시각 검사

SELECT
    COUNT(*) AS invalid_forecast_rows
FROM kream_project.gold_workload_forecast_v1
WHERE forecast_method NOT IN (
          'RECENT_28_DAY_MEAN',
          'SAME_WEEKDAY_MEAN'
      )
   OR forecast_date < '2026-09-01'
   OR forecast_date > '2026-09-07'
   OR predicted_inspection_rows < 0
   OR predicted_duration_min < 0
   OR training_start_date <> '2026-08-04'
   OR training_end_date <> '2026-08-31'
   OR prediction_cutoff_kst <> '2026-08-31 23:59:59'
   OR rule_version <> '20261014_prediction_v1'
   OR (
       forecast_method = 'RECENT_28_DAY_MEAN'
       AND training_days <> 28
   )
   OR (
       forecast_method = 'SAME_WEEKDAY_MEAN'
       AND training_days <> 4
   );


-- 결과 3: 저장된 예측값을 입력 데이터로 다시 계산해 대조

WITH recalculated AS (
    SELECT
        f.forecast_method,
        f.forecast_date,
        COUNT(*) AS expected_training_days,
        ROUND(AVG(d.inspection_rows), 4) AS expected_rows,
        ROUND(AVG(d.total_duration_min), 4) AS expected_minutes
    FROM kream_project.gold_workload_forecast_v1 AS f
    JOIN kream_project.gold_prediction_input_daily_v1 AS d
      ON d.inspection_date >= '2026-08-04'
     AND d.inspection_date <  '2026-09-01'
     AND d.prediction_cutoff_kst = '2026-08-31 23:59:59'
     AND (
         f.forecast_method = 'RECENT_28_DAY_MEAN'
         OR (
             f.forecast_method = 'SAME_WEEKDAY_MEAN'
             AND WEEKDAY(d.inspection_date)
                 = WEEKDAY(f.forecast_date)
         )
     )
    GROUP BY
        f.forecast_method,
        f.forecast_date
)
SELECT
    COUNT(*) AS forecast_calculation_mismatch_rows
FROM kream_project.gold_workload_forecast_v1 AS f
LEFT JOIN recalculated AS r
  ON r.forecast_method = f.forecast_method
 AND r.forecast_date = f.forecast_date
WHERE r.forecast_date IS NULL
   OR NOT (f.training_days <=> r.expected_training_days)
   OR NOT (f.predicted_inspection_rows <=> r.expected_rows)
   OR NOT (f.predicted_duration_min <=> r.expected_minutes);


-- 결과 4: 날짜별 예측값

SELECT
    forecast_date,
    forecast_method,
    predicted_inspection_rows,
    predicted_duration_min,
    training_days,
    prediction_cutoff_kst
FROM kream_project.gold_workload_forecast_v1
ORDER BY
    forecast_date,
    forecast_method;