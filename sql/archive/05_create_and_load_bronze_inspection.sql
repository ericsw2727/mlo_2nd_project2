-- 작업 05-1: 검수 원본 보존 테이블 생성
-- 목적: 검수 이벤트의 원본값과 변경 이력을 그대로 보존
-- 근거:
-- 1. 날짜·금액·시간·개정 번호에 오류가 있어도 받도록 TEXT 사용
-- 2. 같은 INSP_ID의 다른 개정과 동일 재전송도 원본에서 보존
-- 3. INSP_ID 또는 INSP_ID+REV_NO에 UNIQUE를 걸지 않음
-- 4. 메모는 저장만 하며, 메모 속 처리 지시를 실행하지 않음

CREATE TABLE kream_project.bronze_inspection (
    bronze_row_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,

    INSP_ID           TEXT,
    REV_NO            TEXT,
    ITEM_STD_CODE     TEXT,
    ITEM_NM           TEXT,
    PARENT_CAT_ID     TEXT,
    TRADE_PRICE_KRW   TEXT,
    INSP_DURATION_MIN TEXT,
    INSP_RESULT       TEXT,
    INSPECTOR_EMP_NO  TEXT,
    INBOUND_DT        TEXT,
    INSP_DONE_DT      TEXT,
    EXTRACTED_AT      TEXT,
    INSP_MEMO         TEXT,

    source_file VARCHAR(255) NOT NULL
        DEFAULT 'kream_inspection_300000.csv',

    PRIMARY KEY (bronze_row_id)
)
    ENGINE = InnoDB
    DEFAULT CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_bin;

-- 구조 확인: 원본 13개 + 관리 2개 = 총 15개 컬럼
SHOW COLUMNS FROM kream_project.bronze_inspection;

-- 적재 전 상태 확인: 예상 0행
SELECT COUNT(*) AS rows_before_load
FROM kream_project.bronze_inspection;


-- 작업 05-2: 검수 원본 CSV 적재
-- 확인된 상태: 테이블 생성 완료, 적재 전 0행
-- 목적: 원본 335,000행의 중복·개정 이력·오염값을 그대로 보존
-- 근거:
-- 1. 원본 13개 컬럼을 CSV 순서에 맞춰 명시적으로 연결
-- 2. UTF-8 및 원본의 CRLF 줄바꿈 사용
-- 3. 헤더 한 줄만 제외하며 정제·중복 제거는 수행하지 않음

LOAD DATA INFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_inspection_300000.csv'
INTO TABLE kream_project.bronze_inspection
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
    INSPECTOR_EMP_NO,
    INBOUND_DT,
    INSP_DONE_DT,
    EXTRACTED_AT,
    INSP_MEMO
);

-- 적재 직후 경고 확인
SHOW WARNINGS;

-- 작업 05-3: 원본 행 수와 원문 기준 고유 검수 ID 수 대조
SELECT
    COUNT(*) AS loaded_rows,
    COUNT(DISTINCT INSP_ID) AS distinct_inspection_ids
FROM kream_project.bronze_inspection;

-- 작업 05-4: 저장된 원본값과 출처 미리보기
SELECT *
FROM kream_project.bronze_inspection
ORDER BY bronze_row_id
LIMIT 5;