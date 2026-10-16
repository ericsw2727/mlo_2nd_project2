-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 27-1: 상품 코드의 원문 기준 사전 참조 검사
-- ITEM_MODEL 유형의 사전만 연결
-- 공백·대소문자 보정 전의 정확한 원문 비교
-- 동일 상품 코드가 사전에 여러 행이면 별도 검토
-- 원본 수정 없음

CREATE OR REPLACE VIEW
    kream_project_repro.asis_product_code_reference_check_v1 AS
WITH source_codes AS (
    SELECT
        ITEM_STD_CODE AS raw_item_code,
        HEX(ITEM_STD_CODE) AS raw_code_hex,
        COUNT(*) AS source_rows
    FROM kream_project_repro.bronze_inspection
    GROUP BY ITEM_STD_CODE, HEX(ITEM_STD_CODE)
),
dictionary_codes AS (
    SELECT
        HEX(STD_CODE) AS dictionary_code_hex,
        COUNT(*) AS dictionary_rows,
        MIN(STD_KOR_NM) AS sample_standard_name
    FROM kream_project_repro.bronze_product_std_dict
    WHERE CODE_TYPE = 'ITEM_MODEL'
    GROUP BY HEX(STD_CODE)
)
SELECT
    s.raw_item_code,
    s.raw_code_hex,
    s.source_rows,
    COALESCE(d.dictionary_rows, 0) AS dictionary_rows,

    CASE
        WHEN d.dictionary_rows = 1
        THEN d.sample_standard_name
        ELSE NULL
    END AS standard_item_name,

    CASE
        WHEN COALESCE(LOWER(TRIM(s.raw_item_code)), '') IN (
            '', 'null', 'none', 'na', 'n/a', 'nan', '-'
        )
        THEN 'MISSING_CODE'

        WHEN d.dictionary_code_hex IS NULL
        THEN 'CODE_NOT_FOUND'

        WHEN d.dictionary_rows > 1
        THEN 'DICTIONARY_CODE_REVIEW'

        ELSE 'CODE_FOUND'
    END AS reference_status

FROM source_codes AS s
LEFT JOIN dictionary_codes AS d
  ON d.dictionary_code_hex = s.raw_code_hex;


-- 작업 27-2: 상품 코드 참조 상태별 건수
-- source_rows 합계는 335,000이어야 함

SELECT
    reference_status,
    COUNT(*) AS raw_code_groups,
    SUM(source_rows) AS source_rows
FROM kream_project_repro.asis_product_code_reference_check_v1
GROUP BY reference_status
ORDER BY reference_status;


-- 작업 27-3: 상품 코드별 상세
-- 원문 코드·표준 상품명·연결 상태 확인

SELECT
    raw_item_code,
    raw_code_hex,
    source_rows,
    dictionary_rows,
    standard_item_name,
    reference_status
FROM kream_project_repro.asis_product_code_reference_check_v1
ORDER BY reference_status, raw_code_hex;

-- 작업 27-4: 상품 사전에 없는 코드 확인
-- 원본 수정 및 격리 없음

SELECT
    raw_item_code,
    raw_code_hex,
    source_rows,
    reference_status
FROM kream_project_repro.asis_product_code_reference_check_v1
WHERE reference_status = 'CODE_NOT_FOUND'
ORDER BY raw_code_hex;


-- 작업 27-5: 미연결 상품 코드의 사전 유형·금칙 여부 확인
-- ITEM_MODEL 이외 유형도 포함해 정확한 코드로 대조
-- 원본 수정 및 격리 없음

SELECT
    u.raw_item_code,
    u.source_rows,
    d.DICT_ID,
    d.CODE_TYPE,
    d.STD_KOR_NM,
    d.SYNONYM_LIST,
    d.BANNED_WORD_YN
FROM kream_project_repro.asis_product_code_reference_check_v1 AS u
LEFT JOIN kream_project_repro.bronze_product_std_dict AS d
  ON HEX(d.STD_CODE) = u.raw_code_hex
WHERE u.reference_status = 'CODE_NOT_FOUND'
ORDER BY u.raw_code_hex, d.DICT_ID;