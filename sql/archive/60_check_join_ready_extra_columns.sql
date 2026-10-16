-- 작업 60-1: 검사 결과 테이블 존재 여부 확인

SELECT COUNT(*) AS existing_tables
FROM information_schema.tables
WHERE table_schema = 'kream_project'
  AND table_name = 'asis_join_extra_column_check_v1';


-- 작업 60-2: 조인 통합본의 추가 컬럼 검사 결과 저장
-- 정상, 격리, 제외를 포함한 전체 원천 행 검사
-- 마스터를 사용할 수 없는 행은 정상으로 간주하지 않음

CREATE TABLE kream_project.asis_join_extra_column_check_v1
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin
AS
SELECT
    p.inspection_bronze_row_id,
    p.join_ready_bronze_row_id,
    s.disposition,

    j.PARENT_CAT_NM AS raw_category_name,
    j.INSPECTOR_EMP_NM AS raw_employee_name,
    j.INSPECTOR_DEPT_NM AS raw_department_name,
    j.INSPECTOR_POSITION_NM AS raw_position_name,
    j.COMPENSATION_LOSS_KRW AS raw_compensation_loss,

    c.CAT_NM AS expected_category_name,
    i.EMP_NM AS expected_employee_name,
    i.DEPT_NM AS expected_department_name,
    i.POSITION_NM AS expected_position_name,

    CASE
        WHEN s.insp_result_candidate IS NULL
            THEN NULL
        WHEN s.insp_result_candidate = 'CLAIM_FAKE_PASS'
            THEN
                CASE
                    WHEN s.price_status = 'CONVERTED'
                    THEN s.price_krw_candidate * 3
                    ELSE NULL
                END
        ELSE 0
    END AS expected_compensation_loss,

    CASE
        WHEN j.bronze_row_id IS NULL
          OR s.bronze_row_id IS NULL
        THEN 1 ELSE 0
    END AS missing_input_flag,

    CASE
        WHEN c.CAT_ID IS NULL
            THEN 'MASTER_NOT_AVAILABLE'
        WHEN HEX(j.PARENT_CAT_NM) <=> HEX(c.CAT_NM)
            THEN 'EXACT_MATCH'
        ELSE 'DIFFERENT_VALUE_REVIEW'
    END AS category_name_check_status,

    CASE
        WHEN i.EMP_NO IS NULL
            THEN 'MASTER_NOT_AVAILABLE'
        WHEN HEX(j.INSPECTOR_EMP_NM) <=> HEX(i.EMP_NM)
            THEN 'EXACT_MATCH'
        WHEN HEX(j.INSPECTOR_EMP_NM) <=> HEX(m.EMP_NM)
            THEN 'STANDARDIZATION_REQUIRED'
        ELSE 'DIFFERENT_VALUE_REVIEW'
    END AS employee_name_check_status,

    CASE
        WHEN i.EMP_NO IS NULL
            THEN 'MASTER_NOT_AVAILABLE'
        WHEN HEX(j.INSPECTOR_DEPT_NM) <=> HEX(i.DEPT_NM)
            THEN 'EXACT_MATCH'
        WHEN HEX(j.INSPECTOR_DEPT_NM) <=> HEX(m.DEPT_NM)
            THEN 'STANDARDIZATION_REQUIRED'
        ELSE 'DIFFERENT_VALUE_REVIEW'
    END AS department_name_check_status,

    CASE
        WHEN i.EMP_NO IS NULL
            THEN 'MASTER_NOT_AVAILABLE'
        WHEN HEX(j.INSPECTOR_POSITION_NM) <=> HEX(i.POSITION_NM)
            THEN 'EXACT_MATCH'
        WHEN HEX(j.INSPECTOR_POSITION_NM) <=> HEX(m.POSITION_NM)
            THEN 'STANDARDIZATION_REQUIRED'
        ELSE 'DIFFERENT_VALUE_REVIEW'
    END AS position_name_check_status,

    CASE
        WHEN j.COMPENSATION_LOSS_KRW IS NULL
          OR TRIM(j.COMPENSATION_LOSS_KRW) = ''
            THEN 'MISSING_VALUE'

        WHEN UPPER(TRIM(j.COMPENSATION_LOSS_KRW))
             IN ('NULL', 'NA', 'N/A')
            THEN 'MISSING_TOKEN'

        WHEN REGEXP_LIKE(
            TRIM(j.COMPENSATION_LOSS_KRW),
            '^[-+]?[0-9]+([.][0-9]+)?$',
            'c'
        )
            THEN 'PLAIN_NUMBER'

        WHEN REGEXP_LIKE(
            TRIM(j.COMPENSATION_LOSS_KRW),
            '^[-+]?[0-9]{1,3}(,[0-9]{3})+([.][0-9]+)?$',
            'c'
        )
            THEN 'GROUPED_NUMBER'

        ELSE 'UNSUPPORTED_FORMAT'
    END AS compensation_format_status

