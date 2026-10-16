-- 작업 52-1: 새 테이블 존재 여부 확인

SELECT COUNT(*) AS existing_tables
FROM information_schema.tables
WHERE table_schema = 'kream_project'
  AND table_name IN (
      'asis_product_name_join_lookup_v1',
      'asis_inspection_validation_stage_v1'
  );


-- 작업 52-2: 제품명 검사 연결용 테이블 생성
-- 기존 제품명 검사 결과를 그대로 복사

CREATE TABLE kream_project.asis_product_name_join_lookup_v1
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin
AS
SELECT
    raw_item_code,
    raw_item_name,
    code_standard_name,
    name_check_status
FROM kream_project.asis_product_name_snapshot_v1;

SHOW WARNINGS;


-- 작업 52-3: 원본 제품 코드와 이름의 조회 인덱스 설정
-- 인덱스는 앞부분을 사용하지만 실제 조인은 전체 값을 비교

ALTER TABLE kream_project.asis_product_name_join_lookup_v1
    ADD INDEX ix_raw_product_name (
        raw_item_code(50),
        raw_item_name(150)
    );


-- 작업 52-4: 원천 행별 검사 결과 통합
-- LEFT JOIN으로 검사 결과가 없는 원천 행도 보존
-- 제품 코드와 이름은 원본 값으로 연결
-- 오류가 겹쳐도 각각의 검사 결과를 보존

CREATE TABLE kream_project.asis_inspection_validation_stage_v1
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin
AS
SELECT
    b.bronze_row_id,

    k.normalized_insp_id,
    k.normalized_rev_no,

    n.price_krw_candidate,
    n.duration_min_candidate,
    n.price_status,
    n.duration_status,

    d.inbound_dt_kst,
    d.insp_done_dt_kst,
    d.extracted_at_kst,

    e.effective_reference_id AS inspector_emp_no_candidate,
    e.final_reference_status AS employee_reference_status,

    c.effective_reference_id AS parent_cat_id_candidate,
    c.reference_origin AS category_reference_origin,
    c.final_reference_status AS category_reference_status,

    p.code_standard_name AS standard_item_name,
    p.name_check_status,

    g.rows_per_key AS revision_group_rows,
    g.raw_payload_versions AS revision_payload_versions,

    CASE
        WHEN k.bronze_row_id IS NULL
          OR n.bronze_row_id IS NULL
          OR d.bronze_row_id IS NULL
          OR e.bronze_row_id IS NULL
          OR c.bronze_row_id IS NULL
          OR p.name_check_status IS NULL
          OR g.normalized_insp_id IS NULL
        THEN 1 ELSE 0
    END AS missing_check_flag,

    CASE
        WHEN n.price_status = 'CONVERTED'
        THEN 0 ELSE 1
    END AS price_error_flag,

    CASE
        WHEN n.duration_status = 'CONVERTED'
        THEN 0 ELSE 1
    END AS duration_error_flag,

    CASE
        WHEN d.inbound_dt_kst IS NULL
          OR d.insp_done_dt_kst IS NULL
          OR d.extracted_at_kst IS NULL
        THEN 1 ELSE 0
    END AS datetime_missing_flag,

    CASE
        WHEN d.insp_done_dt_kst < d.inbound_dt_kst
        THEN 1 ELSE 0
    END AS done_before_inbound_flag,

    CASE
        WHEN d.extracted_at_kst < d.insp_done_dt_kst
        THEN 1 ELSE 0
    END AS extracted_before_done_flag,

    CASE
        WHEN e.final_reference_status = 'SILVER_MASTER_FOUND'
        THEN 0 ELSE 1
    END AS employee_reference_error_flag,

    CASE
        WHEN c.final_reference_status = 'SILVER_MASTER_FOUND'
        THEN 0 ELSE 1
    END AS category_reference_error_flag,

    CASE
        WHEN p.name_check_status IN (
            'STANDARD_NAME',
            'REGISTERED_ALIAS'
        )
        THEN 0 ELSE 1
    END AS product_name_error_flag,

    CASE
        WHEN g.raw_payload_versions > 1
        THEN 1 ELSE 0
    END AS revision_conflict_flag

