-- 작업 04-1: 검수원 마스터 원본 테이블 생성
-- 목적: 사번·부서·입사일·재직 코드의 원본값 보존
-- 근거:
-- 1. 날짜와 코드 형식이 혼재하므로 원본 컬럼은 TEXT 사용
-- 2. 중복 사번도 받아야 하므로 EMP_NO에 UNIQUE를 걸지 않음
-- 3. 원본 행 식별자와 출처 파일명을 별도로 기록

CREATE TABLE kream_project.bronze_inspector_master (
    bronze_row_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,

    EMP_NO       TEXT,
    EMP_NM       TEXT,
    DEPT_NM      TEXT,
    POSITION_NM  TEXT,
    HIRE_DT      TEXT,
    ACTIVE_YN    TEXT,

    source_file VARCHAR(255) NOT NULL
        DEFAULT 'kream_inspector_master.csv',

    PRIMARY KEY (bronze_row_id)
)
    ENGINE = InnoDB
    DEFAULT CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_bin;

-- 구조 확인: 원본 6개 + 관리 2개 = 총 8개 컬럼
SHOW COLUMNS FROM kream_project.bronze_inspector_master;

-- 적재 전 상태 확인: 예상 0행
SELECT COUNT(*) AS rows_before_load
FROM kream_project.bronze_inspector_master;


-- 작업 04-2: 검수원 마스터 원본 CSV 적재
-- 확인된 상태: 테이블 생성 완료, 적재 전 0행
-- 목적: 중복·표기 차이·날짜·재직 코드를 정제하지 않고 보존
-- 근거: 원본 6개 컬럼 연결, UTF-8 및 CRLF 사용, 헤더 제외

LOAD DATA INFILE
    'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_inspector_master.csv'
INTO TABLE kream_project.bronze_inspector_master
CHARACTER SET utf8mb4
FIELDS
    TERMINATED BY ','
    OPTIONALLY ENCLOSED BY '"'
    ESCAPED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(
    EMP_NO,
    EMP_NM,
    DEPT_NM,
    POSITION_NM,
    HIRE_DT,
    ACTIVE_YN
);

-- 적재 직후 경고 확인
SHOW WARNINGS;

-- 작업 04-3: 원본 행 수와 원문 기준 고유 사번 수 대조
SELECT
    COUNT(*) AS loaded_rows,
    COUNT(DISTINCT EMP_NO) AS distinct_employee_ids
FROM kream_project.bronze_inspector_master;

-- 작업 04-4: 한글·날짜·재직 코드·출처 미리보기
SELECT *
FROM kream_project.bronze_inspector_master
ORDER BY bronze_row_id
LIMIT 5;