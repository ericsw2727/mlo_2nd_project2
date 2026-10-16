-- 작업 54A-1: 현재 격리 행에서 세 추가 항목의 중첩 확인
-- 세 값이 모두 0인 그룹은 다른 오류로 격리된 행

SELECT
    CASE
        WHEN name_check_status = 'UNMAPPED_NAME_REVIEW'
        THEN 1 ELSE 0
    END AS unmapped_product_name_flag,

    CASE
        WHEN employee_reference_status = 'MASTER_QUARANTINED'
        THEN 1 ELSE 0
    END AS quarantined_employee_reference_flag,

    CASE
        WHEN category_reference_status = 'MASTER_QUARANTINED'
        THEN 1 ELSE 0
    END AS quarantined_category_reference_flag,

    COUNT(*) AS quarantine_rows

FROM kream_project.asis_inspection_disposition_stage_v1
WHERE disposition = 'QUARANTINE'

GROUP BY
    unmapped_product_name_flag,
    quarantined_employee_reference_flag,
    quarantined_category_reference_flag

ORDER BY
    unmapped_product_name_flag,
    quarantined_employee_reference_flag,
    quarantined_category_reference_flag;


-- 작업 54A-2: 세 항목을 제외한 비교용 분류 계산
-- 실제 분류와 저장 데이터는 변경하지 않음
-- 금지 코드, 결측, 유령 참조, 시간 오류, 개정 충돌 등은 유지
-- 정상 개정 선택도 비교 기준에 맞춰 다시 계산

WITH diagnostic_checked AS (
    SELECT
        bronze_row_id,
        normalized_insp_id,
        normalized_rev_no,

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

              OR (
                  product_name_error_flag = 1
                  AND COALESCE(name_check_status, '')
                      <> 'UNMAPPED_NAME_REVIEW'
              )

            THEN 1 ELSE 0
        END AS diagnostic_error_flag

    FROM kream_project.asis_inspection_disposition_stage_v1
),
diagnostic_valid AS (
    SELECT
        bronze_row_id,

        ROW_NUMBER() OVER (
            PARTITION BY
                normalized_insp_id,
                normalized_rev_no
            ORDER BY bronze_row_id
        ) AS occurrence_no,

        MAX(normalized_rev_no) OVER (
            PARTITION BY normalized_insp_id
        ) AS latest_valid_rev_no

    FROM diagnostic_checked
    WHERE diagnostic_error_flag = 0
),
diagnostic_classified AS (
    SELECT
        c.bronze_row_id,

        CASE
            WHEN c.diagnostic_error_flag = 1
                THEN 'QUARANTINE'
            WHEN v.occurrence_no > 1
                THEN 'EXCLUDED'
            WHEN c.normalized_rev_no < v.latest_valid_rev_no
                THEN 'EXCLUDED'
            ELSE 'SILVER_CANDIDATE'
        END AS diagnostic_disposition

    FROM diagnostic_checked AS c
    LEFT JOIN diagnostic_valid AS v
      ON v.bronze_row_id = c.bronze_row_id
),
counts AS (
    SELECT
        diagnostic_disposition,
        COUNT(*) AS diagnostic_rows
    FROM diagnostic_classified
    GROUP BY diagnostic_disposition
),
expected_counts AS (
    SELECT
        'SILVER_CANDIDATE' AS diagnostic_disposition,
        280800 AS supplier_expected_rows

    UNION ALL

    SELECT 'EXCLUDED', 32600

    UNION ALL

    SELECT 'QUARANTINE', 21600
)
SELECT
    e.diagnostic_disposition,
    e.supplier_expected_rows,
    COALESCE(c.diagnostic_rows, 0) AS diagnostic_rows,

    COALESCE(c.diagnostic_rows, 0)
        - e.supplier_expected_rows AS difference_rows

FROM expected_counts AS e
LEFT JOIN counts AS c
  ON c.diagnostic_disposition = e.diagnostic_disposition
ORDER BY e.diagnostic_disposition;


-- 작업 54A-3: 미매핑 제품명의 주요 사례 확인
-- 건수가 많은 15개 조합부터 확인

SELECT
    raw_item_code,
    raw_item_name,
    code_standard_name,
    source_rows
FROM kream_project.asis_product_name_snapshot_v1
WHERE name_check_status = 'UNMAPPED_NAME_REVIEW'
ORDER BY
    source_rows DESC,
    raw_code_hex,
    raw_name_hex
LIMIT 15;


-- 작업 54A-4: 제공된 상품명 동의어 원문 확인
-- 미매핑 이름이 사전 해석 과정에서 누락됐는지 대조

SELECT
    STD_CODE,
    STD_KOR_NM,
    SYNONYM_LIST
FROM kream_project.silver_product_std_dict
WHERE CODE_TYPE = 'ITEM_MODEL'
ORDER BY STD_CODE;


-- 작업 54A-5: 격리된 카테고리의 원본 계층 값 확인

SELECT
    b.CAT_LEVEL AS raw_cat_level,
    COUNT(*) AS quarantine_master_rows,

    GROUP_CONCAT(
        DISTINCT b.CAT_ID
        ORDER BY b.CAT_ID
        SEPARATOR ', '
    ) AS raw_category_ids

FROM kream_project.quarantine_category_parent_lookup AS q
JOIN kream_project.bronze_category_parent_lookup AS b
  ON b.bronze_row_id = q.source_bronze_row_id

GROUP BY
    b.CAT_LEVEL,
    HEX(b.CAT_LEVEL)

ORDER BY quarantine_master_rows DESC;