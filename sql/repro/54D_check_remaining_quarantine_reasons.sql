-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 54D-1: 격리된 마스터 참조와 다른 오류를 구분
-- 정상 판정은 품질 검사 기준이며 최종 정상 데이터 건수가 아님

WITH checked AS (
    SELECT
        bronze_row_id,

        CASE
            WHEN employee_reference_status = 'MASTER_QUARANTINED'
            THEN 1 ELSE 0
        END AS quarantined_employee_flag,

        CASE
            WHEN category_reference_status = 'MASTER_QUARANTINED'
            THEN 1 ELSE 0
        END AS quarantined_category_flag,

        CASE
            WHEN integrated_missing_check_flag = 1
              OR inspection_key_error_flag = 1
              OR price_error_flag = 1
              OR duration_error_flag = 1
              OR datetime_missing_flag = 1
              OR done_before_inbound_flag = 1
              OR extracted_before_done_flag = 1
              OR revision_conflict_flag = 1
              OR result_error_flag = 1
              OR required_value_missing_flag = 1
              OR product_name_error_flag = 1

              OR (
                  employee_reference_error_flag = 1
                  AND COALESCE(employee_reference_status, '')
                      <> 'MASTER_QUARANTINED'
              )

              OR (
                  category_reference_error_flag = 1
                  AND COALESCE(category_reference_status, '')
                      <> 'MASTER_QUARANTINED'
              )

            THEN 1 ELSE 0
        END AS other_rule_error_flag

    FROM kream_project_repro.asis_inspection_disposition_stage_v2
)
SELECT
    CASE
        WHEN other_rule_error_flag = 1
            THEN 'OTHER_RULE_ERROR'
        WHEN quarantined_employee_flag = 1
          OR quarantined_category_flag = 1
            THEN 'QUARANTINED_MASTER_ONLY'
        ELSE 'PASSED_QUALITY_CHECKS'
    END AS quarantine_reason_group,

    COUNT(*) AS source_rows

FROM checked
GROUP BY quarantine_reason_group
ORDER BY quarantine_reason_group;


-- 작업 54D-2: 격리된 카테고리별 검수 참조 건수 확인
-- 마스터를 ID별로 묶어 중복 조인을 방지
-- 원본 계층 값은 수정하지 않음

WITH category_reasons AS (
    SELECT
        q.normalized_cat_id,

        MAX(b.CAT_NM) AS category_name,

        GROUP_CONCAT(
            DISTINCT b.CAT_LEVEL
            ORDER BY b.CAT_LEVEL
            SEPARATOR ', '
        ) AS raw_category_levels

    FROM kream_project_repro.quarantine_category_parent_lookup AS q

    JOIN kream_project_repro.bronze_category_parent_lookup AS b
      ON b.bronze_row_id = q.source_bronze_row_id

    GROUP BY q.normalized_cat_id
)
SELECT
    m.normalized_cat_id,
    m.category_name,
    m.raw_category_levels,
    COUNT(*) AS referenced_inspection_rows

FROM kream_project_repro.asis_inspection_disposition_stage_v2 AS s

JOIN category_reasons AS m
  ON m.normalized_cat_id = s.parent_cat_id_candidate

WHERE s.category_reference_status = 'MASTER_QUARANTINED'

GROUP BY
    m.normalized_cat_id,
    m.category_name,
    m.raw_category_levels

ORDER BY
    referenced_inspection_rows DESC,
    m.normalized_cat_id;


-- 작업 54D-3: 격리된 검수원의 원본 부서와 격리 사유 확인
-- 사번별로 묶어 마스터 중복 때문에 건수가 늘어나지 않도록 처리

WITH employee_reasons AS (
    SELECT
        q.normalized_emp_no,

        GROUP_CONCAT(
            DISTINCT b.DEPT_NM
            ORDER BY b.DEPT_NM
            SEPARATOR ', '
        ) AS raw_department_names,

        GROUP_CONCAT(
            DISTINCT q.primary_reason
            ORDER BY q.primary_reason
            SEPARATOR ', '
        ) AS master_quarantine_reasons

    FROM kream_project_repro.quarantine_inspector_master AS q

    JOIN kream_project_repro.bronze_inspector_master AS b
      ON b.bronze_row_id = q.source_bronze_row_id

    GROUP BY q.normalized_emp_no
)
SELECT
    m.raw_department_names,
    m.master_quarantine_reasons,
    COUNT(DISTINCT m.normalized_emp_no) AS referenced_employee_ids,
    COUNT(*) AS referenced_inspection_rows

FROM kream_project_repro.asis_inspection_disposition_stage_v2 AS s

JOIN employee_reasons AS m
  ON m.normalized_emp_no = s.inspector_emp_no_candidate

WHERE s.employee_reference_status = 'MASTER_QUARANTINED'

GROUP BY
    m.raw_department_names,
    m.master_quarantine_reasons

ORDER BY referenced_inspection_rows DESC;