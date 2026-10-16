-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 02: 표준 사전 원본 CSV 적재
-- 단계 1: CSV 적재 허용 폴더 확인
SELECT @@secure_file_priv AS import_allowed_directory;

-- 작업 02-1: 적재 전 상태 확인
-- 목적: 이미 적재한 데이터를 다시 넣지 않도록 건수 확인
USE kream_project_repro;

SELECT COUNT(*) AS rows_before_load
FROM bronze_product_std_dict;

-- 작업 02-2: 표준 사전 원본 CSV 적재
-- 근거:
-- 1. secure_file_priv에서 확인한 허용 폴더 사용
-- 2. 원본 CSV는 UTF-8이며 줄바꿈은 CRLF
-- 3. 첫 줄은 헤더이므로 제외
-- 4. CSV의 원본 8개 컬럼만 명시적으로 연결
-- 5. 원본값을 정제하거나 숫자로 변환하지 않음

LOAD DATA INFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_product_std_dict.csv'
INTO TABLE bronze_product_std_dict
CHARACTER SET utf8mb4
FIELDS
    TERMINATED BY ','
    OPTIONALLY ENCLOSED BY '"'
    ESCAPED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(
    DICT_ID,
    CODE_TYPE,
    STD_CODE,
    STD_KOR_NM,
    SYNONYM_LIST,
    BANNED_WORD_YN,
    BASE_RETAIL_KRW,
    FAKE_PENALTY_MULTIPLIER
);

-- 적재 직후 경고 확인
SHOW WARNINGS;

-- 작업 02-3: 적재 건수와 사전 식별자 수 확인
SELECT
    COUNT(*) AS loaded_rows,
    COUNT(DISTINCT DICT_ID) AS distinct_dict_ids
FROM bronze_product_std_dict;

-- 작업 02-4: 한글·동의어·숫자 원문·출처 확인
SELECT
    bronze_row_id,
    DICT_ID,
    CODE_TYPE,
    STD_KOR_NM,
    SYNONYM_LIST,
    BASE_RETAIL_KRW,
    FAKE_PENALTY_MULTIPLIER,
    source_file
FROM bronze_product_std_dict
ORDER BY bronze_row_id
LIMIT 5;