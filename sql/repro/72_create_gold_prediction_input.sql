-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 72-1: 테이블 존재 여부와 입력 후보 확인

SELECT
    TABLE_NAME
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'kream_project_repro'
  AND TABLE_NAME IN (
      'gold_prediction_input_record_v1',
      'gold_prediction_input_daily_v1'
  );

SELECT
    COUNT(*) AS input_rows,
    COUNT(DISTINCT DATE(insp_done_dt_kst)) AS observed_days,
    MIN(insp_done_dt_kst) AS first_done_at,
    MAX(insp_done_dt_kst) AS last_done_at,
    MAX(extracted_at_kst) AS last_extracted_at,
    SUM(duration_min_candidate) AS total_duration_min
FROM kream_project_repro.asis_inspection_disposition_stage_v2
WHERE integrated_missing_check_flag = 0
  AND record_error_flag = 0
  AND valid_occurrence_no = 1
  AND normalized_rev_no = 1
  AND insp_done_dt_kst >= '2026-08-04 00:00:00'
  AND insp_done_dt_kst <  '2026-09-01 00:00:00'
  AND extracted_at_kst <= '2026-08-31 23:59:59';

  -- 작업 72-2: 예측 입력 상세 테이블 생성

CREATE TABLE kream_project_repro.gold_prediction_input_record_v1 (
    source_bronze_row_id BIGINT UNSIGNED NOT NULL,
    insp_done_dt_kst DATETIME NOT NULL,
    extracted_at_kst DATETIME NOT NULL,
    duration_min DECIMAL(12,8) NOT NULL,
    prediction_cutoff_kst DATETIME NOT NULL,
    rule_version VARCHAR(32) NOT NULL,

    PRIMARY KEY (source_bronze_row_id)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin;


-- 작업 72-3: 기준일 이전에 추출된 정상 최초 검수 저장

INSERT INTO kream_project_repro.gold_prediction_input_record_v1 (
    source_bronze_row_id,
    insp_done_dt_kst,
    extracted_at_kst,
    duration_min,
    prediction_cutoff_kst,
    rule_version
)
SELECT
    bronze_row_id,
    insp_done_dt_kst,
    extracted_at_kst,
    duration_min_candidate,
    '2026-08-31 23:59:59',
    '20261014_prediction_v1'
FROM kream_project_repro.asis_inspection_disposition_stage_v2
WHERE integrated_missing_check_flag = 0
  AND record_error_flag = 0
  AND valid_occurrence_no = 1
  AND normalized_rev_no = 1
  AND insp_done_dt_kst >= '2026-08-04 00:00:00'
  AND insp_done_dt_kst <  '2026-09-01 00:00:00'
  AND extracted_at_kst <= '2026-08-31 23:59:59';


-- 작업 72-4: 날짜별 예측 입력 테이블 생성 및 집계

CREATE TABLE kream_project_repro.gold_prediction_input_daily_v1 (
    inspection_date DATE NOT NULL,
    inspection_rows BIGINT UNSIGNED NOT NULL,
    total_duration_min DECIMAL(20,8) NOT NULL,
    avg_duration_min DECIMAL(12,4) NOT NULL,
    prediction_cutoff_kst DATETIME NOT NULL,
    rule_version VARCHAR(32) NOT NULL,

    PRIMARY KEY (inspection_date)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin;


INSERT INTO kream_project_repro.gold_prediction_input_daily_v1 (
    inspection_date,
    inspection_rows,
    total_duration_min,
    avg_duration_min,
    prediction_cutoff_kst,
    rule_version
)
SELECT
    DATE(insp_done_dt_kst),
    COUNT(*),
    SUM(duration_min),
    ROUND(AVG(duration_min), 4),
    '2026-08-31 23:59:59',
    '20261014_prediction_v1'
FROM kream_project_repro.gold_prediction_input_record_v1
GROUP BY DATE(insp_done_dt_kst);

-- 작업 72-5: 저장 건수와 날짜별 집계 검증

-- 결과 1: 상세와 일별 집계의 전체 합계

SELECT
    'RECORD_INPUT' AS input_type,
    COUNT(*) AS stored_rows,
    COUNT(*) AS inspection_rows,
    SUM(duration_min) AS total_duration_min
FROM kream_project_repro.gold_prediction_input_record_v1

UNION ALL

SELECT
    'DAILY_INPUT',
    COUNT(*),
    SUM(inspection_rows),
    SUM(total_duration_min)
FROM kream_project_repro.gold_prediction_input_daily_v1;


-- 결과 2: 원천 후보와 저장 상세의 누락 및 값 차이

WITH eligible_source AS (
    SELECT
        bronze_row_id,
        insp_done_dt_kst,
        extracted_at_kst,
        duration_min_candidate
    FROM kream_project_repro.asis_inspection_disposition_stage_v2
    WHERE integrated_missing_check_flag = 0
      AND record_error_flag = 0
      AND valid_occurrence_no = 1
      AND normalized_rev_no = 1
      AND insp_done_dt_kst >= '2026-08-04 00:00:00'
      AND insp_done_dt_kst <  '2026-09-01 00:00:00'
      AND extracted_at_kst <= '2026-08-31 23:59:59'
)
SELECT
    'SOURCE_MISSING_OR_VALUE_DIFFERENT' AS check_name,
    COUNT(*) AS failed_rows
FROM eligible_source AS s
LEFT JOIN kream_project_repro.gold_prediction_input_record_v1 AS p
  ON p.source_bronze_row_id = s.bronze_row_id
WHERE p.source_bronze_row_id IS NULL
   OR NOT (p.insp_done_dt_kst <=> s.insp_done_dt_kst)
   OR NOT (p.extracted_at_kst <=> s.extracted_at_kst)
   OR NOT (p.duration_min <=> s.duration_min_candidate)
   OR p.prediction_cutoff_kst <> '2026-08-31 23:59:59'
   OR p.rule_version <> '20261014_prediction_v1'

UNION ALL

SELECT
    'UNEXPECTED_STORED_RECORD',
    COUNT(*)
FROM kream_project_repro.gold_prediction_input_record_v1 AS p
LEFT JOIN eligible_source AS s
  ON s.bronze_row_id = p.source_bronze_row_id
WHERE s.bronze_row_id IS NULL;


-- 결과 3: 날짜별 집계의 누락 및 값 차이

WITH expected_daily AS (
    SELECT
        DATE(insp_done_dt_kst) AS inspection_date,
        COUNT(*) AS inspection_rows,
        SUM(duration_min) AS total_duration_min,
        ROUND(AVG(duration_min), 4) AS avg_duration_min
    FROM kream_project_repro.gold_prediction_input_record_v1
    GROUP BY DATE(insp_done_dt_kst)
)
SELECT
    'DAILY_MISSING_OR_VALUE_DIFFERENT' AS check_name,
    COUNT(*) AS failed_rows
FROM expected_daily AS e
LEFT JOIN kream_project_repro.gold_prediction_input_daily_v1 AS d
  ON d.inspection_date = e.inspection_date
WHERE d.inspection_date IS NULL
   OR NOT (d.inspection_rows <=> e.inspection_rows)
   OR NOT (d.total_duration_min <=> e.total_duration_min)
   OR NOT (d.avg_duration_min <=> e.avg_duration_min)
   OR d.prediction_cutoff_kst <> '2026-08-31 23:59:59'
   OR d.rule_version <> '20261014_prediction_v1'

UNION ALL

SELECT
    'UNEXPECTED_STORED_DAY',
    COUNT(*)
FROM kream_project_repro.gold_prediction_input_daily_v1 AS d
LEFT JOIN expected_daily AS e
  ON e.inspection_date = d.inspection_date
WHERE e.inspection_date IS NULL;


-- 결과 4: 예측에 사용할 날짜별 입력 확인

SELECT
    inspection_date,
    inspection_rows,
    total_duration_min,
    avg_duration_min,
    prediction_cutoff_kst
FROM kream_project_repro.gold_prediction_input_daily_v1
ORDER BY inspection_date;