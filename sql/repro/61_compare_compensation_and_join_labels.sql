-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 61-1: 배상금 검사 테이블 존재 여부 확인

SELECT COUNT(*) AS existing_tables
FROM information_schema.tables
WHERE table_schema = 'kream_project_repro'
  AND table_name = 'asis_join_compensation_check_v1';


-- 작업 61-2: 숫자 변환의 범위와 소수 정밀도 확인
-- 소수 부분을 잘라서 비교하지 않도록 사전 확인
-- storage_error_rows는 0이어야 함

SELECT
    COUNT(*) AS source_rows,

    SUM(
        CASE
            WHEN REGEXP_LIKE(
                TRIM(raw_compensation_loss),
                '^[-+]?[0-9]{1,22}([.][0-9]{1,8})?$',
                'c'
            )
            THEN 0 ELSE 1
        END
    ) AS storage_error_rows,

    MAX(
        CASE
            WHEN LOCATE('.', TRIM(raw_compensation_loss)) > 0
            THEN CHAR_LENGTH(
                SUBSTRING_INDEX(
                    TRIM(raw_compensation_loss),
                    '.',
                    -1
                )
            )
            ELSE 0
        END
    ) AS max_fractional_digits

FROM kream_project_repro.asis_join_extra_column_check_v1;


-- 작업 61-3: 배상금 검사 테이블 생성
-- 원본 배상금은 그대로 보존
-- 비교용 숫자는 소수 8자리까지 보존

CREATE TABLE kream_project_repro.asis_join_compensation_check_v1 (
    inspection_bronze_row_id BIGINT UNSIGNED NOT NULL,
    join_ready_bronze_row_id BIGINT UNSIGNED NOT NULL,
    disposition VARCHAR(32) NOT NULL,
    raw_compensation_loss TEXT,
    parsed_compensation_loss DECIMAL(30,8) NOT NULL,
    expected_compensation_loss DECIMAL(30,8),
    compensation_check_status VARCHAR(40) NOT NULL,

    PRIMARY KEY (inspection_bronze_row_id),

    UNIQUE KEY uq_compensation_join_row (
        join_ready_bronze_row_id
    )
)
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin;


-- 작업 61-4: 원본 배상금과 공식 재계산값 비교
-- 기준 금액을 계산할 수 없는 행은 별도로 표시

INSERT INTO kream_project_repro.asis_join_compensation_check_v1 (
    inspection_bronze_row_id,
    join_ready_bronze_row_id,
    disposition,
    raw_compensation_loss,
    parsed_compensation_loss,
    expected_compensation_loss,
    compensation_check_status
)
SELECT
    inspection_bronze_row_id,
    join_ready_bronze_row_id,
    disposition,
    raw_compensation_loss,

    CAST(
        TRIM(raw_compensation_loss) AS DECIMAL(30,8)
    ),

    expected_compensation_loss,

    CASE
        WHEN expected_compensation_loss IS NULL
            THEN 'BASE_AMOUNT_NOT_AVAILABLE'

        WHEN CAST(
            TRIM(raw_compensation_loss) AS DECIMAL(30,8)
        ) = expected_compensation_loss
            THEN 'EXACT_MATCH'

        ELSE 'AMOUNT_DIFFERENT'
    END

FROM kream_project_repro.asis_join_extra_column_check_v1;

SHOW WARNINGS;


-- 작업 61-5: 저장 건수와 배상금 비교 결과 확인

SELECT
    compensation_check_status,
    COUNT(*) AS source_rows
FROM kream_project_repro.asis_join_compensation_check_v1
GROUP BY compensation_check_status
ORDER BY compensation_check_status;


-- 작업 61-6: 배상금 차이가 각 분류에 미치는 범위 확인

SELECT
    disposition,
    compensation_check_status,
    COUNT(*) AS source_rows
FROM kream_project_repro.asis_join_compensation_check_v1
GROUP BY
    disposition,
    compensation_check_status
ORDER BY
    disposition,
    compensation_check_status;


-- 작업 61-7: 배상금 차이 사례 확인

SELECT
    inspection_bronze_row_id,
    disposition,
    raw_compensation_loss,
    parsed_compensation_loss,
    expected_compensation_loss,

    parsed_compensation_loss
        - expected_compensation_loss AS difference_krw

FROM kream_project_repro.asis_join_compensation_check_v1
WHERE compensation_check_status = 'AMOUNT_DIFFERENT'
ORDER BY
    ABS(
        parsed_compensation_loss - expected_compensation_loss
    ) DESC,
    inspection_bronze_row_id
LIMIT 15;


-- 작업 61-8: 부서명 차이의 주요 조합 확인

SELECT
    raw_department_name,
    expected_department_name,
    COUNT(*) AS source_rows
FROM kream_project_repro.asis_join_extra_column_check_v1
WHERE department_name_check_status = 'DIFFERENT_VALUE_REVIEW'
GROUP BY
    raw_department_name,
    HEX(raw_department_name),
    expected_department_name,
    HEX(expected_department_name)
ORDER BY source_rows DESC
LIMIT 20;


-- 작업 61-9: 직급 차이의 주요 조합 확인

SELECT
    raw_position_name,
    expected_position_name,
    COUNT(*) AS source_rows
FROM kream_project_repro.asis_join_extra_column_check_v1
WHERE position_name_check_status = 'DIFFERENT_VALUE_REVIEW'
GROUP BY
    raw_position_name,
    HEX(raw_position_name),
    expected_position_name,
    HEX(expected_position_name)
ORDER BY source_rows DESC
LIMIT 10;


-- 작업 61-10: 카테고리명 차이의 주요 조합 확인

SELECT
    raw_category_name,
    expected_category_name,
    COUNT(*) AS source_rows
FROM kream_project_repro.asis_join_extra_column_check_v1
WHERE category_name_check_status = 'DIFFERENT_VALUE_REVIEW'
GROUP BY
    raw_category_name,
    HEX(raw_category_name),
    expected_category_name,
    HEX(expected_category_name)
ORDER BY source_rows DESC
LIMIT 10;