FROM kream_project.bronze_inspection AS b

LEFT JOIN kream_project.asis_inspection_key_snapshot_v1 AS k
  ON k.bronze_row_id = b.bronze_row_id

LEFT JOIN kream_project.asis_inspection_numeric_snapshot_v1 AS n
  ON n.bronze_row_id = b.bronze_row_id

LEFT JOIN kream_project.asis_inspection_datetime_snapshot_v1 AS d
  ON d.bronze_row_id = b.bronze_row_id

LEFT JOIN kream_project.asis_final_reference_snapshot_v1 AS e
  ON e.bronze_row_id = b.bronze_row_id
 AND e.column_name = 'INSPECTOR_EMP_NO'

LEFT JOIN kream_project.asis_final_reference_snapshot_v1 AS c
  ON c.bronze_row_id = b.bronze_row_id
 AND c.column_name = 'PARENT_CAT_ID'

LEFT JOIN kream_project.asis_product_name_join_lookup_v1 AS p
  ON p.raw_item_code <=> b.ITEM_STD_CODE
 AND p.raw_item_name <=> b.ITEM_NM

LEFT JOIN kream_project.asis_revision_group_snapshot_v1 AS g
  ON g.normalized_insp_id = k.normalized_insp_id
 AND g.normalized_rev_no = k.normalized_rev_no;

SHOW WARNINGS;


-- 작업 52-5: 원천 행 기준 기본키 설정
-- 조인으로 같은 원천 행이 늘어났으면 여기서 확인됨

ALTER TABLE kream_project.asis_inspection_validation_stage_v1
    ADD PRIMARY KEY (bronze_row_id);


-- 작업 52-6: 통합 건수와 검사 누락 확인

SELECT
    COUNT(*) AS integrated_rows,
    COUNT(DISTINCT bronze_row_id) AS distinct_source_rows,
    SUM(missing_check_flag) AS missing_check_rows
FROM kream_project.asis_inspection_validation_stage_v1;


-- 작업 52-7: 기존 검사 건수와 비교
-- 아래 오류 건수는 서로 겹칠 수 있으므로 합산하지 않음

SELECT
    SUM(price_error_flag) AS price_error_rows,
    SUM(duration_error_flag) AS duration_error_rows,
    SUM(datetime_missing_flag) AS datetime_missing_rows,
    SUM(done_before_inbound_flag) AS done_before_inbound_rows,
    SUM(extracted_before_done_flag) AS extracted_before_done_rows,
    SUM(employee_reference_error_flag) AS employee_reference_error_rows,
    SUM(category_reference_error_flag) AS category_reference_error_rows,
    SUM(product_name_error_flag) AS product_name_error_rows,
    SUM(revision_conflict_flag) AS revision_conflict_rows
FROM kream_project.asis_inspection_validation_stage_v1;


-- 작업 52-8: 현재 연결한 검사 기준의 통과 여부 확인
-- 최종 Silver 건수가 아님

SELECT
    CASE
        WHEN missing_check_flag = 1
            THEN 'CHECK_MISSING'
        WHEN price_error_flag = 1
          OR duration_error_flag = 1
          OR datetime_missing_flag = 1
          OR done_before_inbound_flag = 1
          OR extracted_before_done_flag = 1
          OR employee_reference_error_flag = 1
          OR category_reference_error_flag = 1
          OR product_name_error_flag = 1
          OR revision_conflict_flag = 1
            THEN 'HAS_RULE_ERROR'
        ELSE 'PASSED_CONNECTED_CHECKS'
    END AS integrated_check_status,

    COUNT(*) AS source_rows

FROM kream_project.asis_inspection_validation_stage_v1
GROUP BY integrated_check_status
ORDER BY integrated_check_status;