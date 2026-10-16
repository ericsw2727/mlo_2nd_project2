-- 작업 03-1: 카테고리 원본 보존 테이블 생성
-- 이유:
-- 1. 날짜·코드 오류도 원본 그대로 받기 위해 TEXT 사용
-- 2. CAT_ID 중복을 검사해야 하므로 원본 컬럼에 UNIQUE를 걸지 않음
-- 3. 적재 행 식별자와 출처 파일명을 별도로 기록

USE kream_project;

CREATE TABLE bronze_category_parent_lookup (
    bronze_row_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,

    CAT_ID     TEXT,
    CAT_NM     TEXT,
    CAT_LEVEL  TEXT,
    REG_DT     TEXT,

    source_file VARCHAR(255) NOT NULL
        DEFAULT 'kream_category_parent_lookup.csv',

    PRIMARY KEY (bronze_row_id)
)
    ENGINE = InnoDB
    DEFAULT CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_bin;

-- 적재 전 상태 확인: 예상 0행
SELECT COUNT(*) AS rows_before_load
FROM bronze_category_parent_lookup;

-- 작업 03-2: 카테고리 CSV 원본 적재
-- 이유: 원본 4개 컬럼을 명시적으로 연결하고 헤더만 제외
-- 원본 파일에서 확인한 CRLF 줄바꿈 사용

LOAD DATA INFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_category_parent_lookup.csv'
INTO TABLE bronze_category_parent_lookup
CHARACTER SET utf8mb4
FIELDS
    TERMINATED BY ','
    OPTIONALLY ENCLOSED BY '"'
    ESCAPED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(
    CAT_ID,
    CAT_NM,
    CAT_LEVEL,
    REG_DT
);

-- 적재 직후 경고 확인
SHOW WARNINGS;

-- 작업 03-3: 물리 행 수와 원문 기준 고유 ID 수 대조
SELECT
    COUNT(*) AS loaded_rows,
    COUNT(DISTINCT CAT_ID) AS distinct_category_ids
FROM bronze_category_parent_lookup;

-- 작업 03-4: 원본값과 출처 확인
SELECT
    bronze_row_id,
    CAT_ID,
    CAT_NM,
    CAT_LEVEL,
    REG_DT,
    source_file
FROM bronze_category_parent_lookup
ORDER BY bronze_row_id
LIMIT 5;

-- 작업 03-5: 테이블 중복 생성 오류 후 현재 적재 상태 확인
-- 이유: 적재 재실행으로 원본이 중복 입력되는 것을 방지

SELECT
    COUNT(*) AS loaded_rows,
    COUNT(DISTINCT CAT_ID) AS distinct_category_ids
FROM kream_project.bronze_category_parent_lookup;

-- 작업 03-6: 비어 있는 카테고리 원본 테이블에 CSV 적재
-- 확인된 상태: 테이블 존재, 적재 건수 0행
-- 목적: 원본 1,050행을 정제 없이 보존

LOAD DATA INFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_category_parent_lookup.csv'
INTO TABLE kream_project.bronze_category_parent_lookup
CHARACTER SET utf8mb4
FIELDS
    TERMINATED BY ','
    OPTIONALLY ENCLOSED BY '"'
    ESCAPED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(
    CAT_ID,
    CAT_NM,
    CAT_LEVEL,
    REG_DT
);

-- 적재 직후 경고 확인
SHOW WARNINGS;

-- 원본 건수와 대조
SELECT
    COUNT(*) AS loaded_rows,
    COUNT(DISTINCT CAT_ID) AS distinct_category_ids
FROM kream_project.bronze_category_parent_lookup;

-- 원본값과 출처 미리보기
SELECT *
FROM kream_project.bronze_category_parent_lookup
ORDER BY bronze_row_id
LIMIT 5;