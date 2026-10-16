-- 작업 53-1: 저장 테이블 존재 여부 확인

SELECT COUNT(*) AS existing_tables
FROM information_schema.tables
WHERE table_schema = 'kream_project'
  AND table_name = 'asis_inspection_result_required_snapshot_v1';


-- 작업 53-2: 제공받은 검수 결과 사전 확인

SELECT
    DICT_ID,
    STD_CODE,
    STD_KOR_NM,
    BANNED_WORD_YN,
    FAKE_PENALTY_MULTIPLIER
FROM kream_project.silver_product_std_dict
WHERE CODE_TYPE = 'INSP_RESULT'
ORDER BY STD_CODE;


-- 작업 53-3: 검수 결과와 필수값 검사 결과 저장
-- 검수 결과는 원본 값과 사전 코드가 정확히 일치해야 함
-- PARENT_CAT_ID와 INSP_MEMO는 필수값 검사에서 제외
-- 결측 대체 문자열 검사는 기존 참조 및 수치 검사와 함께 적용

CREATE TABLE
    kream_project.asis_inspection_result_required_snapshot_v1
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin
AS
SELECT
    b.bronze_row_id,
    b.INSP_RESULT AS raw_insp_result,
    d.STD_CODE AS insp_result_candidate,
    d.FAKE_PENALTY_MULTIPLIER AS penalty_multiplier_candidate,

    CASE
        WHEN d.DICT_ID IS NULL
            THEN 'UNMAPPED_RESULT'
        WHEN d.BANNED_WORD_YN = 'N'
            THEN 'REGISTERED_RESULT'
        ELSE 'BANNED_OR_INVALID_RESULT'
    END AS result_check_status,

    CASE
        WHEN d.DICT_ID IS NOT NULL
         AND d.BANNED_WORD_YN = 'N'
        THEN 0 ELSE 1
    END AS result_error_flag,

    CASE
        WHEN NULLIF(TRIM(b.INSP_ID), '') IS NULL
          OR NULLIF(TRIM(b.REV_NO), '') IS NULL
          OR NULLIF(TRIM(b.ITEM_STD_CODE), '') IS NULL
          OR NULLIF(TRIM(b.ITEM_NM), '') IS NULL
          OR NULLIF(TRIM(b.TRADE_PRICE_KRW), '') IS NULL
          OR NULLIF(TRIM(b.INSP_DURATION_MIN), '') IS NULL
          OR NULLIF(TRIM(b.INSP_RESULT), '') IS NULL
          OR NULLIF(TRIM(b.INSPECTOR_EMP_NO), '') IS NULL
          OR NULLIF(TRIM(b.INBOUND_DT), '') IS NULL
          OR NULLIF(TRIM(b.INSP_DONE_DT), '') IS NULL
          OR NULLIF(TRIM(b.EXTRACTED_AT), '') IS NULL
        THEN 1 ELSE 0
    END AS required_value_missing_flag

FROM kream_project.bronze_inspection AS b

LEFT JOIN kream_project.silver_product_std_dict AS d
  ON d.CODE_TYPE = 'INSP_RESULT'
 AND HEX(d.STD_CODE) = HEX(b.INSP_RESULT);

SHOW WARNINGS;


-- 작업 53-4: 원천 행 기준 기본키 설정
-- 사전 조인으로 같은 원천 행이 늘어났으면 여기서 확인됨

ALTER TABLE
    kream_project.asis_inspection_result_required_snapshot_v1
    ADD PRIMARY KEY (bronze_row_id);


-- 작업 53-5: 저장 건수와 누락 확인

SELECT
    COUNT(*) AS saved_rows,
    COUNT(DISTINCT bronze_row_id) AS distinct_source_rows,
    SUM(result_error_flag) AS result_error_rows,
    SUM(required_value_missing_flag) AS required_value_missing_rows
FROM kream_project.asis_inspection_result_required_snapshot_v1;

SELECT
    COUNT(*) AS missing_saved_rows
FROM kream_project.bronze_inspection AS b
LEFT JOIN
    kream_project.asis_inspection_result_required_snapshot_v1 AS r
  ON r.bronze_row_id = b.bronze_row_id
WHERE r.bronze_row_id IS NULL;


-- 작업 53-6: 원본 검수 결과별 사전 등록 여부 확인

SELECT
    raw_insp_result,
    HEX(raw_insp_result) AS raw_result_hex,
    insp_result_candidate,
    result_check_status,
    penalty_multiplier_candidate,
    COUNT(*) AS source_rows
FROM kream_project.asis_inspection_result_required_snapshot_v1
GROUP BY
    raw_insp_result,
    HEX(raw_insp_result),
    insp_result_candidate,
    result_check_status,
    penalty_multiplier_candidate
ORDER BY
    result_check_status,
    raw_result_hex;