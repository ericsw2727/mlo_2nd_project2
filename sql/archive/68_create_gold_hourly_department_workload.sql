-- 작업 68-1: 시간대별 작업량 테이블 존재 여부 확인

SELECT COUNT(*) AS existing_tables
FROM information_schema.tables
WHERE table_schema = 'kream_project'
  AND table_name = 'gold_inspection_workload_hourly_v1';


-- 작업 68-2: 날짜, 시간대, 부서, 검수 종류별 집계 테이블 생성

CREATE TABLE kream_project.gold_inspection_workload_hourly_v1 (
    done_date_kst DATE NOT NULL,
    done_hour_kst TINYINT UNSIGNED NOT NULL,
    department_name VARCHAR(100) NOT NULL,
    event_type VARCHAR(20) NOT NULL,
    analysis_period VARCHAR(40) NOT NULL,
    inspection_event_rows BIGINT UNSIGNED NOT NULL,
    observed_inspector_ids BIGINT UNSIGNED NOT NULL,
    total_work_minutes DECIMAL(20,8) NOT NULL,
    avg_work_minutes DECIMAL(12,4) NOT NULL,
    department_basis VARCHAR(40) NOT NULL,
    rule_version VARCHAR(32) NOT NULL,

    PRIMARY KEY (
        done_date_kst,
        done_hour_kst,
        department_name,
        event_type
    ),

    CONSTRAINT ck_gold_workload_hour
        CHECK (done_hour_kst BETWEEN 0 AND 23)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin;


-- 작업 68-3: 유효 검수 기록의 시간대별 작업량 저장
-- 부서는 현재 정규 마스터 기준으로 연결
-- 마스터 누락 시 필수값 제약으로 확인되도록 LEFT JOIN 사용

INSERT INTO kream_project.gold_inspection_workload_hourly_v1 (
    done_date_kst,
    done_hour_kst,
    department_name,
    event_type,
    analysis_period,
    inspection_event_rows,
    observed_inspector_ids,
    total_work_minutes,
    avg_work_minutes,
    department_basis,
    rule_version
)
WITH event_base AS (
    SELECT
        DATE(s.insp_done_dt_kst) AS done_date_kst,
        HOUR(s.insp_done_dt_kst) AS done_hour_kst,
        i.DEPT_NM AS department_name,
        s.inspector_emp_no_candidate,
        s.duration_min_candidate,

        CASE
            WHEN s.normalized_rev_no = 1
                THEN 'FIRST_INSPECTION'
            ELSE 'REINSPECTION'
        END AS event_type,

        CASE
            WHEN DATE(s.insp_done_dt_kst) < '2022-01-01'
                THEN 'ISOLATED_EARLY_PERIOD'
            WHEN DATE(s.insp_done_dt_kst) >= '2026-10-01'
                THEN 'REINSPECTION_BATCH_PERIOD'
            WHEN DATE(s.insp_done_dt_kst) >= '2026-09-01'
                THEN 'PARTIAL_BOUNDARY_MONTH'
            ELSE 'CONTINUOUS_PERIOD'
        END AS analysis_period

    FROM kream_project.asis_inspection_disposition_stage_v2 AS s

    LEFT JOIN kream_project.silver_inspector_master AS i
      ON i.EMP_NO = s.inspector_emp_no_candidate

    WHERE s.integrated_missing_check_flag = 0
      AND s.record_error_flag = 0
      AND s.valid_occurrence_no = 1
)
SELECT
    done_date_kst,
    done_hour_kst,
    department_name,
    event_type,
    analysis_period,
    COUNT(*),
    COUNT(DISTINCT inspector_emp_no_candidate),
    SUM(duration_min_candidate),
    ROUND(AVG(duration_min_candidate), 4),
    'CURRENT_MASTER',
    '20261014_v2'

FROM event_base
GROUP BY
    done_date_kst,
    done_hour_kst,
    department_name,
    event_type,
    analysis_period;

SHOW WARNINGS;


-- 작업 68-4: 시간대 집계의 전체 건수와 시간 합계 확인

SELECT
    COUNT(*) AS saved_group_rows,
    SUM(inspection_event_rows) AS represented_event_rows,
    SUM(total_work_minutes) AS total_work_minutes
FROM kream_project.gold_inspection_workload_hourly_v1;


-- 작업 68-5: 일별 집계와 시간대 집계 대조
-- 검사 그룹 수 외의 네 값은 모두 0이어야 함

WITH hourly_rollup AS (
    SELECT
        done_date_kst,
        event_type,
        SUM(inspection_event_rows) AS event_rows,
        SUM(total_work_minutes) AS work_minutes
    FROM kream_project.gold_inspection_workload_hourly_v1
    GROUP BY
        done_date_kst,
        event_type
)
SELECT
    COUNT(*) AS checked_daily_groups,

    SUM(
        CASE WHEN h.done_date_kst IS NULL
             THEN 1 ELSE 0 END
    ) AS missing_hourly_groups,

    SUM(
        CASE
            WHEN h.done_date_kst IS NOT NULL
             AND d.inspection_event_rows <> h.event_rows
            THEN 1 ELSE 0
        END
    ) AS different_count_groups,

    SUM(
        CASE
            WHEN h.done_date_kst IS NOT NULL
             AND d.total_work_minutes <> h.work_minutes
            THEN 1 ELSE 0
        END
    ) AS different_work_minutes_groups,

    (
        SELECT COUNT(*)
        FROM hourly_rollup AS x

        LEFT JOIN kream_project.gold_inspection_workload_daily_v1 AS original
          ON original.done_date_kst = x.done_date_kst
         AND original.event_type = x.event_type

        WHERE original.done_date_kst IS NULL
    ) AS unexpected_hourly_groups

FROM kream_project.gold_inspection_workload_daily_v1 AS d

LEFT JOIN hourly_rollup AS h
  ON h.done_date_kst = d.done_date_kst
 AND h.event_type = d.event_type;


-- 작업 68-6: 연속 관측 기간의 최초 검수 완료 시간대 비교
-- 재검수와 별도 확인 구간은 이 비교에서 분리
-- 평균은 해당 기간의 전체 관측 일수로 계산

SELECT
    done_hour_kst,
    SUM(inspection_event_rows) AS inspection_event_rows,
    SUM(total_work_minutes) AS total_work_minutes,

    ROUND(
        SUM(inspection_event_rows) /
        (
            SELECT COUNT(*)
            FROM kream_project.gold_inspection_workload_daily_v1
            WHERE analysis_period = 'CONTINUOUS_PERIOD'
              AND event_type = 'FIRST_INSPECTION'
        ),
        4
    ) AS avg_events_per_observed_day

FROM kream_project.gold_inspection_workload_hourly_v1

WHERE analysis_period = 'CONTINUOUS_PERIOD'
  AND event_type = 'FIRST_INSPECTION'

GROUP BY done_hour_kst
ORDER BY inspection_event_rows DESC, done_hour_kst;


-- 작업 68-7: 연속 관측 기간의 부서별 최초 검수 작업량

SELECT
    department_name,
    SUM(inspection_event_rows) AS inspection_event_rows,
    SUM(total_work_minutes) AS total_work_minutes,

    ROUND(
        SUM(total_work_minutes)
            / SUM(inspection_event_rows),
        4
    ) AS avg_work_minutes

FROM kream_project.gold_inspection_workload_hourly_v1

WHERE analysis_period = 'CONTINUOUS_PERIOD'
  AND event_type = 'FIRST_INSPECTION'

GROUP BY department_name
ORDER BY total_work_minutes DESC, department_name;


-- 작업 68-8: 재검수 완료 시간대와 작업량 확인

SELECT
    done_date_kst,
    done_hour_kst,
    SUM(inspection_event_rows) AS reinspection_rows,
    SUM(total_work_minutes) AS total_work_minutes

FROM kream_project.gold_inspection_workload_hourly_v1
WHERE event_type = 'REINSPECTION'

GROUP BY
    done_date_kst,
    done_hour_kst

ORDER BY
    done_date_kst,
    done_hour_kst;