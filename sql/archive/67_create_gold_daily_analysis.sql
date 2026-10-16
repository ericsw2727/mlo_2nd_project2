-- 작업 67-1: 분석 테이블 존재 여부 확인

SELECT COUNT(*) AS existing_tables
FROM information_schema.tables
WHERE table_schema = 'kream_project'
  AND table_name IN (
      'gold_inspection_result_daily_v1',
      'gold_inspection_workload_daily_v1'
  );


-- 작업 67-2: 주문별 최종 결과의 일별 분석 테이블 생성

CREATE TABLE kream_project.gold_inspection_result_daily_v1 (
    done_date_kst DATE NOT NULL,
    analysis_period VARCHAR(40) NOT NULL,
    inspection_rows BIGINT UNSIGNED NOT NULL,
    pass_rows BIGINT UNSIGNED NOT NULL,
    fake_reject_rows BIGINT UNSIGNED NOT NULL,
    box_damage_hold_rows BIGINT UNSIGNED NOT NULL,
    fake_pass_claim_rows BIGINT UNSIGNED NOT NULL,
    total_trade_price_krw DECIMAL(24,4) NOT NULL,
    compensation_loss_krw DECIMAL(24,4) NOT NULL,
    rule_version VARCHAR(32) NOT NULL,

    PRIMARY KEY (done_date_kst)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin;


-- 작업 67-3: 최종 정상 상태의 일별 결과 저장
-- 분석 구간 표시는 이번 데이터에서 확인한 날짜 분포 기준
-- 표시 때문에 원본이나 정제 결과를 제외하지 않음

INSERT INTO kream_project.gold_inspection_result_daily_v1 (
    done_date_kst,
    analysis_period,
    inspection_rows,
    pass_rows,
    fake_reject_rows,
    box_damage_hold_rows,
    fake_pass_claim_rows,
    total_trade_price_krw,
    compensation_loss_krw,
    rule_version
)
WITH result_base AS (
    SELECT
        DATE(INSP_DONE_DT) AS done_date_kst,
        INSP_RESULT,
        TRADE_PRICE_KRW,
        COMPENSATION_LOSS_KRW,

        CASE
            WHEN DATE(INSP_DONE_DT) < '2022-01-01'
                THEN 'ISOLATED_EARLY_PERIOD'
            WHEN DATE(INSP_DONE_DT) >= '2026-10-01'
                THEN 'REINSPECTION_BATCH_PERIOD'
            WHEN DATE(INSP_DONE_DT) >= '2026-09-01'
                THEN 'PARTIAL_BOUNDARY_MONTH'
            ELSE 'CONTINUOUS_PERIOD'
        END AS analysis_period

    FROM kream_project.silver_inspection_join_ready
)
SELECT
    done_date_kst,
    analysis_period,
    COUNT(*),

    SUM(
        CASE WHEN INSP_RESULT = 'PASS'
             THEN 1 ELSE 0 END
    ),

    SUM(
        CASE WHEN INSP_RESULT = 'FAKE_REJECT'
             THEN 1 ELSE 0 END
    ),

    SUM(
        CASE WHEN INSP_RESULT = 'BOX_DMG_HOLD'
             THEN 1 ELSE 0 END
    ),

    SUM(
        CASE WHEN INSP_RESULT = 'CLAIM_FAKE_PASS'
             THEN 1 ELSE 0 END
    ),

    SUM(TRADE_PRICE_KRW),
    SUM(COMPENSATION_LOSS_KRW),
    '20261014_v2'

FROM result_base
GROUP BY
    done_date_kst,
    analysis_period;

SHOW WARNINGS;


-- 작업 67-4: 유효 검수 기록의 일별 작업량 테이블 생성

CREATE TABLE kream_project.gold_inspection_workload_daily_v1 (
    done_date_kst DATE NOT NULL,
    event_type VARCHAR(20) NOT NULL,
    analysis_period VARCHAR(40) NOT NULL,
    inspection_event_rows BIGINT UNSIGNED NOT NULL,
    observed_inspector_ids BIGINT UNSIGNED NOT NULL,
    total_work_minutes DECIMAL(20,8) NOT NULL,
    avg_work_minutes DECIMAL(12,4) NOT NULL,
    rule_version VARCHAR(32) NOT NULL,

    PRIMARY KEY (done_date_kst, event_type)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin;


-- 작업 67-5: 최초 검수와 재검수의 일별 작업량 저장
-- 정상 이전 개정도 실제 검수 기록으로 포함
-- 동일 중복과 품질 오류 행은 제외
-- 평균만 소수 4자리로 표시하며 원본 시간과 합계는 보존

INSERT INTO kream_project.gold_inspection_workload_daily_v1 (
    done_date_kst,
    event_type,
    analysis_period,
    inspection_event_rows,
    observed_inspector_ids,
    total_work_minutes,
    avg_work_minutes,
    rule_version
)
WITH event_base AS (
    SELECT
        DATE(insp_done_dt_kst) AS done_date_kst,
        inspector_emp_no_candidate,
        duration_min_candidate,

        CASE
            WHEN normalized_rev_no = 1
                THEN 'FIRST_INSPECTION'
            ELSE 'REINSPECTION'
        END AS event_type,

        CASE
            WHEN DATE(insp_done_dt_kst) < '2022-01-01'
                THEN 'ISOLATED_EARLY_PERIOD'
            WHEN DATE(insp_done_dt_kst) >= '2026-10-01'
                THEN 'REINSPECTION_BATCH_PERIOD'
            WHEN DATE(insp_done_dt_kst) >= '2026-09-01'
                THEN 'PARTIAL_BOUNDARY_MONTH'
            ELSE 'CONTINUOUS_PERIOD'
        END AS analysis_period

    FROM kream_project.asis_inspection_disposition_stage_v2

    WHERE integrated_missing_check_flag = 0
      AND record_error_flag = 0
      AND valid_occurrence_no = 1
)
SELECT
    done_date_kst,
    event_type,
    analysis_period,
    COUNT(*),
    COUNT(DISTINCT inspector_emp_no_candidate),
    SUM(duration_min_candidate),
    ROUND(AVG(duration_min_candidate), 4),
    '20261014_v2'

FROM event_base
GROUP BY
    done_date_kst,
    event_type,
    analysis_period;

SHOW WARNINGS;


-- 작업 67-6: 최종 결과 집계 건수와 배상금 확인
-- result_count_difference는 0이어야 함

SELECT
    COUNT(*) AS saved_daily_rows,
    SUM(inspection_rows) AS represented_inspection_rows,
    SUM(pass_rows) AS pass_rows,
    SUM(fake_reject_rows) AS fake_reject_rows,
    SUM(box_damage_hold_rows) AS box_damage_hold_rows,
    SUM(fake_pass_claim_rows) AS fake_pass_claim_rows,
    SUM(compensation_loss_krw) AS compensation_loss_krw,

    SUM(inspection_rows)
        - SUM(
            pass_rows
            + fake_reject_rows
            + box_damage_hold_rows
            + fake_pass_claim_rows
        ) AS result_count_difference

FROM kream_project.gold_inspection_result_daily_v1;


-- 작업 67-7: 검수 종류별 작업량 확인
-- 두 종류의 검수 기록 합계는 291548이어야 함

SELECT
    event_type,
    SUM(inspection_event_rows) AS inspection_event_rows,
    SUM(total_work_minutes) AS total_work_minutes
FROM kream_project.gold_inspection_workload_daily_v1
GROUP BY event_type
ORDER BY event_type;


-- 작업 67-8: 원천 분석 대상과 저장된 집계의 합계 대조
-- 각 기준의 건수와 금액 또는 시간 합계가 같아야 함

SELECT
    'FINAL_RESULT' AS analysis_scope,
    'COMPENSATION_KRW' AS total_value_unit,

    (
        SELECT COUNT(*)
        FROM kream_project.silver_inspection_join_ready
    ) AS source_rows,

    (
        SELECT SUM(inspection_rows)
        FROM kream_project.gold_inspection_result_daily_v1
    ) AS represented_rows,

    (
        SELECT SUM(COMPENSATION_LOSS_KRW)
        FROM kream_project.silver_inspection_join_ready
    ) AS source_total_value,

    (
        SELECT SUM(compensation_loss_krw)
        FROM kream_project.gold_inspection_result_daily_v1
    ) AS saved_total_value

UNION ALL

SELECT
    'VALID_WORKLOAD',
    'WORK_MINUTES',

    (
        SELECT COUNT(*)
        FROM kream_project.asis_inspection_disposition_stage_v2
        WHERE integrated_missing_check_flag = 0
          AND record_error_flag = 0
          AND valid_occurrence_no = 1
    ),

    (
        SELECT SUM(inspection_event_rows)
        FROM kream_project.gold_inspection_workload_daily_v1
    ),

    (
        SELECT SUM(duration_min_candidate)
        FROM kream_project.asis_inspection_disposition_stage_v2
        WHERE integrated_missing_check_flag = 0
          AND record_error_flag = 0
          AND valid_occurrence_no = 1
    ),

    (
        SELECT SUM(total_work_minutes)
        FROM kream_project.gold_inspection_workload_daily_v1
    );


-- 작업 67-9: 분석 구간별 검수 작업량 확인

SELECT
    analysis_period,
    event_type,
    MIN(done_date_kst) AS first_date,
    MAX(done_date_kst) AS last_date,
    COUNT(*) AS observed_days,
    SUM(inspection_event_rows) AS inspection_event_rows
FROM kream_project.gold_inspection_workload_daily_v1
GROUP BY
    analysis_period,
    event_type
ORDER BY
    first_date,
    event_type;