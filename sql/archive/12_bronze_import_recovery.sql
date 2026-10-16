-- 작업 12-1: 복구용 테이블 생성
-- 목적: 기존 조인 결과 테이블은 보존하고,
-- 원본 CSV를 다시 적재할 빈 테이블 생성
-- LIKE는 구조만 복사하며 데이터는 복사하지 않음

CREATE TABLE kream_project.bronze_inspection_join_ready_reloaded
LIKE kream_project.bronze_inspection_join_ready;

-- 복구용 테이블이 비어 있는지 확인
SELECT COUNT(*) AS recovery_rows_before_load
FROM kream_project.bronze_inspection_join_ready_reloaded;


-- 작업 12-2: 조인 결과 원본을 복구용 테이블에 적재
-- 목적:
-- 1. 원본 CSV의 335,000행을 별도 테이블에 적재
-- 2. 사번의 문자열 'NULL'을 원문 그대로 보존
--
-- 근거:
-- 첨부 원본 CSV의 INSPECTOR_EMP_NO에 문자열 'NULL'이 400행 있음
-- 이 파일의 해당 컬럼에 한하여 적재 해석을 되돌림
-- 직원 사번을 추측하거나 정상값으로 채우는 정제가 아님

LOAD DATA INFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_inspection_join_ready.csv'
INTO TABLE kream_project.bronze_inspection_join_ready_reloaded
CHARACTER SET utf8mb4
FIELDS
    TERMINATED BY ','
    OPTIONALLY ENCLOSED BY '"'
    ESCAPED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(
    INSP_ID,
    REV_NO,
    ITEM_STD_CODE,
    ITEM_NM,
    PARENT_CAT_ID,
    PARENT_CAT_NM,
    TRADE_PRICE_KRW,
    INSP_DURATION_MIN,
    INSP_RESULT,
    COMPENSATION_LOSS_KRW,
    @raw_inspector_emp_no,
    INSPECTOR_EMP_NM,
    INSPECTOR_DEPT_NM,
    INSPECTOR_POSITION_NM,
    INBOUND_DT,
    INSP_DONE_DT,
    EXTRACTED_AT,
    INSP_MEMO
)
SET INSPECTOR_EMP_NO = COALESCE(@raw_inspector_emp_no, 'NULL');

-- 적재 직후 경고 확인
SHOW WARNINGS;


-- 작업 12-3: 복구용 테이블의 적재 건수 확인
SELECT
    COUNT(*) AS loaded_rows,
    COUNT(DISTINCT INSP_ID) AS distinct_inspection_ids
FROM kream_project.bronze_inspection_join_ready_reloaded;


-- 작업 12-4: 사번의 원본 결측 표기가 보존됐는지 확인
SELECT
    SUM(
        CASE WHEN INSPECTOR_EMP_NO IS NULL
             THEN 1 ELSE 0 END
    ) AS sql_null_rows,

    SUM(
        CASE WHEN INSPECTOR_EMP_NO = 'NULL'
             THEN 1 ELSE 0 END
    ) AS literal_null_text_rows,

    SUM(
        CASE WHEN INSPECTOR_EMP_NO = ''
             THEN 1 ELSE 0 END
    ) AS empty_string_rows,

    SUM(
        CASE WHEN INSPECTOR_EMP_NO = 'NA'
             THEN 1 ELSE 0 END
    ) AS literal_na_rows
FROM kream_project.bronze_inspection_join_ready_reloaded;


-- 작업 12-5: 조인 결과 복구 테이블을 작업용 이름으로 전환
-- 목적:
-- 기존 670,000행은 복구 전 증빙으로 보존
-- 새로 적재한 335,000행을 이후 분석 대상으로 사용

RENAME TABLE
    kream_project.bronze_inspection_join_ready
        TO kream_project.bronze_inspection_join_ready_before_recovery,
    kream_project.bronze_inspection_join_ready_reloaded
        TO kream_project.bronze_inspection_join_ready;


-- 작업 12-6: 전환 후 작업용·보관용 건수 확인
SELECT
    '작업용' AS table_role,
    COUNT(*) AS row_count,
    SUM(
        CASE WHEN INSPECTOR_EMP_NO IS NULL
             THEN 1 ELSE 0 END
    ) AS sql_null_rows,
    SUM(
        CASE WHEN INSPECTOR_EMP_NO = 'NULL'
             THEN 1 ELSE 0 END
    ) AS literal_null_text_rows
FROM kream_project.bronze_inspection_join_ready

UNION ALL

SELECT
    '복구 전 보관용',
    COUNT(*),
    SUM(
        CASE WHEN INSPECTOR_EMP_NO IS NULL
             THEN 1 ELSE 0 END
    ),
    SUM(
        CASE WHEN INSPECTOR_EMP_NO = 'NULL'
             THEN 1 ELSE 0 END
    )
