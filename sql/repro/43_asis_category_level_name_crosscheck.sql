-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 43-1: 전체 계층 코드와 카테고리 이름 형태 대조
-- 이름 형태는 조사용 단서이며 확정된 계층 규칙이 아님
-- 원본 수정·계층 복구·격리 없음

WITH classified AS (
    SELECT
        CAT_LEVEL AS raw_cat_level,
        HEX(CAT_LEVEL) AS raw_level_hex,

        UPPER(
            REPLACE(TRIM(CAT_LEVEL), ' ', '_')
        ) AS level_spelling_candidate,

        CASE
            WHEN REGEXP_LIKE(
                CAT_NM, '_LINE_[0-9]+$', 'c'
            )
            THEN 'LINE_NAME_PATTERN'
            ELSE 'OTHER_NAME_PATTERN'
        END AS name_pattern

    FROM kream_project_repro.bronze_category_parent_lookup
)
SELECT
    raw_cat_level,
    raw_level_hex,
    level_spelling_candidate,
    name_pattern,
    COUNT(*) AS source_rows
FROM classified
GROUP BY
    raw_cat_level,
    raw_level_hex,
    level_spelling_candidate,
    name_pattern
ORDER BY raw_level_hex, name_pattern;