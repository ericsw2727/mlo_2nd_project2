-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 54-1: 분류 후보 테이블 존재 여부 확인

SELECT COUNT(*) AS existing_tables
FROM information_schema.tables
WHERE table_schema = 'kream_project_repro'
  AND table_name = 'asis_inspection_disposition_stage_v1';


-- 작업 54-2: 검사 결과와 개정 선택을 연결하여 분류 후보 생성
-- 검사 누락은 품질 오류와 구분하여 별도로 표시
-- 정상 행끼리만 중복과 최신 유효 개정을 판단
-- 동일 내용 중복의 대표 행은 가장 작은 원천 행 번호로 선택

CREATE TABLE kream_project_repro.asis_inspection_disposition_stage_v1
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin
AS
WITH checked AS (
    SELECT
        s.*,
        r.raw_insp_result,
        r.insp_result_candidate,
        r.penalty_multiplier_candidate,
        r.result_check_status,
        r.result_error_flag,
        r.required_value_missing_flag,

        CASE
            WHEN s.missing_check_flag = 1
              OR r.bronze_row_id IS NULL
            THEN 1 ELSE 0
        END AS integrated_missing_check_flag,

        CASE
            WHEN s.normalized_insp_id IS NULL
              OR s.normalized_rev_no IS NULL
              OR s.normalized_rev_no < 1
            THEN 1 ELSE 0
        END AS inspection_key_error_flag,

        CASE
            WHEN s.price_error_flag = 1
              OR s.duration_error_flag = 1
              OR s.datetime_missing_flag = 1
              OR s.done_before_inbound_flag = 1
              OR s.extracted_before_done_flag = 1
              OR s.employee_reference_error_flag = 1
              OR s.category_reference_error_flag = 1
              OR s.product_name_error_flag = 1
              OR s.revision_conflict_flag = 1
              OR r.result_error_flag = 1
              OR r.required_value_missing_flag = 1
              OR s.normalized_insp_id IS NULL
              OR s.normalized_rev_no IS NULL
              OR s.normalized_rev_no < 1
            THEN 1 ELSE 0
        END AS record_error_flag

    FROM kream_project_repro.asis_inspection_validation_stage_v1 AS s

    LEFT JOIN
        kream_project_repro.asis_inspection_result_required_snapshot_v1 AS r
      ON r.bronze_row_id = s.bronze_row_id
),
valid_ranked AS (
    SELECT
        bronze_row_id,

        ROW_NUMBER() OVER (
            PARTITION BY
                normalized_insp_id,
                normalized_rev_no
            ORDER BY bronze_row_id
        ) AS valid_occurrence_no,

        MAX(normalized_rev_no) OVER (
            PARTITION BY normalized_insp_id
        ) AS latest_valid_rev_no

    FROM checked
    WHERE integrated_missing_check_flag = 0
      AND record_error_flag = 0
)
SELECT
    c.*,
    v.valid_occurrence_no,
    v.latest_valid_rev_no,

    CASE
        WHEN c.integrated_missing_check_flag = 1
            THEN 'CHECK_MISSING'
        WHEN c.record_error_flag = 1
            THEN 'QUARANTINE'
        WHEN v.valid_occurrence_no > 1
            THEN 'EXCLUDED'
        WHEN c.normalized_rev_no < v.latest_valid_rev_no
            THEN 'EXCLUDED'
        ELSE 'SILVER_CANDIDATE'
    END AS disposition,

    CASE
        WHEN c.integrated_missing_check_flag = 1
            THEN 'CHECK_RESULT_MISSING'
        WHEN c.record_error_flag = 1
            THEN 'QUALITY_RULE_VIOLATION'
        WHEN v.valid_occurrence_no > 1
            THEN 'IDENTICAL_DUPLICATE'
        WHEN c.normalized_rev_no < v.latest_valid_rev_no
            THEN 'SUPERSEDED_VALID_REVISION'
        ELSE 'LATEST_VALID_REVISION'
    END AS primary_reason,

    '20261014_v1' AS rule_version

FROM checked AS c
LEFT JOIN valid_ranked AS v
  ON v.bronze_row_id = c.bronze_row_id;

SHOW WARNINGS;


-- 작업 54-3: 원천 행 기준 기본키 설정

ALTER TABLE kream_project_repro.asis_inspection_disposition_stage_v1
    ADD PRIMARY KEY (bronze_row_id);


-- 작업 54-4: 분류 건수와 검사 상태 확인

SELECT
    COUNT(*) AS classified_rows,
    COUNT(DISTINCT bronze_row_id) AS distinct_source_rows,
    SUM(integrated_missing_check_flag) AS missing_check_rows,
    SUM(inspection_key_error_flag) AS inspection_key_error_rows,

    SUM(
        CASE
            WHEN required_value_missing_flag = 1
             AND employee_reference_error_flag = 0
            THEN 1 ELSE 0
        END
    ) AS required_missing_without_employee_error_rows

FROM kream_project_repro.asis_inspection_disposition_stage_v1;


-- 작업 54-5: 분류별 건수 확인

SELECT
    disposition,
    primary_reason,
    COUNT(*) AS source_rows
FROM kream_project_repro.asis_inspection_disposition_stage_v1
GROUP BY
    disposition,
    primary_reason
ORDER BY
    disposition,
    primary_reason;


-- 작업 54-6: Silver 후보에 오류나 잘못된 개정 선택이 있는지 확인
-- 세 오류 값 모두 0이어야 함
-- 후보 행 수와 서로 다른 검수 ID 수가 같아야 함

SELECT
    COUNT(*) AS silver_candidate_rows,
    COUNT(DISTINCT normalized_insp_id) AS distinct_inspection_ids,

    SUM(
        CASE WHEN record_error_flag = 1
             THEN 1 ELSE 0 END
    ) AS candidate_with_rule_error_rows,

    SUM(
        CASE WHEN integrated_missing_check_flag = 1
             THEN 1 ELSE 0 END
    ) AS candidate_with_missing_check_rows,

    SUM(
        CASE
            WHEN normalized_rev_no <> latest_valid_rev_no
              OR valid_occurrence_no <> 1
            THEN 1 ELSE 0
        END
    ) AS incorrect_revision_selection_rows

FROM kream_project_repro.asis_inspection_disposition_stage_v1
WHERE disposition = 'SILVER_CANDIDATE';


-- 작업 54-7: Bronze 원천 대비 누락과 추가 행 확인
-- 두 값 모두 0이어야 함

SELECT
    (
        SELECT COUNT(*)
        FROM kream_project_repro.bronze_inspection AS b
        LEFT JOIN
            kream_project_repro.asis_inspection_disposition_stage_v1 AS s
          ON s.bronze_row_id = b.bronze_row_id
        WHERE s.bronze_row_id IS NULL
    ) AS missing_classified_rows,

    (
        SELECT COUNT(*)
        FROM kream_project_repro.asis_inspection_disposition_stage_v1 AS s
        LEFT JOIN kream_project_repro.bronze_inspection AS b
          ON b.bronze_row_id = s.bronze_row_id
        WHERE b.bronze_row_id IS NULL
    ) AS unknown_source_rows;