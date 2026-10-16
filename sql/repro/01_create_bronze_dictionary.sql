-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 1. 프로젝트 데이터베이스 생성
CREATE DATABASE IF NOT EXISTS kream_project_repro
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_bin;

-- 2. 작업할 데이터베이스 선택
USE kream_project_repro;

-- 3. 표준 사전 원본 보존 테이블 생성
CREATE TABLE bronze_product_std_dict (
    bronze_row_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,

    DICT_ID                 TEXT,
    CODE_TYPE               TEXT,
    STD_CODE                TEXT,
    STD_KOR_NM              TEXT,
    SYNONYM_LIST            TEXT,
    BANNED_WORD_YN          TEXT,
    BASE_RETAIL_KRW         TEXT,
    FAKE_PENALTY_MULTIPLIER  TEXT,

    source_file VARCHAR(255) NOT NULL
        DEFAULT 'kream_product_std_dict.csv',

    PRIMARY KEY (bronze_row_id)
)
    ENGINE = InnoDB
    DEFAULT CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_bin;

-- 4. 테이블 구조 확인
SHOW COLUMNS FROM bronze_product_std_dict;

-- 5. 현재 적재 건수 확인
SELECT COUNT(*) AS loaded_rows
FROM bronze_product_std_dict;