-- 작업 33-1: 부서명 전체의 사전 매핑 검사
-- 표준명과 쉼표 구분 동의어를 사용
-- 앞뒤 일반 공백·대소문자를 통일해 비교
-- 금칙 부서, 단일 표준 매핑, 다중 매핑, 미매핑 구분
-- 원본 수정 없음

CREATE OR REPLACE VIEW
    kream_project.asis_inspector_department_check_v1 AS

WITH dictionary_terms AS (
    SELECT
        STD_CODE,
        STD_KOR_NM,
        CODE_TYPE,
        BANNED_WORD_YN,
        LOWER(TRIM(STD_KOR_NM)) AS term_for_check
    FROM kream_project.bronze_product_std_dict
    WHERE CODE_TYPE IN ('DEPT_STD', 'BANNED_DEPT')

    UNION ALL

    SELECT
        d.STD_CODE,
        d.STD_KOR_NM,
        d.CODE_TYPE,
        d.BANNED_WORD_YN,
        LOWER(TRIM(j.alias_term))
    FROM kream_project.bronze_product_std_dict AS d

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

    WHERE d.CODE_TYPE IN ('DEPT_STD', 'BANNED_DEPT')
      AND TRIM(j.alias_term) <> ''
),
term_summary AS (
    SELECT
        term_for_check,

        COUNT(DISTINCT
            CASE
                WHEN CODE_TYPE = 'DEPT_STD'
                 AND BANNED_WORD_YN = 'N'
                THEN STD_CODE
            END
        ) AS normal_code_count,

        COUNT(DISTINCT
            CASE
                WHEN BANNED_WORD_YN = 'Y'
                THEN STD_CODE
            END
        ) AS banned_code_count,

        MIN(
            CASE
                WHEN CODE_TYPE = 'DEPT_STD'
                 AND BANNED_WORD_YN = 'N'
                THEN STD_CODE
            END
        ) AS candidate_code,

        MIN(
            CASE
                WHEN CODE_TYPE = 'DEPT_STD'
                 AND BANNED_WORD_YN = 'N'
                THEN STD_KOR_NM
            END
        ) AS candidate_name

    FROM dictionary_terms
    WHERE term_for_check IS NOT NULL
      AND term_for_check <> ''
    GROUP BY term_for_check
),
source_departments AS (
    SELECT
        DEPT_NM AS raw_department,
        HEX(DEPT_NM) AS raw_department_hex,
        LOWER(TRIM(DEPT_NM)) AS department_for_check,
        COUNT(*) AS source_rows
    FROM kream_project.bronze_inspector_master
    GROUP BY DEPT_NM, HEX(DEPT_NM)
)
SELECT
    s.raw_department,
    s.raw_department_hex,
    s.source_rows,

    CASE
        WHEN COALESCE(t.banned_code_count, 0) = 0
         AND t.normal_code_count = 1
        THEN t.candidate_code
        ELSE NULL
    END AS proposed_department_code,

    CASE
        WHEN COALESCE(t.banned_code_count, 0) = 0
         AND t.normal_code_count = 1
        THEN t.candidate_name
        ELSE NULL
    END AS proposed_department_name,

    CASE
        WHEN NULLIF(s.department_for_check, '') IS NULL
        THEN 'MISSING_DEPARTMENT'

        WHEN COALESCE(t.banned_code_count, 0) > 0
        THEN 'BANNED_DEPARTMENT'

        WHEN COALESCE(t.normal_code_count, 0) = 0
        THEN 'UNMAPPED_DEPARTMENT'

        WHEN t.normal_code_count > 1
        THEN 'AMBIGUOUS_DEPARTMENT'

        WHEN s.raw_department_hex = HEX(t.candidate_name)
        THEN 'STANDARD_DEPARTMENT'

        ELSE 'NORMALIZABLE_DEPARTMENT'
    END AS department_status

FROM source_departments AS s
LEFT JOIN term_summary AS t
  ON t.term_for_check = s.department_for_check;


-- 작업 33-2: 부서 매핑 상태별 건수
-- source_rows 합계는 3,150이어야 함

SELECT
    department_status,
    COUNT(*) AS raw_department_groups,
    SUM(source_rows) AS source_rows
FROM kream_project.asis_inspector_department_check_v1
GROUP BY department_status
ORDER BY department_status;


-- 작업 33-3: 부서명별 처리 후보 확인
-- 전체 부서명 유형을 표시

SELECT
    raw_department,
    source_rows,
    proposed_department_code,
    proposed_department_name,
    department_status
FROM kream_project.asis_inspector_department_check_v1
ORDER BY department_status, raw_department_hex;