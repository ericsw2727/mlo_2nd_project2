-- 작업 09-1: 카테고리 필수값 누락 검사
-- 근거: 명세서의 CAT_ID, CAT_NM, CAT_LEVEL, REG_DT는 필수
-- 이번 검사는 NULL·빈 문자열·공백만 검사

SELECT COUNT(*) AS missing_required_rows
FROM kream_project.bronze_category_parent_lookup
WHERE NULLIF(TRIM(CAT_ID), '') IS NULL
   OR NULLIF(TRIM(CAT_NM), '') IS NULL
   OR NULLIF(TRIM(CAT_LEVEL), '') IS NULL
   OR NULLIF(TRIM(REG_DT), '') IS NULL;


-- 작업 09-2: 원문 기준 중복 ID 집계
-- 목적: 반복되는 ID 종류와 각 ID의 첫 행을 제외한 추가 행 수 확인
-- 같은 ID라는 이유만으로 완전히 동일한 재전송이라고 판정하지 않음

SELECT
    COUNT(*) AS duplicate_id_groups,
    COALESCE(SUM(rows_per_id - 1), 0) AS additional_rows_for_same_id
FROM (
    SELECT
        CAT_ID,
        COUNT(*) AS rows_per_id
    FROM kream_project.bronze_category_parent_lookup
    GROUP BY CAT_ID
    HAVING COUNT(*) > 1
) AS repeated_ids;


-- 작업 09-3: 계층 코드의 원문 표기 분포 확인
-- 목적: 표준 코드, 표기 차이, 허용되지 않은 값 구분의 기초 조사
-- HEX는 보이지 않는 공백·문자 차이를 확인하기 위한 보조값

SELECT
    CAT_LEVEL,
    HEX(CAT_LEVEL) AS raw_level_hex,
    COUNT(*) AS row_count
FROM kream_project.bronze_category_parent_lookup
GROUP BY CAT_LEVEL, HEX(CAT_LEVEL)
ORDER BY row_count DESC, raw_level_hex;

-- 작업 09-4: 같은 ID의 원본 내용이 완전히 동일한지 검사
-- 목적: 동일 재전송 후보와 같은 ID의 값 충돌을 구분
-- 관리 컬럼을 제외하고 원본 4개 컬럼을 비교
-- HEX를 사용하여 대소문자·공백 등 실제 문자 차이도 구분
-- NULL은 HEX 값과 겹치지 않는 별도 표기로 처리

WITH duplicate_groups AS (
    SELECT
        CAT_ID,
        COUNT(*) AS rows_per_id,
        COUNT(DISTINCT
            COALESCE(HEX(CAT_ID), 'NULL'),
            COALESCE(HEX(CAT_NM), 'NULL'),
            COALESCE(HEX(CAT_LEVEL), 'NULL'),
            COALESCE(HEX(REG_DT), 'NULL')
        ) AS raw_content_versions
    FROM kream_project.bronze_category_parent_lookup
    GROUP BY CAT_ID
    HAVING COUNT(*) > 1
)
SELECT
    COUNT(*) AS duplicate_id_groups,
    COALESCE(SUM(raw_content_versions = 1), 0)
        AS identical_content_groups,
    COALESCE(SUM(raw_content_versions > 1), 0)
        AS conflicting_content_groups,
    COALESCE(SUM(rows_per_id - 1), 0)
        AS additional_rows_for_same_id
FROM duplicate_groups;


-- 작업 09-5: 등록일의 원문 형식 분포 검사
-- 목적: 날짜 변환에 필요한 형식을 파악
-- 형식만 분류하며 실제 날짜 유효성 검사는 아직 수행하지 않음

SELECT
    CASE
        WHEN REG_DT IS NULL OR TRIM(REG_DT) = ''
            THEN 'MISSING'
        WHEN REGEXP_LIKE(
            REG_DT,
            '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$'
        )
            THEN 'HYPHEN_DATETIME'
        WHEN REGEXP_LIKE(
            REG_DT,
            '^[0-9]{4}/[0-9]{2}/[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$'
        )
            THEN 'SLASH_DATETIME'
        ELSE 'OTHER_FORMAT'
    END AS date_format,
    COUNT(*) AS row_count
FROM kream_project.bronze_category_parent_lookup
GROUP BY date_format
ORDER BY row_count DESC;


-- 작업 09-6: 카테고리 ID의 원문 형식 검사
-- 기준: 이번 데이터의 정규 ID 형식인 CAT_ + 숫자 5자리
-- 형식 차이를 찾는 검사이며 실제로 없는 ID라고 판정하지 않음
-- 'c'는 대소문자를 구분하도록 지정

SELECT
    COUNT(*) AS total_rows,
    SUM(
        CASE
            WHEN REGEXP_LIKE(CAT_ID, '^CAT_[0-9]{5}$', 'c')
            THEN 1 ELSE 0
        END
    ) AS standard_id_format_rows,
    SUM(
        CASE
            WHEN CAT_ID IS NULL
              OR NOT REGEXP_LIKE(CAT_ID, '^CAT_[0-9]{5}$', 'c')
            THEN 1 ELSE 0
        END
    ) AS nonstandard_id_format_rows
FROM kream_project.bronze_category_parent_lookup;


-- 작업 09-7: 비표준 ID의 실제 값과 문자 정보 확인
-- 목적: 전각 문자·공백·접두어 차이 등 보정 근거 확인
-- 원본을 수정하지 않고 최대 10행만 조회

SELECT
    bronze_row_id,
    CAT_ID,
    HEX(CAT_ID) AS raw_id_hex,
    CHAR_LENGTH(CAT_ID) AS character_count,
    LENGTH(CAT_ID) AS byte_count,
    CAT_NM
FROM kream_project.bronze_category_parent_lookup
WHERE CAT_ID IS NULL
   OR NOT REGEXP_LIKE(CAT_ID, '^CAT_[0-9]{5}$', 'c')
ORDER BY bronze_row_id
LIMIT 10;