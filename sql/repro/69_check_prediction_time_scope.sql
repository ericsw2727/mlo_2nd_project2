-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 69-1: 예측 입력과 평가 기간의 기준 설정
-- 모든 날짜와 시각은 한국 시간 기준
-- 종료 경계는 다음 날 0시를 사용

SET @kream_prediction_cutoff_kst =
    CAST('2026-08-31 23:59:59' AS DATETIME);

SET @kream_prediction_train_start =
    CAST('2026-08-04' AS DATE);

SET @kream_prediction_test_start =
    CAST('2026-09-01' AS DATE);

SET @kream_prediction_test_end =
    CAST('2026-09-08' AS DATE);

SELECT
    @kream_prediction_cutoff_kst AS prediction_cutoff_kst,
    @kream_prediction_train_start AS train_start_date,
    @kream_prediction_test_start AS test_start_date,
    @kream_prediction_test_end AS test_end_exclusive;


-- 작업 69-2: 연속 관측 기간의 최초 검수와 추출 시각 확인
-- 검수 완료일만 과거라고 당시 추출된 데이터로 간주하지 않음

SELECT
    COUNT(*) AS historical_first_inspection_rows,

    MIN(extracted_at_kst) AS first_extracted_at_kst,
    MAX(extracted_at_kst) AS last_extracted_at_kst,

    SUM(
        CASE
            WHEN extracted_at_kst <= @kream_prediction_cutoff_kst
            THEN 1 ELSE 0
        END
    ) AS extracted_by_cutoff_rows,

    SUM(
        CASE
            WHEN extracted_at_kst > @kream_prediction_cutoff_kst
            THEN 1 ELSE 0
        END
    ) AS extracted_after_cutoff_rows,

    SUM(
        CASE
            WHEN insp_done_dt_kst >= @kream_prediction_train_start
            THEN 1 ELSE 0
        END
    ) AS recent_28_day_rows,

    SUM(
        CASE
            WHEN insp_done_dt_kst >= @kream_prediction_train_start
             AND extracted_at_kst <= @kream_prediction_cutoff_kst
            THEN 1 ELSE 0
        END
    ) AS recent_28_day_extracted_by_cutoff_rows

FROM kream_project_repro.asis_inspection_disposition_stage_v2

WHERE integrated_missing_check_flag = 0
  AND record_error_flag = 0
  AND valid_occurrence_no = 1
  AND normalized_rev_no = 1
  AND insp_done_dt_kst >= '2022-01-01'
  AND insp_done_dt_kst < @kream_prediction_test_start;


-- 작업 69-3: 입력 후보 28일의 추출 날짜별 분포 확인
-- 완료 기간과 추출 기간의 차이를 확인

SELECT
    DATE(extracted_at_kst) AS extracted_date_kst,
    COUNT(*) AS inspection_rows,
    MIN(insp_done_dt_kst) AS first_done_kst,
    MAX(insp_done_dt_kst) AS last_done_kst

FROM kream_project_repro.asis_inspection_disposition_stage_v2

WHERE integrated_missing_check_flag = 0
  AND record_error_flag = 0
  AND valid_occurrence_no = 1
  AND normalized_rev_no = 1
  AND insp_done_dt_kst >= @kream_prediction_train_start
  AND insp_done_dt_kst < @kream_prediction_test_start

GROUP BY DATE(extracted_at_kst)
ORDER BY extracted_date_kst;


-- 작업 69-4: 평가 기간 후보의 일별 실제 작업량 확인
-- 이 값은 예측 입력으로 사용하지 않고 결과 평가에 사용

SELECT
    DATE(insp_done_dt_kst) AS evaluation_date_kst,
    COUNT(*) AS actual_inspection_rows,
    SUM(duration_min_candidate) AS actual_work_minutes,

    SUM(
        CASE
            WHEN extracted_at_kst <= @kream_prediction_cutoff_kst
            THEN 1 ELSE 0
        END
    ) AS extracted_before_prediction_rows

FROM kream_project_repro.asis_inspection_disposition_stage_v2

WHERE integrated_missing_check_flag = 0
  AND record_error_flag = 0
  AND valid_occurrence_no = 1
  AND normalized_rev_no = 1
  AND insp_done_dt_kst >= @kream_prediction_test_start
  AND insp_done_dt_kst < @kream_prediction_test_end

GROUP BY DATE(insp_done_dt_kst)
ORDER BY evaluation_date_kst;


-- 작업 69-5: 입력 후보 기간의 관측 일수 확인
-- 28일 중 실제 검수 기록이 있는 날짜 수 확인

SELECT
    COUNT(DISTINCT DATE(insp_done_dt_kst)) AS observed_train_days,
    MIN(DATE(insp_done_dt_kst)) AS first_train_date,
    MAX(DATE(insp_done_dt_kst)) AS last_train_date,

    COUNT(DISTINCT
        CASE
            WHEN extracted_at_kst <= @kream_prediction_cutoff_kst
            THEN DATE(insp_done_dt_kst)
            ELSE NULL
        END
    ) AS observed_train_days_extracted_by_cutoff

FROM kream_project_repro.asis_inspection_disposition_stage_v2

WHERE integrated_missing_check_flag = 0
  AND record_error_flag = 0
  AND valid_occurrence_no = 1
  AND normalized_rev_no = 1
  AND insp_done_dt_kst >= @kream_prediction_train_start
  AND insp_done_dt_kst < @kream_prediction_test_start;