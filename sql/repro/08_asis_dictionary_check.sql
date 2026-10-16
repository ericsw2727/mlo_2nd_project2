-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 08-1: 표준 사전의 기본 현황 확인
-- 목적: 전체 행 수와 원문 기준 식별자·코드 수 파악
-- STD_CODE 개수는 현황값이며 전역 UNIQUE 규칙으로 확정하지 않음

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT DICT_ID) AS distinct_dict_ids,
    COUNT(DISTINCT CODE_TYPE) AS distinct_code_types,
    COUNT(DISTINCT STD_CODE) AS distinct_standard_codes
FROM kream_project_repro.bronze_product_std_dict;


-- 작업 08-2: 명세서상 필수 컬럼의 NULL·빈 문자열·공백 검사
-- 근거: SYNONYM_LIST는 선택 컬럼이므로 이번 필수값 검사에서 제외
-- 주의: 조회에만 TRIM을 사용하며 저장된 원본은 변경하지 않음

SELECT
    bronze_row_id,
    DICT_ID,
    CODE_TYPE,
    STD_CODE,
    STD_KOR_NM,
    BANNED_WORD_YN,
    BASE_RETAIL_KRW,
    FAKE_PENALTY_MULTIPLIER
FROM kream_project_repro.bronze_product_std_dict
WHERE NULLIF(TRIM(DICT_ID), '') IS NULL
   OR NULLIF(TRIM(CODE_TYPE), '') IS NULL
   OR NULLIF(TRIM(STD_CODE), '') IS NULL
   OR NULLIF(TRIM(STD_KOR_NM), '') IS NULL
   OR NULLIF(TRIM(BANNED_WORD_YN), '') IS NULL
   OR NULLIF(TRIM(BASE_RETAIL_KRW), '') IS NULL
   OR NULLIF(TRIM(FAKE_PENALTY_MULTIPLIER), '') IS NULL
ORDER BY bronze_row_id;


-- 작업 08-3: 원문 기준 사전 기본키 중복 검사
-- 근거: 명세서에서 DICT_ID는 기본키
-- 동일 ID가 반복되면 값을 비교한 후 처리해야 함

SELECT
    DICT_ID,
    COUNT(*) AS duplicate_rows
FROM kream_project_repro.bronze_product_std_dict
GROUP BY DICT_ID
HAVING COUNT(*) > 1
ORDER BY duplicate_rows DESC, DICT_ID;


-- 작업 08-4: 코드 유형별 사전 구성 확인
-- 목적: 상품·금칙어·검수 결과·부서 규칙을 구분
-- 사전 조인 시 CODE_TYPE을 함께 확인하기 위한 기초 조사

SELECT
    CODE_TYPE,
    COUNT(*) AS dictionary_rows
FROM kream_project_repro.bronze_product_std_dict
GROUP BY CODE_TYPE
ORDER BY CODE_TYPE;

-- 작업 08-5: 필수값 누락을 숫자로 확인
-- 목적: 빈 조회 결과를 명시적인 건수로 기록

SELECT COUNT(*) AS missing_required_rows
FROM kream_project_repro.bronze_product_std_dict
WHERE NULLIF(TRIM(DICT_ID), '') IS NULL
   OR NULLIF(TRIM(CODE_TYPE), '') IS NULL
   OR NULLIF(TRIM(STD_CODE), '') IS NULL
   OR NULLIF(TRIM(STD_KOR_NM), '') IS NULL
   OR NULLIF(TRIM(BANNED_WORD_YN), '') IS NULL
   OR NULLIF(TRIM(BASE_RETAIL_KRW), '') IS NULL
   OR NULLIF(TRIM(FAKE_PENALTY_MULTIPLIER), '') IS NULL;


-- 작업 08-6: 중복된 사전 ID 그룹 수를 숫자로 확인
-- 목적: 중복 ID가 몇 종류인지 기록

SELECT COUNT(*) AS duplicate_dict_id_groups
FROM (
    SELECT DICT_ID
    FROM kream_project_repro.bronze_product_std_dict
    GROUP BY DICT_ID
    HAVING COUNT(*) > 1
) AS duplicate_ids;


-- 작업 08-7: 코드 유형과 금칙 여부 코드 검사
-- 근거: 현재 제공된 사전의 5개 유형과 Y/N 기준으로 검사
-- 사전 유형이 추가되면 허용 목록도 재검토해야 함

SELECT
    bronze_row_id,
    DICT_ID,
    CODE_TYPE,
    STD_CODE,
    BANNED_WORD_YN
FROM kream_project_repro.bronze_product_std_dict
WHERE CODE_TYPE IS NULL
   OR CODE_TYPE NOT IN (
       'ITEM_MODEL',
       'BANNED_WORD',
       'INSP_RESULT',
       'DEPT_STD',
       'BANNED_DEPT'
   )
   OR BANNED_WORD_YN IS NULL
   OR BANNED_WORD_YN NOT IN ('Y', 'N')
ORDER BY bronze_row_id;


-- 작업 08-8: 기준 가격과 배상 배수의 숫자 형식 검사
-- 기준 가격: 0 이상의 정수 문자열
-- 배상 배수: 0 이상의 정수 또는 소수 문자열
-- 이번 검사는 형식 검사이며 DB 자료형 범위·정밀도 검사는 별도
-- 조회만 수행하고 숫자 변환이나 보정은 하지 않음

SELECT
    bronze_row_id,
    DICT_ID,
    CODE_TYPE,
    STD_CODE,
    BASE_RETAIL_KRW,
    FAKE_PENALTY_MULTIPLIER
FROM kream_project_repro.bronze_product_std_dict
WHERE BASE_RETAIL_KRW IS NULL
   OR NOT REGEXP_LIKE(BASE_RETAIL_KRW, '^[0-9]+$')
   OR FAKE_PENALTY_MULTIPLIER IS NULL
   OR NOT REGEXP_LIKE(
       FAKE_PENALTY_MULTIPLIER,
       '^[0-9]+([.][0-9]+)?$'
   )
ORDER BY bronze_row_id;


-- 작업 08-9: 검수 결과별 배상 배수 확인
-- 목적: 이후 조인 결과의 배상금 검증 기준 확인
-- 제공된 프로젝트 명세의 배상 시나리오이며 현행 서비스 정책 아님

SELECT
    DICT_ID,
    STD_CODE AS inspection_result_code,
    STD_KOR_NM AS inspection_result_name,
    FAKE_PENALTY_MULTIPLIER
FROM kream_project_repro.bronze_product_std_dict
WHERE CODE_TYPE = 'INSP_RESULT'
ORDER BY STD_CODE;