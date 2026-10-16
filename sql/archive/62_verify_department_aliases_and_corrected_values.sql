-- 작업 62-1: 부서 조합 검사 테이블 존재 여부 확인

SELECT COUNT(*) AS existing_tables
FROM information_schema.tables
WHERE table_schema = 'kream_project'
  AND table_name = 'asis_department_pair_check_v1';


-- 작업 62-2: 원본 부서명과 정규 부서명의 조합 검사
-- 공식 부서명과 등록된 동의어만 사용
-- 동의어 비교는 앞뒤 공백과 영문 대소문자만 정리
-- 기존 원본 마스터에 근거한 표준화 결과도 보존

CREATE TABLE kream_project.asis_department_pair_check_v1
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin
AS
WITH department_aliases AS (
    SELECT
        STD_CODE,
        STD_KOR_NM,
        LOWER(TRIM(STD_KOR_NM)) AS alias_value
    FROM kream_project.silver_product_std_dict
    WHERE CODE_TYPE = 'DEPT_STD'
      AND BANNED_WORD_YN = 'N'

    UNION

    SELECT
        d.STD_CODE,
        d.STD_KOR_NM,
        LOWER(TRIM(a.alias_value))
    FROM kream_project.silver_product_std_dict AS d

    JOIN JSON_TABLE(
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
            alias_value VARCHAR(1000) PATH '$'
        )
    ) AS a ON TRUE

    WHERE d.CODE_TYPE = 'DEPT_STD'
      AND d.BANNED_WORD_YN = 'N'
      AND NULLIF(TRIM(a.alias_value), '') IS NOT NULL
),
department_pairs AS (
    SELECT
        raw_department_name,
        expected_department_name,
        department_name_check_status AS previous_check_status,
        COUNT(*) AS source_rows

    FROM kream_project.asis_join_extra_column_check_v1

    GROUP BY
        raw_department_name,
        HEX(raw_department_name),
        expected_department_name,
        HEX(expected_department_name),
        department_name_check_status
),
known_departments AS (
    SELECT DISTINCT DEPT_NM
    FROM kream_project.silver_inspector_master
),
matched_pairs AS (
    SELECT
        p.raw_department_name,
        p.expected_department_name,
        p.previous_check_status,
        p.source_rows,

        COUNT(DISTINCT a.STD_CODE) AS alias_target_count,

        GROUP_CONCAT(
            DISTINCT a.STD_KOR_NM
            ORDER BY a.STD_KOR_NM
            SEPARATOR ', '
        ) AS alias_target_names,

        MAX(HEX(a.STD_KOR_NM)) AS single_target_name_hex,
        MAX(k.DEPT_NM) AS known_raw_department

    FROM department_pairs AS p

    LEFT JOIN department_aliases AS a
      ON HEX(a.alias_value) =
         HEX(LOWER(TRIM(p.raw_department_name)))

    LEFT JOIN known_departments AS k
      ON HEX(k.DEPT_NM) = HEX(p.raw_department_name)

    GROUP BY
        p.raw_department_name,
        HEX(p.raw_department_name),
        p.expected_department_name,
        HEX(p.expected_department_name),
        p.previous_check_status,
        p.source_rows
)
SELECT
    m.*,

    CASE
        WHEN previous_check_status = 'MASTER_NOT_AVAILABLE'
            THEN 'MASTER_NOT_AVAILABLE'

        WHEN previous_check_status = 'EXACT_MATCH'
            THEN 'EXACT_MATCH'

        WHEN previous_check_status = 'STANDARDIZATION_REQUIRED'
            THEN 'SOURCE_MASTER_STANDARDIZATION'

        WHEN alias_target_count > 1
            THEN 'AMBIGUOUS_ALIAS'

        WHEN alias_target_count = 1
         AND single_target_name_hex =
             HEX(expected_department_name)
            THEN 'REGISTERED_ALIAS_MATCH'

        WHEN alias_target_count = 1
          OR known_raw_department IS NOT NULL
            THEN 'DIFFERENT_DEPARTMENT'

        ELSE 'UNMAPPED_DEPARTMENT_VALUE'
    END AS final_department_check_status

FROM matched_pairs AS m;

SHOW WARNINGS;


-- 작업 62-3: 부서 검사 결과 집계
-- source_rows 합계는 335000이어야 함

SELECT
    final_department_check_status,
    COUNT(*) AS department_pair_groups,
    SUM(source_rows) AS source_rows
FROM kream_project.asis_department_pair_check_v1
GROUP BY final_department_check_status
ORDER BY final_department_check_status;


-- 작업 62-4: 다른 부서 또는 미매핑 부서의 주요 사례 확인

SELECT
    raw_department_name,
    expected_department_name,
    alias_target_names,
    final_department_check_status,
    source_rows
FROM kream_project.asis_department_pair_check_v1
WHERE final_department_check_status IN (
    'DIFFERENT_DEPARTMENT',
    'UNMAPPED_DEPARTMENT_VALUE',
    'AMBIGUOUS_ALIAS'
)
ORDER BY source_rows DESC
LIMIT 20;


-- 작업 62-5: 정상 테이블에서 문자값과 배상금 수정 검증
-- 원본 검사 결과와 실제 저장된 정상 데이터를 직접 연결
-- 입력 누락과 저장값 차이는 모두 0이어야 함

SELECT
    COUNT(*) AS checked_silver_rows,

    SUM(
        CASE
            WHEN e.inspection_bronze_row_id IS NULL
              OR c.inspection_bronze_row_id IS NULL
            THEN 1 ELSE 0
        END
    ) AS missing_check_rows,

    SUM(
        CASE
            WHEN e.inspection_bronze_row_id IS NOT NULL
             AND NOT (
                    (HEX(j.PARENT_CAT_NM)
                        <=> HEX(e.expected_category_name))
                AND (HEX(j.INSPECTOR_EMP_NM)
                        <=> HEX(e.expected_employee_name))
                AND (HEX(j.INSPECTOR_DEPT_NM)
                        <=> HEX(e.expected_department_name))
                AND (HEX(j.INSPECTOR_POSITION_NM)
                        <=> HEX(e.expected_position_name))
             )
            THEN 1 ELSE 0
        END
    ) AS stored_label_difference_rows,

    SUM(
        CASE
            WHEN c.inspection_bronze_row_id IS NOT NULL
             AND NOT (
                 j.COMPENSATION_LOSS_KRW
                    <=> c.expected_compensation_loss
             )
            THEN 1 ELSE 0
        END
    ) AS stored_compensation_difference_rows,

    SUM(
        CASE
            WHEN c.compensation_check_status = 'AMOUNT_DIFFERENT'
            THEN 1 ELSE 0
        END
    ) AS original_compensation_error_rows

FROM kream_project.silver_inspection_join_ready AS j

LEFT JOIN kream_project.asis_join_extra_column_check_v1 AS e
  ON e.inspection_bronze_row_id = j.source_bronze_row_id

LEFT JOIN kream_project.asis_join_compensation_check_v1 AS c
  ON c.inspection_bronze_row_id = j.source_bronze_row_id;