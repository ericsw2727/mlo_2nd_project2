-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 75-1: 새 테이블 존재 여부 확인

SELECT
    TABLE_NAME
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'kream_project_repro'
  AND TABLE_NAME IN (
      'gold_workload_forecast_summary_v1',
      'gold_staffing_scenario_v1'
  );


  -- 작업 75-2: 예측 평가 요약 저장

CREATE TABLE kream_project_repro.gold_workload_forecast_summary_v1 (
    forecast_method VARCHAR(32) NOT NULL,
    evaluated_days INT UNSIGNED NOT NULL,

    actual_week_rows BIGINT UNSIGNED NOT NULL,
    predicted_week_rows DECIMAL(20,4) NOT NULL,
    inspection_mae DECIMAL(20,4) NOT NULL,
    inspection_wape_pct DECIMAL(20,4) NULL,

    actual_week_duration_min DECIMAL(24,8) NOT NULL,
    predicted_week_duration_min DECIMAL(24,4) NOT NULL,
    duration_mae_min DECIMAL(24,4) NOT NULL,
    duration_wape_pct DECIMAL(20,4) NULL,

    rule_version VARCHAR(32) NOT NULL,

    PRIMARY KEY (forecast_method)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin;


INSERT INTO kream_project_repro.gold_workload_forecast_summary_v1 (
    forecast_method,
    evaluated_days,
    actual_week_rows,
    predicted_week_rows,
    inspection_mae,
    inspection_wape_pct,
    actual_week_duration_min,
    predicted_week_duration_min,
    duration_mae_min,
    duration_wape_pct,
    rule_version
)
SELECT
    forecast_method,
    COUNT(*),

    SUM(actual_inspection_rows),
    SUM(predicted_inspection_rows),
    ROUND(AVG(inspection_abs_error), 4),
    ROUND(
        SUM(inspection_abs_error) * 100.0
            / NULLIF(SUM(actual_inspection_rows), 0),
        4
    ),

    SUM(actual_duration_min),
    SUM(predicted_duration_min),
    ROUND(AVG(duration_abs_error_min), 4),
    ROUND(
        SUM(duration_abs_error_min) * 100.0
            / NULLIF(SUM(actual_duration_min), 0),
        4
    ),

    '20261014_prediction_v1'
FROM kream_project_repro.gold_workload_forecast_evaluation_v1
GROUP BY forecast_method;


-- 작업 75-3: 인력 배치 시나리오 저장

CREATE TABLE kream_project_repro.gold_staffing_scenario_v1 (
    forecast_method VARCHAR(32) NOT NULL,
    forecast_date DATE NOT NULL,
    scenario_name VARCHAR(32) NOT NULL,

    available_minutes_per_person INT UNSIGNED NOT NULL,
    predicted_duration_min DECIMAL(20,4) NOT NULL,
    estimated_required_people INT UNSIGNED NOT NULL,

    prediction_cutoff_kst DATETIME NOT NULL,
    workload_scope VARCHAR(32) NOT NULL,
    assumption_basis VARCHAR(32) NOT NULL,
    rule_version VARCHAR(32) NOT NULL,

    PRIMARY KEY (
        forecast_method,
        forecast_date,
        scenario_name
    ),

    CONSTRAINT fk_staffing_forecast_v1
        FOREIGN KEY (forecast_method, forecast_date)
        REFERENCES kream_project_repro.gold_workload_forecast_v1 (
            forecast_method,
            forecast_date
        )
)
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin;


INSERT INTO kream_project_repro.gold_staffing_scenario_v1 (
    forecast_method,
    forecast_date,
    scenario_name,
    available_minutes_per_person,
    predicted_duration_min,
    estimated_required_people,
    prediction_cutoff_kst,
    workload_scope,
    assumption_basis,
    rule_version
)
WITH scenarios AS (
    SELECT
        'AVAILABLE_240_MIN' AS scenario_name,
        240 AS available_minutes_per_person

    UNION ALL

    SELECT 'AVAILABLE_360_MIN', 360

    UNION ALL

    SELECT 'AVAILABLE_480_MIN', 480
)
SELECT
    f.forecast_method,
    f.forecast_date,
    s.scenario_name,
    s.available_minutes_per_person,
    f.predicted_duration_min,

    CEIL(
        f.predicted_duration_min
            / s.available_minutes_per_person
    ),

    f.prediction_cutoff_kst,
    'FIRST_INSPECTION_ONLY',
    'ASSUMED_AVAILABLE_MINUTES',
    '20261014_prediction_v1'
FROM kream_project_repro.gold_workload_forecast_v1 AS f
CROSS JOIN scenarios AS s;



-- 작업 75-4: 저장 결과 검증과 시나리오 조회

-- 결과 1: 방법별 평가 요약

SELECT
    *
FROM kream_project_repro.gold_workload_forecast_summary_v1
ORDER BY forecast_method;


-- 결과 2: 평가 요약의 누락과 계산 차이

WITH expected_summary AS (
    SELECT
        forecast_method,
        COUNT(*) AS evaluated_days,

        SUM(actual_inspection_rows) AS actual_week_rows,
        SUM(predicted_inspection_rows) AS predicted_week_rows,
        ROUND(AVG(inspection_abs_error), 4) AS inspection_mae,
        ROUND(
            SUM(inspection_abs_error) * 100.0
                / NULLIF(SUM(actual_inspection_rows), 0),
            4
        ) AS inspection_wape_pct,

        SUM(actual_duration_min) AS actual_week_duration_min,
        SUM(predicted_duration_min) AS predicted_week_duration_min,
        ROUND(AVG(duration_abs_error_min), 4) AS duration_mae_min,
        ROUND(
            SUM(duration_abs_error_min) * 100.0
                / NULLIF(SUM(actual_duration_min), 0),
            4
        ) AS duration_wape_pct

    FROM kream_project_repro.gold_workload_forecast_evaluation_v1
    GROUP BY forecast_method
)
SELECT
    'SUMMARY_MISSING_OR_DIFFERENT' AS check_name,
    COUNT(*) AS failed_rows
FROM expected_summary AS e
LEFT JOIN kream_project_repro.gold_workload_forecast_summary_v1 AS s
  ON s.forecast_method = e.forecast_method
WHERE s.forecast_method IS NULL
   OR NOT (s.evaluated_days <=> e.evaluated_days)
   OR NOT (s.actual_week_rows <=> e.actual_week_rows)
   OR NOT (s.predicted_week_rows <=> e.predicted_week_rows)
   OR NOT (s.inspection_mae <=> e.inspection_mae)
   OR NOT (s.inspection_wape_pct <=> e.inspection_wape_pct)
   OR NOT (
       s.actual_week_duration_min <=> e.actual_week_duration_min
   )
   OR NOT (
       s.predicted_week_duration_min <=> e.predicted_week_duration_min
   )
   OR NOT (s.duration_mae_min <=> e.duration_mae_min)
   OR NOT (s.duration_wape_pct <=> e.duration_wape_pct)
   OR s.rule_version <> '20261014_prediction_v1'

UNION ALL

SELECT
    'UNEXPECTED_SUMMARY',
    COUNT(*)
FROM kream_project_repro.gold_workload_forecast_summary_v1 AS s
LEFT JOIN expected_summary AS e
  ON e.forecast_method = s.forecast_method
WHERE e.forecast_method IS NULL;


-- 결과 3: 시나리오별 저장 건수와 필요 인원 범위

SELECT
    forecast_method,
    scenario_name,
    available_minutes_per_person,
    COUNT(*) AS forecast_days,
    MIN(estimated_required_people) AS min_required_people,
    MAX(estimated_required_people) AS max_required_people
FROM kream_project_repro.gold_staffing_scenario_v1
GROUP BY
    forecast_method,
    scenario_name,
    available_minutes_per_person
ORDER BY
    forecast_method,
    available_minutes_per_person;


-- 결과 4: 시나리오 누락과 계산 차이

WITH scenarios AS (
    SELECT
        'AVAILABLE_240_MIN' AS scenario_name,
        240 AS available_minutes_per_person

    UNION ALL

    SELECT 'AVAILABLE_360_MIN', 360

    UNION ALL

    SELECT 'AVAILABLE_480_MIN', 480
),
expected_scenarios AS (
    SELECT
        f.forecast_method,
        f.forecast_date,
        s.scenario_name,
        s.available_minutes_per_person,
        f.predicted_duration_min,
        f.prediction_cutoff_kst
    FROM kream_project_repro.gold_workload_forecast_v1 AS f
    CROSS JOIN scenarios AS s
)
SELECT
    'SCENARIO_MISSING_OR_DIFFERENT' AS check_name,
    COUNT(*) AS failed_rows
FROM expected_scenarios AS e
LEFT JOIN kream_project_repro.gold_staffing_scenario_v1 AS s
  ON s.forecast_method = e.forecast_method
 AND s.forecast_date = e.forecast_date
 AND s.scenario_name = e.scenario_name
WHERE s.scenario_name IS NULL
   OR NOT (
       s.available_minutes_per_person
           <=> e.available_minutes_per_person
   )
   OR NOT (
       s.predicted_duration_min <=> e.predicted_duration_min
   )
   OR NOT (
       s.estimated_required_people
           <=> CEIL(
               e.predicted_duration_min
                   / e.available_minutes_per_person
           )
   )
   OR NOT (
       s.prediction_cutoff_kst <=> e.prediction_cutoff_kst
   )
   OR s.workload_scope <> 'FIRST_INSPECTION_ONLY'
   OR s.assumption_basis <> 'ASSUMED_AVAILABLE_MINUTES'
   OR s.rule_version <> '20261014_prediction_v1'

UNION ALL

SELECT
    'UNEXPECTED_SCENARIO',
    COUNT(*)
FROM kream_project_repro.gold_staffing_scenario_v1 AS s
LEFT JOIN expected_scenarios AS e
  ON e.forecast_method = s.forecast_method
 AND e.forecast_date = s.forecast_date
 AND e.scenario_name = s.scenario_name
WHERE e.scenario_name IS NULL;


-- 결과 5: 날짜별 인력 배치 시나리오

SELECT
    forecast_date,
    forecast_method,
    scenario_name,
    available_minutes_per_person,
    predicted_duration_min,
    estimated_required_people,
    workload_scope,
    assumption_basis
FROM kream_project_repro.gold_staffing_scenario_v1
ORDER BY
    forecast_date,
    forecast_method,
    available_minutes_per_person;