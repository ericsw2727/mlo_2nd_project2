-- 작업 47-0: 기존 검사 저장 테이블 확인

SELECT TABLE_NAME
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'kream_project'
  AND TABLE_NAME = 'asis_final_reference_snapshot_v1';


-- 작업 47-1: 최종 Silver 마스터 참조 검사 저장
-- 원본 행 번호와 컬럼을 묶어 검사 결과 중복 저장 방지
-- 정상 여부는 참조 검사에 한정됨
-- 다른 품질 검사 결과는 이후 연결

CREATE TABLE kream_project.asis_final_reference_snapshot_v1 (
    bronze_row_id BIGINT UNSIGNED NOT NULL,
    column_name VARCHAR(32) NOT NULL,
    raw_value TEXT,
    proposed_id VARCHAR(20),
    effective_reference_id VARCHAR(20),
    reference_origin VARCHAR(32) NOT NULL,
    final_reference_status VARCHAR(32) NOT NULL,
    rule_version VARCHAR(32) NOT NULL,

    PRIMARY KEY (bronze_row_id, column_name),
    INDEX ix_final_reference_status (
        column_name,
        final_reference_status
    )
)
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin;


INSERT INTO kream_project.asis_final_reference_snapshot_v1 (
    bronze_row_id,
    column_name,
    raw_value,
    proposed_id,
    effective_reference_id,
    reference_origin,
    final_reference_status,
    rule_version
)
SELECT
    bronze_row_id,
    column_name,
    raw_value,
    proposed_id,
    effective_reference_id,
    reference_origin,
    final_reference_status,
    '20261014_v1'
FROM kream_project.asis_reference_to_silver_master_v1;

SHOW WARNINGS;


-- 작업 47-2: 컬럼별 저장 건수와 참조 통과 건수
-- 각 컬럼 335,000행, 전체 670,000개 검사 결과

SELECT
    column_name,
    COUNT(*) AS inspected_rows,

    SUM(
        CASE WHEN final_reference_status = 'SILVER_MASTER_FOUND'
             THEN 1 ELSE 0 END
    ) AS reference_passed_rows,

    SUM(
        CASE WHEN final_reference_status <> 'SILVER_MASTER_FOUND'
             THEN 1 ELSE 0 END
    ) AS reference_failed_rows

FROM kream_project.asis_final_reference_snapshot_v1
GROUP BY column_name
ORDER BY column_name;


-- 작업 47-3: 원본 행별 검사 누락 확인
-- 원본마다 사번 검사 1개, 카테고리 검사 1개 필요

WITH recorded AS (
    SELECT
        bronze_row_id,
        COUNT(*) AS check_count,

        SUM(
            CASE WHEN column_name = 'INSPECTOR_EMP_NO'
                 THEN 1 ELSE 0 END
        ) AS employee_check_count,

        SUM(
            CASE WHEN column_name = 'PARENT_CAT_ID'
                 THEN 1 ELSE 0 END
        ) AS category_check_count

    FROM kream_project.asis_final_reference_snapshot_v1
    GROUP BY bronze_row_id
)
SELECT
    COUNT(*) AS bronze_rows,

    SUM(
        CASE WHEN r.bronze_row_id IS NULL
             THEN 1 ELSE 0 END
    ) AS missing_all_checks_rows,

    SUM(
        CASE WHEN COALESCE(r.check_count, 0) <> 2
             THEN 1 ELSE 0 END
    ) AS incorrect_check_count_rows,

    SUM(
        CASE WHEN COALESCE(r.employee_check_count, 0) <> 1
             THEN 1 ELSE 0 END
    ) AS incorrect_employee_check_rows,

    SUM(
        CASE WHEN COALESCE(r.category_check_count, 0) <> 1
             THEN 1 ELSE 0 END
    ) AS incorrect_category_check_rows

FROM kream_project.bronze_inspection AS b
LEFT JOIN recorded AS r
  ON r.bronze_row_id = b.bronze_row_id;


-- 작업 47-4: 두 참조 문제의 행별 중첩 집계
-- 각 원본 행은 정확히 한 조합에 속함
-- 아래 row_count 합계는 335,000이어야 함

WITH row_checks AS (
    SELECT
        bronze_row_id,

        MAX(
            CASE WHEN column_name = 'INSPECTOR_EMP_NO'
                 THEN
                     CASE
                         WHEN final_reference_status =
                              'SILVER_MASTER_FOUND'
                         THEN 'PASS'
                         ELSE 'FAIL'
                     END
            END
        ) AS employee_reference_check,

        MAX(
            CASE WHEN column_name = 'PARENT_CAT_ID'
                 THEN
                     CASE
                         WHEN final_reference_status =
                              'SILVER_MASTER_FOUND'
                         THEN 'PASS'
                         ELSE 'FAIL'
                     END
            END
        ) AS category_reference_check

    FROM kream_project.asis_final_reference_snapshot_v1
    GROUP BY bronze_row_id
)
SELECT
    employee_reference_check,
    category_reference_check,
    COUNT(*) AS row_count
FROM row_checks
GROUP BY employee_reference_check, category_reference_check
ORDER BY employee_reference_check, category_reference_check;