FROM kream_project.bronze_inspection_join_ready_before_recovery;


-- 작업 12-7: 검수 원본의 복구용 빈 테이블 생성
-- 목적: 기존 검수 원본은 보존하고,
-- 문자열 NULL을 유지하며 다시 적재할 공간 마련
-- LIKE는 구조만 복사하고 데이터는 복사하지 않음

CREATE TABLE kream_project.bronze_inspection_reloaded
LIKE kream_project.bronze_inspection;

-- 작업 12-8: 복구용 테이블 초기 상태 확인
-- 예상 결과: 0행

SELECT COUNT(*) AS recovery_rows_before_load
FROM kream_project.bronze_inspection_reloaded;


-- 작업 12-9: 검수 원본 CSV를 복구용 테이블에 적재
-- 목적: 원본 335,000행과 사번의 문자열 'NULL' 보존
-- 근거: 이번 원본 CSV에 문자열 'NULL'인 사번이 400행 존재
-- 기존 테이블은 변경하지 않으며 오염 정제도 수행하지 않음

LOAD DATA INFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_inspection_300000.csv'
INTO TABLE kream_project.bronze_inspection_reloaded
CHARACTER SET utf8mb4
FIELDS
    TERMINATED BY ','
    OPTIONALLY ENCLOSED BY '"'
    ESCAPED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(
    INSP_ID,
    REV_NO,
    ITEM_STD_CODE,
    ITEM_NM,
    PARENT_CAT_ID,
    TRADE_PRICE_KRW,
    INSP_DURATION_MIN,
    INSP_RESULT,
    @raw_inspector_emp_no,
    INBOUND_DT,
    INSP_DONE_DT,
    EXTRACTED_AT,
    INSP_MEMO
)
SET INSPECTOR_EMP_NO = COALESCE(@raw_inspector_emp_no, 'NULL');

-- 적재 직후 경고 확인
SHOW WARNINGS;


-- 작업 12-10: 복구용 검수 원본의 건수 확인
SELECT
    COUNT(*) AS loaded_rows,
    COUNT(DISTINCT INSP_ID) AS distinct_inspection_ids
FROM kream_project.bronze_inspection_reloaded;


-- 작업 12-11: 담당 사번의 결측 원문 보존 확인
SELECT
    SUM(
        CASE WHEN INSPECTOR_EMP_NO IS NULL
             THEN 1 ELSE 0 END
    ) AS sql_null_rows,

    SUM(
        CASE WHEN INSPECTOR_EMP_NO = 'NULL'
             THEN 1 ELSE 0 END
    ) AS literal_null_text_rows,

    SUM(
        CASE WHEN INSPECTOR_EMP_NO = ''
             THEN 1 ELSE 0 END
    ) AS empty_string_rows,

    SUM(
        CASE WHEN INSPECTOR_EMP_NO = 'NA'
             THEN 1 ELSE 0 END
    ) AS literal_na_rows
FROM kream_project.bronze_inspection_reloaded;


-- 작업 12-12: 검수 원본 전환 전 테이블 이름 확인
-- 목적: 기존 작업용·복구용·보관용 테이블의 존재 여부 확인
-- 데이터와 테이블 이름은 변경하지 않음

SELECT TABLE_NAME
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'kream_project'
  AND TABLE_NAME IN (
      'bronze_inspection',
      'bronze_inspection_reloaded',
      'bronze_inspection_before_recovery'
  )
ORDER BY TABLE_NAME;

-- 작업 12-13: 기존 테이블 보관 및 복구 테이블 전환
RENAME TABLE
    kream_project.bronze_inspection
        TO kream_project.bronze_inspection_before_recovery,
    kream_project.bronze_inspection_reloaded
        TO kream_project.bronze_inspection;

-- 작업 12-14: 전환 후 건수 확인
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT INSP_ID) AS distinct_insp_id
FROM kream_project.bronze_inspection;

-- 작업 12-15: 전환 후 담당 사번의 원본 표기 확인
SELECT
    SUM(CASE WHEN INSPECTOR_EMP_NO IS NULL
             THEN 1 ELSE 0 END) AS sql_null_rows,
    SUM(CASE WHEN INSPECTOR_EMP_NO = 'NULL'
             THEN 1 ELSE 0 END) AS literal_null_text_rows,
    SUM(CASE WHEN INSPECTOR_EMP_NO = ''
             THEN 1 ELSE 0 END) AS empty_string_rows,
    SUM(CASE WHEN INSPECTOR_EMP_NO = 'NA'
             THEN 1 ELSE 0 END) AS literal_na_rows
FROM kream_project.bronze_inspection;