FROM kream_project.asis_inspection_join_row_pair_v1 AS p

LEFT JOIN kream_project.bronze_inspection_join_ready AS j
  ON j.bronze_row_id = p.join_ready_bronze_row_id

LEFT JOIN kream_project.asis_inspection_disposition_stage_v2 AS s
  ON s.bronze_row_id = p.inspection_bronze_row_id

LEFT JOIN kream_project.silver_inspector_master AS i
  ON i.EMP_NO = s.inspector_emp_no_candidate

LEFT JOIN kream_project.bronze_inspector_master AS m
  ON m.bronze_row_id = i.source_bronze_row_id

LEFT JOIN kream_project.silver_category_parent_lookup AS c
  ON c.CAT_ID = s.parent_cat_id_candidate;

SHOW WARNINGS;


-- 작업 60-3: 양쪽 원천 행의 중복 연결 방지

ALTER TABLE kream_project.asis_join_extra_column_check_v1
    ADD PRIMARY KEY (inspection_bronze_row_id),
    ADD UNIQUE KEY uq_extra_check_join_row (
        join_ready_bronze_row_id
    );


-- 작업 60-4: 검사 건수와 입력 누락 확인

SELECT
    COUNT(*) AS checked_rows,
    COUNT(DISTINCT inspection_bronze_row_id)
        AS distinct_inspection_rows,
    COUNT(DISTINCT join_ready_bronze_row_id)
        AS distinct_join_ready_rows,
    SUM(missing_input_flag) AS missing_input_rows
FROM kream_project.asis_join_extra_column_check_v1;


-- 작업 60-5: 문자 컬럼별 검사 결과 집계

SELECT
    'PARENT_CAT_NM' AS column_name,
    category_name_check_status AS check_status,
    COUNT(*) AS source_rows
FROM kream_project.asis_join_extra_column_check_v1
GROUP BY category_name_check_status

UNION ALL

SELECT
    'INSPECTOR_EMP_NM',
    employee_name_check_status,
    COUNT(*)
FROM kream_project.asis_join_extra_column_check_v1
GROUP BY employee_name_check_status

UNION ALL

SELECT
    'INSPECTOR_DEPT_NM',
    department_name_check_status,
    COUNT(*)
FROM kream_project.asis_join_extra_column_check_v1
GROUP BY department_name_check_status

UNION ALL

SELECT
    'INSPECTOR_POSITION_NM',
    position_name_check_status,
    COUNT(*)
FROM kream_project.asis_join_extra_column_check_v1
GROUP BY position_name_check_status

ORDER BY column_name, check_status;


-- 작업 60-6: 원본 배상금의 문자 형식 확인
-- 현재 단계에서는 강제로 숫자로 변환하지 않음

SELECT
    compensation_format_status,
    COUNT(*) AS source_rows
FROM kream_project.asis_join_extra_column_check_v1
GROUP BY compensation_format_status
ORDER BY compensation_format_status;


-- 작업 60-7: 지원되지 않는 배상금 형식의 실제 값 확인
-- 해당 값이 없으면 결과 행 없이 컬럼만 표시됨

SELECT
    raw_compensation_loss,
    HEX(raw_compensation_loss) AS raw_value_hex,
    COUNT(*) AS source_rows
FROM kream_project.asis_join_extra_column_check_v1
WHERE compensation_format_status = 'UNSUPPORTED_FORMAT'
GROUP BY
    raw_compensation_loss,
    HEX(raw_compensation_loss)
ORDER BY source_rows DESC
LIMIT 20;