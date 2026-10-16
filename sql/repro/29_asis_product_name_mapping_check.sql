-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 29-1: 전체 상품명과 사전의 정확한 매핑 검사
-- 동의어는 명세서의 쉼표 구분 기준으로 분리
-- 비교에서는 앞뒤 일반 공백과 대소문자만 통일
-- 사전의 '(오타)' 등 문구는 임의로 제거하지 않음
-- 원본 수정·상품명 복구·격리는 아직 수행하지 않음

CREATE OR REPLACE VIEW
    kream_project_repro.asis_product_name_mapping_check_v1 AS

WITH source_names AS (
    SELECT
        ITEM_STD_CODE AS raw_item_code,
        ITEM_NM AS raw_item_name,
        HEX(ITEM_STD_CODE) AS raw_code_hex,
        HEX(ITEM_NM) AS raw_name_hex,
        LOWER(TRIM(ITEM_NM)) AS name_for_check,
        COUNT(*) AS source_rows
    FROM kream_project_repro.bronze_inspection
    GROUP BY
        ITEM_STD_CODE, HEX(ITEM_STD_CODE),
        ITEM_NM, HEX(ITEM_NM)
),
dictionary_terms AS (
    -- 표준명도 이름 매핑 기준에 포함
    SELECT
        STD_CODE,
        CODE_TYPE,
        BANNED_WORD_YN,
        LOWER(TRIM(STD_KOR_NM)) AS term_for_check
    FROM kream_project_repro.bronze_product_std_dict
    WHERE CODE_TYPE IN ('ITEM_MODEL', 'BANNED_WORD')

    UNION ALL

    -- JSON_QUOTE로 따옴표·역슬래시를 보존한 뒤
    -- 쉼표 구분 동의어를 각각의 행으로 펼침
    SELECT
        d.STD_CODE,
        d.CODE_TYPE,
        d.BANNED_WORD_YN,
        LOWER(TRIM(j.alias_term))
    FROM kream_project_repro.bronze_product_std_dict AS d
    CROSS JOIN JSON_TABLE(
        CONCAT(
            '[',
            REPLACE(
                JSON_QUOTE(COALESCE(d.SYNONYM_LIST, '')),
                ',',
                '","'
            ),
            ']'
        ),
        '$[*]' COLUMNS (
            alias_term VARCHAR(1000) PATH '$'
        )
    ) AS j
    WHERE d.CODE_TYPE IN ('ITEM_MODEL', 'BANNED_WORD')
      AND TRIM(j.alias_term) <> ''
)
SELECT
    s.raw_item_code,
    s.raw_item_name,
    s.raw_code_hex,
    s.raw_name_hex,
    s.source_rows,
    d.STD_KOR_NM AS code_standard_name,

    CASE
        WHEN d.CODE_TYPE = 'BANNED_WORD'
         AND d.BANNED_WORD_YN = 'Y'
        THEN 'BANNED_PRODUCT_CODE'

        WHEN EXISTS (
            SELECT 1
            FROM dictionary_terms AS t
            WHERE t.CODE_TYPE = 'BANNED_WORD'
              AND t.BANNED_WORD_YN = 'Y'
              AND t.term_for_check = s.name_for_check
        )
        THEN 'BANNED_NAME_EXACT_MATCH'

        WHEN d.DICT_ID IS NULL
          OR d.CODE_TYPE <> 'ITEM_MODEL'
        THEN 'PRODUCT_CODE_REVIEW'

        WHEN EXISTS (
            SELECT 1
            FROM dictionary_terms AS t
            WHERE t.CODE_TYPE = 'ITEM_MODEL'
              AND HEX(t.STD_CODE) <> s.raw_code_hex
              AND t.term_for_check = s.name_for_check
        )
        THEN 'OTHER_PRODUCT_NAME_REVIEW'

        WHEN s.raw_name_hex = HEX(d.STD_KOR_NM)
        THEN 'STANDARD_NAME'

        WHEN s.name_for_check = LOWER(TRIM(d.STD_KOR_NM))
        THEN 'STANDARD_NAME_SPELLING_VARIANT'

        WHEN EXISTS (
            SELECT 1
            FROM dictionary_terms AS t
            WHERE t.CODE_TYPE = 'ITEM_MODEL'
              AND HEX(t.STD_CODE) = s.raw_code_hex
              AND t.term_for_check = s.name_for_check
        )
        THEN 'REGISTERED_ALIAS'

        ELSE 'UNMAPPED_NAME_REVIEW'
    END AS name_check_status

FROM source_names AS s
LEFT JOIN kream_project_repro.bronze_product_std_dict AS d
  ON HEX(d.STD_CODE) = s.raw_code_hex
 AND d.CODE_TYPE IN ('ITEM_MODEL', 'BANNED_WORD');


-- 작업 29-2: 전체 상품명 검사 결과 집계
-- source_rows 합계는 335,000이어야 함
-- name_groups는 코드와 원문 상품명 조합의 수

SELECT
    name_check_status,
    COUNT(*) AS name_groups,
    SUM(source_rows) AS source_rows
FROM kream_project_repro.asis_product_name_mapping_check_v1
GROUP BY name_check_status
ORDER BY name_check_status;


-- 작업 29-3: 추가 검토가 필요한 상품명
-- 수신 행 수가 많은 유형 최대 30개
-- 표준명으로 임의 치환하지 않음

SELECT
    raw_item_code,
    raw_item_name,
    code_standard_name,
    name_check_status,
    source_rows
FROM kream_project_repro.asis_product_name_mapping_check_v1
WHERE name_check_status IN (
    'PRODUCT_CODE_REVIEW',
    'OTHER_PRODUCT_NAME_REVIEW',
    'UNMAPPED_NAME_REVIEW'
)
ORDER BY source_rows DESC, raw_code_hex, raw_name_hex
LIMIT 30;