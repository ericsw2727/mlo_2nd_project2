-- 작업 06-1: 공급 팀의 조인 결과 원본 테이블 생성
-- 목적: 공급된 조인·파생값을 보존하고 이후 재조인 결과와 비교
-- 근거:
-- 1. 조인 결과를 무조건 정답으로 취급하지 않음
-- 2. 원본 18개 컬럼을 TEXT로 보존
-- 3. 중복·개정 이력·충돌도 원본에서 보존
-- 4. 검수 원본과 별도 테이블로 관리

CREATE TABLE kream_project.bronze_inspection_join_ready (
    bronze_row_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,

    INSP_ID                 TEXT,
    REV_NO                  TEXT,
    ITEM_STD_CODE           TEXT,
    ITEM_NM                 TEXT,
    PARENT_CAT_ID           TEXT,
    PARENT_CAT_NM           TEXT,
    TRADE_PRICE_KRW         TEXT,
    INSP_DURATION_MIN       TEXT,
    INSP_RESULT             TEXT,
    COMPENSATION_LOSS_KRW    TEXT,
    INSPECTOR_EMP_NO        TEXT,
    INSPECTOR_EMP_NM        TEXT,
    INSPECTOR_DEPT_NM       TEXT,
    INSPECTOR_POSITION_NM   TEXT,
    INBOUND_DT              TEXT,
    INSP_DONE_DT            TEXT,
    EXTRACTED_AT            TEXT,
    INSP_MEMO               TEXT,

    source_file VARCHAR(255) NOT NULL
        DEFAULT 'kream_inspection_join_ready.csv',

    PRIMARY KEY (bronze_row_id)
)
    ENGINE = InnoDB
    DEFAULT CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_bin;

-- 구조 확인: 원본 18개 + 관리 2개 = 총 20개 컬럼
SHOW COLUMNS FROM kream_project.bronze_inspection_join_ready;

-- 적재 전 상태 확인: 예상 0행
SELECT COUNT(*) AS rows_before_load
FROM kream_project.bronze_inspection_join_ready;


-- 작업 06-2: 공급 팀의 조인 결과 원본 CSV 적재
-- 확인된 상태: 테이블 생성 완료, 적재 전 0행
-- 목적: 조인·파생값을 원본 그대로 보존하여 이후 검증에 사용
-- 근거:
-- 1. CSV 순서에 맞춰 원본 18개 컬럼을 명시적으로 연결
-- 2. UTF-8 및 원본의 CRLF 줄바꿈 사용
-- 3. 헤더만 제외하며 보정·계산·중복 제거는 하지 않음

LOAD DATA INFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_inspection_join_ready.csv'
INTO TABLE kream_project.bronze_inspection_join_ready
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
    INSPECTOR_EMP_NO,
    INSPECTOR_EMP_NM,
    INSPECTOR_DEPT_NM,
    INSPECTOR_POSITION_NM,
    INBOUND_DT,
    INSP_DONE_DT,
    EXTRACTED_AT,
    INSP_MEMO
);

-- 적재 직후 경고 확인
SHOW WARNINGS;

-- 작업 06-3: 적재 건수와 원문 기준 고유 검수 ID 확인
SELECT
    COUNT(*) AS loaded_rows,
    COUNT(DISTINCT INSP_ID) AS distinct_inspection_ids
FROM kream_project.bronze_inspection_join_ready;

-- 작업 06-4: 추가된 조인·파생 컬럼 미리보기
SELECT
    bronze_row_id,
    INSP_ID,
    REV_NO,
    PARENT_CAT_ID,
    PARENT_CAT_NM,
    COMPENSATION_LOSS_KRW,
    INSPECTOR_EMP_NO,
    INSPECTOR_EMP_NM,
    INSPECTOR_DEPT_NM,
    INSPECTOR_POSITION_NM,
    source_file
FROM kream_project.bronze_inspection_join_ready
ORDER BY bronze_row_id
LIMIT 5;