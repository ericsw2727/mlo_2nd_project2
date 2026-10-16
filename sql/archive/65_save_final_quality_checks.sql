-- 작업 65-1: 품질 검사 결과 테이블 존재 여부 확인

SELECT COUNT(*) AS existing_tables
FROM information_schema.tables
WHERE table_schema = 'kream_project'
  AND table_name = 'data_quality_check_results_v1';


-- 작업 65-2: 품질 검사 결과 테이블 생성
-- 미검증 항목은 오류 건수를 NULL로 기록
-- 검사 실행 시각은 한국 시간으로 기록

CREATE TABLE kream_project.data_quality_check_results_v1 (
    check_id VARCHAR(64) NOT NULL,
    target_table VARCHAR(64) NOT NULL,
    checked_rows BIGINT UNSIGNED NOT NULL,
    failed_rows BIGINT UNSIGNED,
    check_status VARCHAR(32) NOT NULL,
    check_description TEXT NOT NULL,
    rule_version VARCHAR(32) NOT NULL,
    checked_at_kst DATETIME NOT NULL,

    PRIMARY KEY (check_id)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin;


-- 작업 65-3: 현재 데이터의 품질 검사 결과 저장
-- 동일 테이블의 여러 검사를 집계하여 반복 조회를 줄임

SET @kream_quality_checked_at =
    DATE_ADD(UTC_TIMESTAMP(), INTERVAL 9 HOUR);

INSERT INTO kream_project.data_quality_check_results_v1 (
    check_id,
    target_table,
    checked_rows,
    failed_rows,
    check_status,
    check_description,
    rule_version,
    checked_at_kst
)
WITH inspection_stats AS (
    SELECT
        COUNT(*) AS total_rows,

        COUNT(*) - COUNT(DISTINCT f.INSP_ID)
            AS duplicate_inspection_rows,

        SUM(
            CASE
                WHEN NOT REGEXP_LIKE(
                    f.INSP_ID,
                    '^INSP_[0-9]{6}$',
                    'c'
                )
                  OR f.REV_NO < 1
                  OR TRIM(f.ITEM_STD_CODE) = ''
                  OR TRIM(f.ITEM_NM) = ''
                  OR TRIM(f.INSP_RESULT) = ''
                  OR TRIM(f.INSPECTOR_EMP_NO) = ''
                THEN 1 ELSE 0
            END
        ) AS invalid_key_or_required_rows,

        SUM(
            CASE
                WHEN f.TRADE_PRICE_KRW < 0
                  OR f.INSP_DURATION_MIN < 0
                THEN 1 ELSE 0
            END
        ) AS negative_numeric_rows,

        SUM(
            CASE
                WHEN f.INBOUND_DT > f.INSP_DONE_DT
                  OR f.INSP_DONE_DT > f.EXTRACTED_AT
                THEN 1 ELSE 0
            END
        ) AS reversed_datetime_rows,

        SUM(
            CASE WHEN i.EMP_NO IS NULL
                 THEN 1 ELSE 0 END
        ) AS missing_employee_rows,

        SUM(
            CASE
                WHEN f.PARENT_CAT_ID IS NOT NULL
                 AND c.CAT_ID IS NULL
                THEN 1 ELSE 0
            END
        ) AS missing_category_rows

    FROM kream_project.silver_inspection AS f

    LEFT JOIN kream_project.silver_inspector_master AS i
      ON i.EMP_NO = f.INSPECTOR_EMP_NO

    LEFT JOIN kream_project.silver_category_parent_lookup AS c
      ON c.CAT_ID = f.PARENT_CAT_ID
),
inspector_stats AS (
    SELECT
        COUNT(*) AS total_rows,

        SUM(
            CASE
                WHEN b.bronze_row_id IS NULL
                THEN 1 ELSE 0
            END
        ) AS missing_source_rows,

        SUM(
            CASE
                WHEN NOT (
                    i.ACTIVE_YN <=>
                    CASE
                        WHEN HEX(b.ACTIVE_YN) = '59'
                        THEN 'Y'
                        ELSE 'N'
                    END
                )
                THEN 1 ELSE 0
            END
        ) AS active_policy_error_rows,

        SUM(
            CASE
                WHEN NOT REGEXP_LIKE(
                    i.EMP_NO,
                    '^KRM[0-9]{6}$',
                    'c'
                )
                  OR TRIM(i.EMP_NM) = ''
                  OR TRIM(i.DEPT_NM) = ''
                  OR TRIM(i.POSITION_NM) = ''
                THEN 1 ELSE 0
            END
        ) AS standard_value_error_rows

    FROM kream_project.silver_inspector_master AS i

    LEFT JOIN kream_project.bronze_inspector_master AS b
      ON b.bronze_row_id = i.source_bronze_row_id
),
category_stats AS (
    SELECT
        COUNT(*) AS total_rows,

        SUM(
            CASE
                WHEN NOT REGEXP_LIKE(
                    CAT_ID,
                    '^CAT_[0-9]{5}$',
                    'c'
                )
                  OR TRIM(CAT_NM) = ''
                  OR CAT_LEVEL NOT IN (
                      'TOP_LEVEL',
                      'BRAND_LINE'
                  )
                THEN 1 ELSE 0
            END
        ) AS standard_value_error_rows

    FROM kream_project.silver_category_parent_lookup
),
dictionary_stats AS (
    SELECT
        COUNT(*) AS total_rows,

        SUM(
            CASE
                WHEN TRIM(DICT_ID) = ''
                  OR TRIM(STD_CODE) = ''
                  OR TRIM(STD_KOR_NM) = ''
                  OR CODE_TYPE NOT IN (
                      'ITEM_MODEL',
                      'BANNED_WORD',
                      'INSP_RESULT',
                      'DEPT_STD',
                      'BANNED_DEPT'
                  )
                  OR BANNED_WORD_YN NOT IN ('Y', 'N')
                  OR BASE_RETAIL_KRW < 0
                  OR FAKE_PENALTY_MULTIPLIER < 0
                THEN 1 ELSE 0
            END
        ) AS standard_value_error_rows,

        SUM(
            CASE
                WHEN CODE_TYPE = 'INSP_RESULT'
                 AND (
                     (
                         STD_CODE = 'CLAIM_FAKE_PASS'
                         AND FAKE_PENALTY_MULTIPLIER <> 3
                     )
                     OR (
                         STD_CODE <> 'CLAIM_FAKE_PASS'
                         AND FAKE_PENALTY_MULTIPLIER <> 0
                     )
                 )
                THEN 1 ELSE 0
            END
        ) AS penalty_rule_error_rows

    FROM kream_project.silver_product_std_dict
),
join_stats AS (
    SELECT
        COUNT(*) AS total_rows,

        SUM(
            CASE
                WHEN f.INSP_ID IS NULL
                  OR i.EMP_NO IS NULL
                  OR c.CAT_ID IS NULL
                  OR NOT (
                        (HEX(j.INSPECTOR_EMP_NM)
                            <=> HEX(i.EMP_NM))
                    AND (HEX(j.INSPECTOR_DEPT_NM)
                            <=> HEX(i.DEPT_NM))
                    AND (HEX(j.INSPECTOR_POSITION_NM)
                            <=> HEX(i.POSITION_NM))
                    AND (HEX(j.PARENT_CAT_NM)
                            <=> HEX(c.CAT_NM))
                  )
                THEN 1 ELSE 0
            END
        ) AS master_value_error_rows,

        SUM(
            CASE
                WHEN NOT (
                    j.COMPENSATION_LOSS_KRW <=>
                    CASE
                        WHEN j.INSP_RESULT = 'CLAIM_FAKE_PASS'
                        THEN j.TRADE_PRICE_KRW * 3
                        ELSE 0
                    END
                )
                THEN 1 ELSE 0
            END
        ) AS compensation_error_rows

    FROM kream_project.silver_inspection_join_ready AS j

    LEFT JOIN kream_project.silver_inspection AS f
      ON f.INSP_ID = j.INSP_ID
     AND f.REV_NO = j.REV_NO

    LEFT JOIN kream_project.silver_inspector_master AS i
      ON i.EMP_NO = j.INSPECTOR_EMP_NO

    LEFT JOIN kream_project.silver_category_parent_lookup AS c
      ON c.CAT_ID = j.PARENT_CAT_ID
),
check_rows AS (
    SELECT
        'INSPECTION_UNIQUE_ID' AS check_id,
        'silver_inspection' AS target_table,
        total_rows AS checked_rows,
        duplicate_inspection_rows AS failed_rows,
        '검수 ID마다 현재 정상 상태가 한 행인지 확인' AS description,
        CAST(NULL AS CHAR(32)) AS special_status
    FROM inspection_stats

    UNION ALL

    SELECT
        'INSPECTION_KEY_AND_REQUIRED_VALUES',
        'silver_inspection',
        total_rows,
        invalid_key_or_required_rows,
        '검수 키 형식과 필수 문자값 확인',
        NULL
    FROM inspection_stats

    UNION ALL

    SELECT
        'INSPECTION_NONNEGATIVE_NUMBERS',
        'silver_inspection',
        total_rows,
        negative_numeric_rows,
        '음수 거래가와 음수 검수 시간 확인',
        NULL
    FROM inspection_stats

    UNION ALL

    SELECT
        'INSPECTION_DATETIME_ORDER',
        'silver_inspection',
        total_rows,
        reversed_datetime_rows,
        '입고, 검수 완료, 추출 시각의 순서 확인',
        NULL
    FROM inspection_stats

    UNION ALL

    SELECT
        'INSPECTION_EMPLOYEE_REFERENCE',
        'silver_inspection',
        total_rows,
        missing_employee_rows,
        '정상 검수원 마스터 참조 확인',
        NULL
    FROM inspection_stats

    UNION ALL

    SELECT
        'INSPECTION_CATEGORY_REFERENCE',
        'silver_inspection',
        total_rows,
        missing_category_rows,
        '값이 있는 카테고리의 정상 마스터 참조 확인',
        NULL
    FROM inspection_stats

    UNION ALL

    SELECT
        'INSPECTOR_SOURCE_LINK',
        'silver_inspector_master',
        total_rows,
        missing_source_rows,
        '검수원 원본 출처 연결 확인',
        NULL
    FROM inspector_stats

    UNION ALL

    SELECT
        'INSPECTOR_ACTIVE_POLICY',
        'silver_inspector_master',
        total_rows,
        active_policy_error_rows,
        '원본이 정확히 대문자 Y인 경우만 재직 처리 확인',
        NULL
    FROM inspector_stats

    UNION ALL

    SELECT
        'INSPECTOR_STANDARD_VALUES',
        'silver_inspector_master',
        total_rows,
        standard_value_error_rows,
        '사번 형식과 필수 문자값 확인',
        NULL
    FROM inspector_stats

    UNION ALL

    SELECT
        'CATEGORY_STANDARD_VALUES',
        'silver_category_parent_lookup',
        total_rows,
        standard_value_error_rows,
        '카테고리 ID, 이름과 허용 계층 값 확인',
        NULL
    FROM category_stats

    UNION ALL

    SELECT
        'DICTIONARY_STANDARD_VALUES',
        'silver_product_std_dict',
        total_rows,
        standard_value_error_rows,
        '사전 필수값, 코드 유형, 금지 여부와 수치 범위 확인',
        NULL
    FROM dictionary_stats

    UNION ALL

    SELECT
        'DICTIONARY_PENALTY_RULE',
        'silver_product_std_dict',
        total_rows,
        penalty_rule_error_rows,
        '검수 결과별 배상 배수 확인',
        NULL
    FROM dictionary_stats

    UNION ALL

    SELECT
        'JOIN_MASTER_VALUES',
        'silver_inspection_join_ready',
        total_rows,
        master_value_error_rows,
        '정규 마스터의 이름, 부서, 직급과 카테고리명 확인',
        NULL
    FROM join_stats

    UNION ALL

    SELECT
        'JOIN_COMPENSATION_FORMULA',
        'silver_inspection_join_ready',
        total_rows,
        compensation_error_rows,
        '가품 오판정은 거래가의 3배, 그 외는 0 확인',
        NULL
    FROM join_stats

    UNION ALL

    SELECT
        'MAINTENANCE_WINDOW_RULE',
        'silver_inspection',
        0,
        NULL,
        '점검 구간의 기간과 판정 조건이 제공되지 않아 미검증. 추후 개선 항목.',
        'NOT_CHECKED'

    UNION ALL

    SELECT
        'SUPPLIER_COUNT_COMPARISON',
        'silver_inspection',
        335000,
        NULL,
        '현재 정상 271787, 제외 29359, 격리 33854. 상대팀 기준 정상 280800, 제외 32600, 격리 21600과 차이가 있으며 개선 항목으로 기록.',
        'RECORDED_DIFFERENCE'
)
SELECT
    check_id,
    target_table,
    checked_rows,
    failed_rows,

    CASE
        WHEN special_status IS NOT NULL
            THEN special_status
        WHEN failed_rows = 0
            THEN 'PASS'
        ELSE 'FAIL'
    END,

    description,
    '20261014_v2',
    @kream_quality_checked_at

FROM check_rows;

SHOW WARNINGS;


-- 작업 65-4: 검사 상태별 결과 확인

SELECT
    check_status,
    COUNT(*) AS check_count
FROM kream_project.data_quality_check_results_v1
GROUP BY check_status
ORDER BY check_status;


-- 작업 65-5: 실패, 미검증과 기록된 차이 확인
-- 실패 항목은 없어야 함
-- 미검증과 기준 건수 차이는 각각 한 항목 표시

SELECT
    check_id,
    target_table,
    checked_rows,
    failed_rows,
    check_status,
    check_description
FROM kream_project.data_quality_check_results_v1
WHERE check_status <> 'PASS'
ORDER BY check_status, check_id;