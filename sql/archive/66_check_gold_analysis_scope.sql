-- 작업 66-1: 최종 상태와 유효 검수 기록의 기간 및 건수 확인
-- 최종 상태는 주문별 한 행
-- 작업량은 정상 이전 개정을 포함하되 동일 중복은 제외

SELECT
    'FINAL_INSPECTION_STATE' AS analysis_scope,
    COUNT(*) AS record_rows,
    COUNT(DISTINCT INSP_ID) AS distinct_inspection_ids,
    MIN(INBOUND_DT) AS first_inbound_kst,
    MAX(INBOUND_DT) AS last_inbound_kst,
    MIN(INSP_DONE_DT) AS first_done_kst,
    MAX(INSP_DONE_DT) AS last_done_kst,
    COUNT(DISTINCT DATE(INSP_DONE_DT)) AS observed_done_days
FROM kream_project.silver_inspection

UNION ALL

SELECT
    'VALID_INSPECTION_EVENTS',
    COUNT(*),
    COUNT(DISTINCT normalized_insp_id),
    MIN(inbound_dt_kst),
    MAX(inbound_dt_kst),
    MIN(insp_done_dt_kst),
    MAX(insp_done_dt_kst),
    COUNT(DISTINCT DATE(insp_done_dt_kst))
FROM kream_project.asis_inspection_disposition_stage_v2
WHERE integrated_missing_check_flag = 0
  AND record_error_flag = 0
  AND valid_occurrence_no = 1;


-- 작업 66-2: 최종 상태의 월별 결과와 배상금 확인
-- 최종 유효 개정의 검수 완료 월 기준
-- 과거 시점에 알 수 있었던 결과를 재현한 집계는 아님

SELECT
    DATE_FORMAT(INSP_DONE_DT, '%Y-%m') AS done_month_kst,
    MIN(DATE(INSP_DONE_DT)) AS first_observed_date,
    MAX(DATE(INSP_DONE_DT)) AS last_observed_date,
    COUNT(DISTINCT DATE(INSP_DONE_DT)) AS observed_days,
    COUNT(*) AS final_inspection_rows,

    SUM(
        CASE WHEN INSP_RESULT = 'PASS'
             THEN 1 ELSE 0 END
    ) AS pass_rows,

    SUM(
        CASE WHEN INSP_RESULT = 'FAKE_REJECT'
             THEN 1 ELSE 0 END
    ) AS fake_reject_rows,

    SUM(
        CASE WHEN INSP_RESULT = 'BOX_DMG_HOLD'
             THEN 1 ELSE 0 END
    ) AS box_damage_hold_rows,

    SUM(
        CASE WHEN INSP_RESULT = 'CLAIM_FAKE_PASS'
             THEN 1 ELSE 0 END
    ) AS fake_pass_claim_rows,

    SUM(COMPENSATION_LOSS_KRW) AS compensation_loss_krw

FROM kream_project.silver_inspection_join_ready
GROUP BY DATE_FORMAT(INSP_DONE_DT, '%Y-%m')
ORDER BY done_month_kst;


-- 작업 66-3: 유효 검수 기록의 월별 작업량 확인
-- 개정 번호가 2 이상인 정상 기록은 재검수로 집계
-- 검수 소요 시간은 제공된 분 단위 수치를 사용

SELECT
    DATE_FORMAT(insp_done_dt_kst, '%Y-%m') AS done_month_kst,
    COUNT(*) AS inspection_event_rows,

    SUM(
        CASE WHEN normalized_rev_no = 1
             THEN 1 ELSE 0 END
    ) AS first_revision_rows,

    SUM(
        CASE WHEN normalized_rev_no >= 2
             THEN 1 ELSE 0 END
    ) AS reinspection_rows,

    SUM(duration_min_candidate) AS total_work_minutes,
    ROUND(AVG(duration_min_candidate), 4) AS avg_work_minutes,

    COUNT(DISTINCT inspector_emp_no_candidate)
        AS observed_inspector_ids

FROM kream_project.asis_inspection_disposition_stage_v2
WHERE integrated_missing_check_flag = 0
  AND record_error_flag = 0
  AND valid_occurrence_no = 1

GROUP BY DATE_FORMAT(insp_done_dt_kst, '%Y-%m')
ORDER BY done_month_kst;


-- 작업 66-4: 검수 완료 시간대별 유효 작업량 확인
-- 완료 시각 기준으로 소요 시간을 묶은 집계
-- 해당 시간대에 실제로 수행한 모든 작업 시간을 뜻하지는 않음

SELECT
    HOUR(insp_done_dt_kst) AS done_hour_kst,
    COUNT(*) AS inspection_event_rows,

    SUM(
        CASE WHEN normalized_rev_no >= 2
             THEN 1 ELSE 0 END
    ) AS reinspection_rows,

    SUM(duration_min_candidate) AS total_work_minutes,
    ROUND(AVG(duration_min_candidate), 4) AS avg_work_minutes

FROM kream_project.asis_inspection_disposition_stage_v2
WHERE integrated_missing_check_flag = 0
  AND record_error_flag = 0
  AND valid_occurrence_no = 1

GROUP BY HOUR(insp_done_dt_kst)
ORDER BY done_hour_kst;


-- 작업 66-5: 현재 마스터의 부서별 인원 확인
-- 현재 재직 표기이며 과거 날짜의 실제 근무 인원은 아님

SELECT
    DEPT_NM,
    COUNT(*) AS registered_inspector_rows,

    SUM(
        CASE WHEN ACTIVE_YN = 'Y'
             THEN 1 ELSE 0 END
    ) AS active_inspector_rows,

    SUM(
        CASE WHEN ACTIVE_YN = 'N'
             THEN 1 ELSE 0 END
    ) AS inactive_inspector_rows,

    MIN(HIRE_DT) AS earliest_hire_date,
    MAX(HIRE_DT) AS latest_hire_date

FROM kream_project.silver_inspector_master
GROUP BY DEPT_NM
ORDER BY registered_inspector_rows DESC, DEPT_NM;