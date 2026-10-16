-- 작업 39-0: Silver 사전 테이블 존재 여부 확인
-- 데이터 변경 없음

SELECT TABLE_NAME
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'kream_project'
  AND TABLE_NAME = 'silver_product_std_dict';

-- 작업 39-1: Silver 표준 사전 생성
-- 명세서의 자료형·길이·필수 여부 적용
-- 원본 행 번호로 Bronze 추적
-- Bronze 원본은 변경하지 않음

CREATE TABLE kream_project.silver_product_std_dict (
    DICT_ID VARCHAR(20) NOT NULL,
    CODE_TYPE VARCHAR(20) NOT NULL,
    STD_CODE VARCHAR(50) NOT NULL,
    STD_KOR_NM VARCHAR(150) NOT NULL,
    SYNONYM_LIST VARCHAR(1000) NULL,
    BANNED_WORD_YN CHAR(1) NOT NULL,
    BASE_RETAIL_KRW INT NOT NULL,
    FAKE_PENALTY_MULTIPLIER DECIMAL(3,1) NOT NULL,

    source_bronze_row_id BIGINT UNSIGNED NOT NULL,
    dictionary_version VARCHAR(32) NOT NULL,

    PRIMARY KEY (DICT_ID),
    UNIQUE KEY uq_dictionary_source (source_bronze_row_id),
    INDEX ix_dictionary_code (CODE_TYPE, STD_CODE),

    CONSTRAINT chk_silver_dictionary_type
        CHECK (
            CODE_TYPE IN (
                'ITEM_MODEL',
                'BANNED_WORD',
                'INSP_RESULT',
                'DEPT_STD',
                'BANNED_DEPT'
            )
        ),

    CONSTRAINT chk_silver_dictionary_banned
        CHECK (BANNED_WORD_YN IN ('Y', 'N')),

    CONSTRAINT chk_silver_dictionary_retail
        CHECK (BASE_RETAIL_KRW >= 0),

    CONSTRAINT chk_silver_dictionary_multiplier
        CHECK (FAKE_PENALTY_MULTIPLIER >= 0)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin;


-- 작업 39-2: 검증된 사전을 명시적으로 변환해 적재
-- 결측을 기본값으로 채우지 않음
-- 사전 버전은 이번 프로젝트에서 부여한 내부 버전

INSERT INTO kream_project.silver_product_std_dict (
    DICT_ID,
    CODE_TYPE,
    STD_CODE,
    STD_KOR_NM,
    SYNONYM_LIST,
    BANNED_WORD_YN,
    BASE_RETAIL_KRW,
    FAKE_PENALTY_MULTIPLIER,
    source_bronze_row_id,
    dictionary_version
)
SELECT
    DICT_ID,
    CODE_TYPE,
    STD_CODE,
    STD_KOR_NM,
    SYNONYM_LIST,
    BANNED_WORD_YN,
    CAST(BASE_RETAIL_KRW AS SIGNED),
    CAST(FAKE_PENALTY_MULTIPLIER AS DECIMAL(3,1)),
    bronze_row_id,
    '20261014_v1'
FROM kream_project.bronze_product_std_dict;

SHOW WARNINGS;


-- 작업 39-3: Bronze와 Silver 사전 건수 확인

SELECT
    'Bronze' AS layer_name,
    COUNT(*) AS row_count
FROM kream_project.bronze_product_std_dict

UNION ALL

SELECT
    'Silver',
    COUNT(*)
FROM kream_project.silver_product_std_dict;


-- 작업 39-4: 원본 행 연결과 전체 업무 컬럼 대조
-- 숫자는 의도한 자료형 변환 결과와 비교
-- 문자열은 원문 문자 기준으로 비교

SELECT
    COUNT(*) AS bronze_rows,

    SUM(
        CASE WHEN s.source_bronze_row_id IS NULL
             THEN 1 ELSE 0 END
    ) AS missing_silver_rows,

    SUM(
        CASE
            WHEN s.source_bronze_row_id IS NOT NULL
             AND (
                 NOT (HEX(b.DICT_ID) <=> HEX(s.DICT_ID))
                 OR NOT (HEX(b.CODE_TYPE) <=> HEX(s.CODE_TYPE))
                 OR NOT (HEX(b.STD_CODE) <=> HEX(s.STD_CODE))
                 OR NOT (HEX(b.STD_KOR_NM) <=> HEX(s.STD_KOR_NM))
                 OR NOT (
                     HEX(b.SYNONYM_LIST) <=> HEX(s.SYNONYM_LIST)
                 )
                 OR NOT (
                     HEX(b.BANNED_WORD_YN)
                     <=> HEX(s.BANNED_WORD_YN)
                 )
                 OR NOT (
                     CAST(b.BASE_RETAIL_KRW AS SIGNED)
                     <=> s.BASE_RETAIL_KRW
                 )
                 OR NOT (
                     CAST(b.FAKE_PENALTY_MULTIPLIER AS DECIMAL(3,1))
                     <=> s.FAKE_PENALTY_MULTIPLIER
                 )
             )
            THEN 1 ELSE 0
        END
    ) AS unexpected_value_difference_rows

FROM kream_project.bronze_product_std_dict AS b
LEFT JOIN kream_project.silver_product_std_dict AS s
  ON s.source_bronze_row_id = b.bronze_row_id;