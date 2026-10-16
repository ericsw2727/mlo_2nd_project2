-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 13-1: 반복 검수 개정키의 원본 내용 비교
-- 입력: 복구된 bronze_inspection
-- 처리: 같은 INSP_ID + REV_NO 안에서 원본 내용 종류 계산
-- 출력: 동일 내용 반복 그룹과 내용 충돌 그룹의 수
-- 관리용 bronze_row_id, source_file은 비교에서 제외

WITH repeated_groups AS (
    SELECT
        INSP_ID,
        REV_NO,
        COUNT(*) AS rows_per_key,
        COUNT(DISTINCT
            COALESCE(HEX(INSP_ID), 'NULL'),
            COALESCE(HEX(REV_NO), 'NULL'),
            COALESCE(HEX(ITEM_STD_CODE), 'NULL'),
            COALESCE(HEX(ITEM_NM), 'NULL'),
            COALESCE(HEX(PARENT_CAT_ID), 'NULL'),
            COALESCE(HEX(TRADE_PRICE_KRW), 'NULL'),
            COALESCE(HEX(INSP_DURATION_MIN), 'NULL'),
            COALESCE(HEX(INSP_RESULT), 'NULL'),
            COALESCE(HEX(INSPECTOR_EMP_NO), 'NULL'),
            COALESCE(HEX(INBOUND_DT), 'NULL'),
            COALESCE(HEX(INSP_DONE_DT), 'NULL'),
            COALESCE(HEX(EXTRACTED_AT), 'NULL'),
            COALESCE(HEX(INSP_MEMO), 'NULL')
        ) AS raw_content_versions
    FROM kream_project_repro.bronze_inspection
    GROUP BY INSP_ID, REV_NO
    HAVING COUNT(*) > 1
)
SELECT
    COUNT(*) AS repeated_revision_key_groups,
    COALESCE(SUM(raw_content_versions = 1), 0)
        AS identical_content_groups,
    COALESCE(SUM(raw_content_versions > 1), 0)
        AS conflicting_content_groups,
    COALESCE(SUM(rows_per_key - 1), 0)
        AS additional_rows_for_same_key
FROM repeated_groups;


-- 작업 13-2: 같은 개정키의 내용 충돌 샘플 확인
-- 원본 내용이 다른 키 3개를 선정하고 해당 원본 행 조회
-- 데이터 수정·삭제 없음

WITH conflicting_keys AS (
    SELECT
        INSP_ID,
        REV_NO
    FROM kream_project_repro.bronze_inspection
    GROUP BY INSP_ID, REV_NO
    HAVING COUNT(*) > 1
       AND COUNT(DISTINCT
           COALESCE(HEX(INSP_ID), 'NULL'),
           COALESCE(HEX(REV_NO), 'NULL'),
           COALESCE(HEX(ITEM_STD_CODE), 'NULL'),
           COALESCE(HEX(ITEM_NM), 'NULL'),
           COALESCE(HEX(PARENT_CAT_ID), 'NULL'),
           COALESCE(HEX(TRADE_PRICE_KRW), 'NULL'),
           COALESCE(HEX(INSP_DURATION_MIN), 'NULL'),
           COALESCE(HEX(INSP_RESULT), 'NULL'),
           COALESCE(HEX(INSPECTOR_EMP_NO), 'NULL'),
           COALESCE(HEX(INBOUND_DT), 'NULL'),
           COALESCE(HEX(INSP_DONE_DT), 'NULL'),
           COALESCE(HEX(EXTRACTED_AT), 'NULL'),
           COALESCE(HEX(INSP_MEMO), 'NULL')
       ) > 1
    ORDER BY INSP_ID, REV_NO
    LIMIT 3
)
SELECT
    b.bronze_row_id,
    b.INSP_ID,
    b.REV_NO,
    b.ITEM_STD_CODE,
    b.ITEM_NM,
    b.PARENT_CAT_ID,
    b.TRADE_PRICE_KRW,
    b.INSP_DURATION_MIN,
    b.INSP_RESULT,
    b.INSPECTOR_EMP_NO,
    b.INBOUND_DT,
    b.INSP_DONE_DT,
    b.EXTRACTED_AT,
    b.INSP_MEMO
FROM kream_project_repro.bronze_inspection AS b
JOIN conflicting_keys AS c
  ON b.INSP_ID <=> c.INSP_ID
 AND b.REV_NO <=> c.REV_NO
ORDER BY b.INSP_ID, b.REV_NO, b.bronze_row_id;


-- 작업 13-3: 반복 개정키의 컬럼별 원본값 차이 집계
-- 입력: 같은 INSP_ID + REV_NO가 반복된 그룹
-- 처리: HEX로 대소문자·공백 등 원본 문자 차이 비교
-- 출력: 각 컬럼의 값이 다른 그룹 수
-- 한 그룹이 여러 컬럼에 중복 집계될 수 있음
-- 원본 수정 없음

WITH repeated_groups AS (
    SELECT
        INSP_ID,
        REV_NO,
        COUNT(DISTINCT COALESCE(HEX(ITEM_STD_CODE), 'NULL'))
            AS item_code_versions,
        COUNT(DISTINCT COALESCE(HEX(ITEM_NM), 'NULL'))
            AS item_name_versions,
        COUNT(DISTINCT COALESCE(HEX(PARENT_CAT_ID), 'NULL'))
            AS category_versions,
        COUNT(DISTINCT COALESCE(HEX(TRADE_PRICE_KRW), 'NULL'))
            AS price_versions,
        COUNT(DISTINCT COALESCE(HEX(INSP_DURATION_MIN), 'NULL'))
            AS duration_versions,
        COUNT(DISTINCT COALESCE(HEX(INSP_RESULT), 'NULL'))
            AS result_versions,
        COUNT(DISTINCT COALESCE(HEX(INSPECTOR_EMP_NO), 'NULL'))
            AS employee_versions,
        COUNT(DISTINCT COALESCE(HEX(INBOUND_DT), 'NULL'))
            AS inbound_versions,
        COUNT(DISTINCT COALESCE(HEX(INSP_DONE_DT), 'NULL'))
            AS done_versions,
        COUNT(DISTINCT COALESCE(HEX(EXTRACTED_AT), 'NULL'))
            AS extracted_versions,
        COUNT(DISTINCT COALESCE(HEX(INSP_MEMO), 'NULL'))
            AS memo_versions
    FROM kream_project_repro.bronze_inspection
    GROUP BY INSP_ID, REV_NO
    HAVING COUNT(*) > 1
)
SELECT 'ITEM_STD_CODE' AS column_name,
       COUNT(*) AS differing_groups
FROM repeated_groups WHERE item_code_versions > 1
UNION ALL
SELECT 'ITEM_NM', COUNT(*)
FROM repeated_groups WHERE item_name_versions > 1
UNION ALL
SELECT 'PARENT_CAT_ID', COUNT(*)
FROM repeated_groups WHERE category_versions > 1
UNION ALL
SELECT 'TRADE_PRICE_KRW', COUNT(*)
FROM repeated_groups WHERE price_versions > 1
UNION ALL
SELECT 'INSP_DURATION_MIN', COUNT(*)
FROM repeated_groups WHERE duration_versions > 1
UNION ALL
SELECT 'INSP_RESULT', COUNT(*)
FROM repeated_groups WHERE result_versions > 1
UNION ALL
SELECT 'INSPECTOR_EMP_NO', COUNT(*)
FROM repeated_groups WHERE employee_versions > 1
UNION ALL
SELECT 'INBOUND_DT', COUNT(*)
FROM repeated_groups WHERE inbound_versions > 1
UNION ALL
SELECT 'INSP_DONE_DT', COUNT(*)
FROM repeated_groups WHERE done_versions > 1
UNION ALL
SELECT 'EXTRACTED_AT', COUNT(*)
FROM repeated_groups WHERE extracted_versions > 1
UNION ALL
SELECT 'INSP_MEMO', COUNT(*)
FROM repeated_groups WHERE memo_versions > 1;


-- 작업 13-4: 검수 ID·개정 번호의 누락 및 번호 형식 검사
-- 목적: 개정 이력을 분석하기 전에 키의 기본 상태 확인
-- 형식 기준 후보: 1부터 시작하는 양의 정수 문자열
-- 최종 허용 규칙은 명세서와 대조 필요
-- 원본 수정 없음

SELECT
    COUNT(*) AS total_rows,
    SUM(
        CASE WHEN NULLIF(TRIM(INSP_ID), '') IS NULL
             THEN 1 ELSE 0 END
    ) AS missing_inspection_id_rows,
    SUM(
        CASE WHEN NULLIF(TRIM(REV_NO), '') IS NULL
             THEN 1 ELSE 0 END
    ) AS missing_revision_rows,
    SUM(
        CASE
            WHEN NULLIF(TRIM(REV_NO), '') IS NOT NULL
             AND NOT REGEXP_LIKE(REV_NO, '^[1-9][0-9]*$')
            THEN 1 ELSE 0
        END
    ) AS nonstandard_revision_rows
FROM kream_project_repro.bronze_inspection;


-- 작업 13-5: 개정 번호의 원문 분포 확인
-- 목적: 실제 개정 번호 종류와 각 번호의 수신 행 수 확인
-- HEX로 공백 등 실제 문자 차이 구분
-- 중복·충돌을 포함한 수신 행 기준
-- 원본 수정 없음

SELECT
    REV_NO,
    HEX(REV_NO) AS raw_revision_hex,
    COUNT(*) AS row_count
FROM kream_project_repro.bronze_inspection
GROUP BY REV_NO, HEX(REV_NO)
ORDER BY raw_revision_hex;


-- 작업 13-6: 검수 ID별 개정 구성 확인
-- 원본 ID의 실제 문자 기준으로 묶음
-- 개정 2만 존재하는 ID와 개정 1·2가 모두 있는 ID 구분

WITH revision_counts AS (
    SELECT
        HEX(INSP_ID) AS id_hex,
        SUM(REV_NO = '1') AS revision_1_rows,
        SUM(REV_NO = '2') AS revision_2_rows
    FROM kream_project_repro.bronze_inspection
    GROUP BY HEX(INSP_ID)
),
classified AS (
    SELECT
        *,
        CASE
            WHEN revision_1_rows > 0 AND revision_2_rows > 0
                THEN 'BOTH_REV_1_AND_2'
            WHEN revision_1_rows > 0
                THEN 'ONLY_REV_1'
            WHEN revision_2_rows > 0
                THEN 'ONLY_REV_2'
            ELSE 'OTHER'
        END AS revision_structure
    FROM revision_counts
)
SELECT
    revision_structure,
    COUNT(*) AS inspection_id_count,
    SUM(revision_1_rows) AS revision_1_rows,
    SUM(revision_2_rows) AS revision_2_rows,
    SUM(revision_1_rows + revision_2_rows) AS total_rows
FROM classified
GROUP BY revision_structure
ORDER BY revision_structure;


-- 작업 13-7: 개정 1·2 비교 샘플
-- 양쪽 개정에 각각 정확히 1행이 있는 ID에서 5개 선정
-- 반복·충돌이 있는 ID는 이 샘플에서만 제외하며,
-- 전체 데이터의 처리 대상에서 제외하는 것은 아님
-- 날짜는 원문 그대로 조회하며 최신 여부를 아직 판정하지 않음

WITH sample_pairs AS (
    SELECT
        HEX(INSP_ID) AS id_hex,
        MAX(CASE WHEN REV_NO = '1'
                 THEN bronze_row_id END) AS revision_1_row_id,
        MAX(CASE WHEN REV_NO = '2'
                 THEN bronze_row_id END) AS revision_2_row_id
    FROM kream_project_repro.bronze_inspection
    GROUP BY HEX(INSP_ID)
    HAVING SUM(REV_NO = '1') = 1
       AND SUM(REV_NO = '2') = 1
    ORDER BY id_hex
    LIMIT 5
)
SELECT
    a.INSP_ID,
    a.bronze_row_id AS revision_1_row_id,
    b.bronze_row_id AS revision_2_row_id,
    a.TRADE_PRICE_KRW AS price_rev_1,
    b.TRADE_PRICE_KRW AS price_rev_2,
    a.INSP_RESULT AS result_rev_1,
    b.INSP_RESULT AS result_rev_2,
    a.INSP_DURATION_MIN AS duration_rev_1,
    b.INSP_DURATION_MIN AS duration_rev_2,
    a.INSPECTOR_EMP_NO AS inspector_rev_1,
    b.INSPECTOR_EMP_NO AS inspector_rev_2,
    a.INSP_DONE_DT AS done_rev_1,
    b.INSP_DONE_DT AS done_rev_2,
    a.EXTRACTED_AT AS extracted_rev_1,
    b.EXTRACTED_AT AS extracted_rev_2,
    a.INSP_MEMO AS memo_rev_1,
    b.INSP_MEMO AS memo_rev_2
FROM sample_pairs AS p
JOIN kream_project_repro.bronze_inspection AS a
  ON a.bronze_row_id = p.revision_1_row_id
JOIN kream_project_repro.bronze_inspection AS b
  ON b.bronze_row_id = p.revision_2_row_id
ORDER BY p.id_hex;


-- 작업 13-8: 전체 개정 1·2의 컬럼별 원문 차이 집계
-- 양쪽 개정에 각각 1행이 있는 ID만 비교
-- HEX와 <=>로 실제 문자 차이 및 NULL 차이 비교
-- 개정 번호 자체는 비교 항목에서 제외
-- 원본 수정 없음

WITH pairs AS (
    SELECT
        HEX(INSP_ID) AS id_hex,
        MAX(CASE WHEN REV_NO = '1'
                 THEN bronze_row_id END) AS row_1,
        MAX(CASE WHEN REV_NO = '2'
                 THEN bronze_row_id END) AS row_2
    FROM kream_project_repro.bronze_inspection
    GROUP BY HEX(INSP_ID)
    HAVING SUM(REV_NO = '1') = 1
       AND SUM(REV_NO = '2') = 1
),
differences AS (
    SELECT
        NOT (HEX(a.ITEM_STD_CODE) <=> HEX(b.ITEM_STD_CODE))
            AS item_code_changed,
        NOT (HEX(a.ITEM_NM) <=> HEX(b.ITEM_NM))
            AS item_name_changed,
        NOT (HEX(a.PARENT_CAT_ID) <=> HEX(b.PARENT_CAT_ID))
            AS category_changed,
        NOT (HEX(a.TRADE_PRICE_KRW) <=> HEX(b.TRADE_PRICE_KRW))
            AS price_changed,
        NOT (HEX(a.INSP_DURATION_MIN) <=> HEX(b.INSP_DURATION_MIN))
            AS duration_changed,
        NOT (HEX(a.INSP_RESULT) <=> HEX(b.INSP_RESULT))
            AS result_changed,
        NOT (HEX(a.INSPECTOR_EMP_NO) <=> HEX(b.INSPECTOR_EMP_NO))
            AS inspector_changed,
        NOT (HEX(a.INBOUND_DT) <=> HEX(b.INBOUND_DT))
            AS inbound_changed,
        NOT (HEX(a.INSP_DONE_DT) <=> HEX(b.INSP_DONE_DT))
            AS done_changed,
        NOT (HEX(a.EXTRACTED_AT) <=> HEX(b.EXTRACTED_AT))
            AS extracted_changed,
        NOT (HEX(a.INSP_MEMO) <=> HEX(b.INSP_MEMO))
            AS memo_changed
    FROM pairs AS p
    JOIN kream_project_repro.bronze_inspection AS a
      ON a.bronze_row_id = p.row_1
    JOIN kream_project_repro.bronze_inspection AS b
      ON b.bronze_row_id = p.row_2
)
SELECT 'COMPARED_PAIRS' AS check_item, COUNT(*) AS pair_count
FROM differences
UNION ALL
SELECT 'ITEM_STD_CODE', COALESCE(SUM(item_code_changed), 0)
FROM differences
UNION ALL
SELECT 'ITEM_NM', COALESCE(SUM(item_name_changed), 0)
FROM differences
UNION ALL
SELECT 'PARENT_CAT_ID', COALESCE(SUM(category_changed), 0)
FROM differences
UNION ALL
SELECT 'TRADE_PRICE_KRW', COALESCE(SUM(price_changed), 0)
FROM differences
UNION ALL
SELECT 'INSP_DURATION_MIN', COALESCE(SUM(duration_changed), 0)
FROM differences
UNION ALL
SELECT 'INSP_RESULT', COALESCE(SUM(result_changed), 0)
FROM differences
UNION ALL
SELECT 'INSPECTOR_EMP_NO', COALESCE(SUM(inspector_changed), 0)
FROM differences
UNION ALL
SELECT 'INBOUND_DT', COALESCE(SUM(inbound_changed), 0)
FROM differences
UNION ALL
SELECT 'INSP_DONE_DT', COALESCE(SUM(done_changed), 0)
FROM differences
UNION ALL
SELECT 'EXTRACTED_AT', COALESCE(SUM(extracted_changed), 0)
FROM differences
UNION ALL
SELECT 'INSP_MEMO', COALESCE(SUM(memo_changed), 0)
FROM differences
UNION ALL
SELECT
    'ALL_BUSINESS_FIELDS_IDENTICAL',
    COUNT(*)
FROM differences
WHERE item_code_changed = 0
  AND item_name_changed = 0
  AND category_changed = 0
  AND price_changed = 0
  AND duration_changed = 0
  AND result_changed = 0
  AND inspector_changed = 0
  AND inbound_changed = 0
  AND done_changed = 0
  AND extracted_changed = 0
  AND memo_changed = 0;


-- 작업 13-9: 전체 개정 1 → 2의 판정 전환 분포
-- 판정이 같아도 다른 컬럼이 바뀔 수 있으므로
-- 같은 판정을 단순 재전송으로 확정하지 않음

WITH pairs AS (
    SELECT
        HEX(INSP_ID) AS id_hex,
        MAX(CASE WHEN REV_NO = '1'
                 THEN bronze_row_id END) AS row_1,
        MAX(CASE WHEN REV_NO = '2'
                 THEN bronze_row_id END) AS row_2
    FROM kream_project_repro.bronze_inspection
    GROUP BY HEX(INSP_ID)
    HAVING SUM(REV_NO = '1') = 1
       AND SUM(REV_NO = '2') = 1
)
SELECT
    a.INSP_RESULT AS result_rev_1,
    b.INSP_RESULT AS result_rev_2,
    COUNT(*) AS pair_count
FROM pairs AS p
JOIN kream_project_repro.bronze_inspection AS a
  ON a.bronze_row_id = p.row_1
JOIN kream_project_repro.bronze_inspection AS b
  ON b.bronze_row_id = p.row_2
GROUP BY
    a.INSP_RESULT, HEX(a.INSP_RESULT),
    b.INSP_RESULT, HEX(b.INSP_RESULT)
ORDER BY pair_count DESC, result_rev_1, result_rev_2;


-- 작업 13-10: 날짜 형식 및 실제 달력·시간 유효성 검사
-- 대상: INBOUND_DT, INSP_DONE_DT, EXTRACTED_AT
-- 현재 검사하는 형식:
-- YYYY-MM-DD HH:MM:SS / YYYY/MM/DD HH:MM:SS
-- 다른 형식은 자동으로 오류 확정하지 않고 별도 검토 대상으로 분류
-- DB 자료형 범위와 업무상 시간 순서는 이후 별도 검사
-- 원본 수정 없음

WITH date_values AS (
    SELECT
        bronze_row_id,
        'INBOUND_DT' AS column_name,
        INBOUND_DT AS raw_value
    FROM kream_project_repro.bronze_inspection

    UNION ALL

    SELECT
        bronze_row_id,
        'INSP_DONE_DT',
        INSP_DONE_DT
    FROM kream_project_repro.bronze_inspection

    UNION ALL

    SELECT
        bronze_row_id,
        'EXTRACTED_AT',
        EXTRACTED_AT
    FROM kream_project_repro.bronze_inspection
),
formats AS (
    SELECT
        *,
        CASE
            WHEN COALESCE(LOWER(TRIM(raw_value)), '') IN (
                '', 'null', 'none', 'na', 'n/a', 'nan', '-'
            )
            THEN 'MISSING_TOKEN'

            WHEN REGEXP_LIKE(
                raw_value,
                '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$'
            )
            THEN 'HYPHEN_DATETIME'

            WHEN REGEXP_LIKE(
                raw_value,
                '^[0-9]{4}/[0-9]{2}/[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$'
            )
            THEN 'SLASH_DATETIME'

            ELSE 'OTHER_FORMAT'
        END AS date_format
    FROM date_values
),
parts AS (
    SELECT
        *,
        CASE WHEN date_format IN (
            'HYPHEN_DATETIME', 'SLASH_DATETIME'
        ) THEN CAST(SUBSTRING(raw_value, 1, 4) AS UNSIGNED)
        END AS year_part,

        CASE WHEN date_format IN (
            'HYPHEN_DATETIME', 'SLASH_DATETIME'
        ) THEN CAST(SUBSTRING(raw_value, 6, 2) AS UNSIGNED)
        END AS month_part,

        CASE WHEN date_format IN (
            'HYPHEN_DATETIME', 'SLASH_DATETIME'
        ) THEN CAST(SUBSTRING(raw_value, 9, 2) AS UNSIGNED)
        END AS day_part,

        CASE WHEN date_format IN (
            'HYPHEN_DATETIME', 'SLASH_DATETIME'
        ) THEN CAST(SUBSTRING(raw_value, 12, 2) AS UNSIGNED)
        END AS hour_part,

        CASE WHEN date_format IN (
            'HYPHEN_DATETIME', 'SLASH_DATETIME'
        ) THEN CAST(SUBSTRING(raw_value, 15, 2) AS UNSIGNED)
        END AS minute_part,

        CASE WHEN date_format IN (
            'HYPHEN_DATETIME', 'SLASH_DATETIME'
        ) THEN CAST(SUBSTRING(raw_value, 18, 2) AS UNSIGNED)
        END AS second_part
    FROM formats
),
checked AS (
    SELECT
        *,
        CASE
            WHEN date_format = 'MISSING_TOKEN'
            THEN 'MISSING'

            WHEN date_format = 'OTHER_FORMAT'
            THEN 'FORMAT_REVIEW'

            WHEN year_part BETWEEN 1 AND 9999
             AND month_part BETWEEN 1 AND 12
             AND day_part BETWEEN 1 AND
                CASE
                    WHEN month_part = 2 THEN
                        CASE
                            WHEN MOD(year_part, 400) = 0
                              OR (
                                  MOD(year_part, 4) = 0
                                  AND MOD(year_part, 100) <> 0
                              )
                            THEN 29 ELSE 28
                        END
                    WHEN month_part IN (4, 6, 9, 11)
                    THEN 30
                    ELSE 31
                END
             AND hour_part BETWEEN 0 AND 23
             AND minute_part BETWEEN 0 AND 59
             AND second_part BETWEEN 0 AND 59
            THEN 'CALENDAR_TIME_VALID'

            ELSE 'INVALID_DATE_OR_TIME'
        END AS validation_status
    FROM parts
)
SELECT
    column_name,
    date_format,
    validation_status,
    COUNT(*) AS row_count,
    MIN(bronze_row_id) AS example_row_id
FROM checked
GROUP BY column_name, date_format, validation_status
ORDER BY column_name, date_format, validation_status;


-- 작업 13-11: 추가 확인이 필요한 날짜의 표기 조사
-- 숫자를 #으로 바꿔 같은 표기 형태끼리 집계
-- 예: 2026.10.14 → ####.##.##
-- 예시값은 해당 형태에 속한 원본값을 보여줌
-- 날짜 보정·변환·삭제 없음

WITH date_values AS (
    SELECT
        'INBOUND_DT' AS column_name,
        INBOUND_DT AS raw_value
    FROM kream_project_repro.bronze_inspection

    UNION ALL

    SELECT
        'INSP_DONE_DT',
        INSP_DONE_DT
    FROM kream_project_repro.bronze_inspection
),
review_values AS (
    SELECT
        column_name,
        raw_value
    FROM date_values
    WHERE COALESCE(LOWER(TRIM(raw_value)), '') NOT IN (
        '', 'null', 'none', 'na', 'n/a', 'nan', '-'
    )
      AND NOT REGEXP_LIKE(
          raw_value,
          '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$'
      )
      AND NOT REGEXP_LIKE(
          raw_value,
          '^[0-9]{4}/[0-9]{2}/[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$'
      )
),
shapes AS (
    SELECT
        column_name,
        raw_value,
        REGEXP_REPLACE(raw_value, '[0-9]', '#') AS format_pattern
    FROM review_values
)
SELECT
    column_name,
    format_pattern,
    COUNT(*) AS row_count,
    MIN(raw_value) AS example_value_1,
    MAX(raw_value) AS example_value_2
FROM shapes
GROUP BY column_name, format_pattern
ORDER BY column_name, row_count DESC, format_pattern;


-- 작업 13-12: 확인된 날짜 형식 전체의 달력·시간 유효성 검사
-- 숫자 14자리: YYYYMMDDHHMMSS 형식 후보로 검사
-- T/Z 형식: UTC 표시를 별도 기록하며 시간대 변환하지 않음
-- 원본 수정 없음
-- 형식 해석·시간대·DB 자료형 범위는 명세서와 추가 대조 필요

WITH date_values AS (
    SELECT
        'INBOUND_DT' AS column_name,
        INBOUND_DT AS raw_value
    FROM kream_project_repro.bronze_inspection

    UNION ALL

    SELECT 'INSP_DONE_DT', INSP_DONE_DT
    FROM kream_project_repro.bronze_inspection

    UNION ALL

    SELECT 'EXTRACTED_AT', EXTRACTED_AT
    FROM kream_project_repro.bronze_inspection
),
formats AS (
    SELECT
        *,
        CASE
            WHEN COALESCE(LOWER(TRIM(raw_value)), '') IN (
                '', 'null', 'none', 'na', 'n/a', 'nan', '-'
            ) THEN 'MISSING_TOKEN'

            WHEN REGEXP_LIKE(
                raw_value,
                '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$'
            ) THEN 'HYPHEN_DATETIME'

            WHEN REGEXP_LIKE(
                raw_value,
                '^[0-9]{4}/[0-9]{2}/[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$'
            ) THEN 'SLASH_DATETIME'

            WHEN REGEXP_LIKE(
                raw_value,
                '^[0-9]{4}[.][0-9]{2}[.][0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$'
            ) THEN 'DOT_DATETIME'

            WHEN REGEXP_LIKE(
                raw_value, '^[0-9]{14}$'
            ) THEN 'COMPACT_DATETIME'

            WHEN REGEXP_LIKE(
                raw_value,
                '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$',
                'c'
            ) THEN 'ISO_UTC'

            ELSE 'OTHER_FORMAT'
        END AS date_format
    FROM date_values
),
normalized AS (
    SELECT
        *,
        CASE date_format
            WHEN 'HYPHEN_DATETIME' THEN raw_value
            WHEN 'SLASH_DATETIME' THEN REPLACE(raw_value, '/', '-')
            WHEN 'DOT_DATETIME' THEN REPLACE(raw_value, '.', '-')

            WHEN 'COMPACT_DATETIME' THEN CONCAT(
                SUBSTRING(raw_value, 1, 4), '-',
                SUBSTRING(raw_value, 5, 2), '-',
                SUBSTRING(raw_value, 7, 2), ' ',
                SUBSTRING(raw_value, 9, 2), ':',
                SUBSTRING(raw_value, 11, 2), ':',
                SUBSTRING(raw_value, 13, 2)
            )

            -- 표기만 변환하며 UTC 시각 자체는 바꾸지 않음
            WHEN 'ISO_UTC'
                THEN REPLACE(LEFT(raw_value, 19), 'T', ' ')

            ELSE NULL
        END AS normalized_text,

        CASE
            WHEN date_format = 'ISO_UTC' THEN 'UTC'
            WHEN date_format IN ('MISSING_TOKEN', 'OTHER_FORMAT')
                THEN 'UNDETERMINED'
            ELSE 'UNSPECIFIED_IN_VALUE'
        END AS timezone_marker
    FROM formats
),
parts AS (
    SELECT
        *,
        CAST(SUBSTRING(normalized_text, 1, 4) AS UNSIGNED)
            AS year_part,
        CAST(SUBSTRING(normalized_text, 6, 2) AS UNSIGNED)
            AS month_part,
        CAST(SUBSTRING(normalized_text, 9, 2) AS UNSIGNED)
            AS day_part,
        CAST(SUBSTRING(normalized_text, 12, 2) AS UNSIGNED)
            AS hour_part,
        CAST(SUBSTRING(normalized_text, 15, 2) AS UNSIGNED)
            AS minute_part,
        CAST(SUBSTRING(normalized_text, 18, 2) AS UNSIGNED)
            AS second_part
    FROM normalized
),
checked AS (
    SELECT
        *,
        CASE
            WHEN date_format = 'MISSING_TOKEN'
                THEN 'MISSING'
            WHEN date_format = 'OTHER_FORMAT'
                THEN 'FORMAT_REVIEW'

            WHEN year_part BETWEEN 1 AND 9999
             AND month_part BETWEEN 1 AND 12
             AND day_part BETWEEN 1 AND
                CASE
                    WHEN month_part = 2 THEN
                        CASE
                            WHEN MOD(year_part, 400) = 0
                              OR (
                                  MOD(year_part, 4) = 0
                                  AND MOD(year_part, 100) <> 0
                              )
                            THEN 29 ELSE 28
                        END
                    WHEN month_part IN (4, 6, 9, 11) THEN 30
                    ELSE 31
                END
             AND hour_part BETWEEN 0 AND 23
             AND minute_part BETWEEN 0 AND 59
             AND second_part BETWEEN 0 AND 59
                THEN 'CALENDAR_TIME_VALID'

            ELSE 'INVALID_DATE_OR_TIME'
        END AS validation_status
    FROM parts
)
SELECT
    column_name,
    date_format,
    timezone_marker,
    validation_status,
    COUNT(*) AS row_count
FROM checked
GROUP BY
    column_name,
    date_format,
    timezone_marker,
    validation_status
ORDER BY column_name, date_format, validation_status;


-- 작업 13-13: 날짜를 KST로 해석하는 AS-IS 검사 뷰
-- 전제: 13-12에서 현재 데이터의 날짜 유효성 확인 완료
-- 규칙:
-- 1. 시간대 표시 없음 → KST
-- 2. Z 표시 → UTC이므로 9시간을 더해 KST로 변환
-- 3. 원본값은 Bronze에 그대로 보존

CREATE OR REPLACE VIEW
    kream_project_repro.asis_inspection_datetime_check_v1 AS
WITH date_values AS (
    SELECT
        bronze_row_id, INSP_ID, REV_NO,
        'INBOUND_DT' AS column_name,
        INBOUND_DT AS raw_value
    FROM kream_project_repro.bronze_inspection

    UNION ALL

    SELECT
        bronze_row_id, INSP_ID, REV_NO,
        'INSP_DONE_DT', INSP_DONE_DT
    FROM kream_project_repro.bronze_inspection

    UNION ALL

    SELECT
        bronze_row_id, INSP_ID, REV_NO,
        'EXTRACTED_AT', EXTRACTED_AT
    FROM kream_project_repro.bronze_inspection
),
converted AS (
    SELECT
        bronze_row_id, INSP_ID, REV_NO, column_name,

        CASE
            WHEN REGEXP_LIKE(
                raw_value,
                '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$',
                'c'
            )
            THEN DATE_ADD(
                STR_TO_DATE(raw_value, '%Y-%m-%dT%H:%i:%sZ'),
                INTERVAL 9 HOUR
            )

            WHEN REGEXP_LIKE(raw_value, '^[0-9]{14}$')
            THEN STR_TO_DATE(raw_value, '%Y%m%d%H%i%s')

            WHEN REGEXP_LIKE(
                raw_value,
                '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$'
            )
            THEN STR_TO_DATE(raw_value, '%Y-%m-%d %H:%i:%s')

            WHEN REGEXP_LIKE(
                raw_value,
                '^[0-9]{4}/[0-9]{2}/[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$'
            )
            THEN STR_TO_DATE(raw_value, '%Y/%m/%d %H:%i:%s')

            WHEN REGEXP_LIKE(
                raw_value,
                '^[0-9]{4}[.][0-9]{2}[.][0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$'
            )
            THEN STR_TO_DATE(raw_value, '%Y.%m.%d %H:%i:%s')

            ELSE NULL
        END AS value_kst
    FROM date_values
)
SELECT
    bronze_row_id,
    INSP_ID,
    REV_NO,
    MAX(CASE WHEN column_name = 'INBOUND_DT'
             THEN value_kst END) AS inbound_dt_kst,
    MAX(CASE WHEN column_name = 'INSP_DONE_DT'
             THEN value_kst END) AS insp_done_dt_kst,
    MAX(CASE WHEN column_name = 'EXTRACTED_AT'
             THEN value_kst END) AS extracted_at_kst
FROM converted
GROUP BY bronze_row_id, INSP_ID, REV_NO;


-- 작업 13-14: 변환 성공 및 시간 역전 건수
-- 두 시간 역전 조건은 같은 행에 겹칠 수 있으므로
-- 아래 개별 건수를 더해 문제 행 수로 사용하지 않음

SELECT
    COUNT(*) AS total_rows,

    SUM(
        inbound_dt_kst IS NULL
        OR insp_done_dt_kst IS NULL
        OR extracted_at_kst IS NULL
    ) AS conversion_failed_rows,

    SUM(
        CASE WHEN insp_done_dt_kst < inbound_dt_kst
             THEN 1 ELSE 0 END
    ) AS done_before_inbound_rows,

    SUM(
        CASE WHEN extracted_at_kst < insp_done_dt_kst
             THEN 1 ELSE 0 END
    ) AS extracted_before_done_rows,

    SUM(
        CASE
            WHEN inbound_dt_kst IS NOT NULL
             AND insp_done_dt_kst IS NOT NULL
             AND extracted_at_kst IS NOT NULL
             AND insp_done_dt_kst >= inbound_dt_kst
             AND extracted_at_kst >= insp_done_dt_kst
            THEN 1 ELSE 0
        END
    ) AS chronological_order_ok_rows

FROM kream_project_repro.asis_inspection_datetime_check_v1;


-- 작업 13-15: 시간 문제 샘플
-- 대표 문제별 최대 3행
-- 원본값과 KST 변환값을 함께 확인

WITH classified AS (
    SELECT
        d.*,
        CASE
            WHEN inbound_dt_kst IS NULL
              OR insp_done_dt_kst IS NULL
              OR extracted_at_kst IS NULL
            THEN 'CONVERSION_FAILED'

            WHEN insp_done_dt_kst < inbound_dt_kst
            THEN 'DONE_BEFORE_INBOUND'

            WHEN extracted_at_kst < insp_done_dt_kst
            THEN 'EXTRACTED_BEFORE_DONE'

            ELSE 'ORDER_OK'
        END AS primary_time_issue
    FROM kream_project_repro.asis_inspection_datetime_check_v1 AS d
),
samples AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY primary_time_issue
            ORDER BY bronze_row_id
        ) AS sample_no
    FROM classified
    WHERE primary_time_issue <> 'ORDER_OK'
)
SELECT
    s.bronze_row_id,
    s.INSP_ID,
    s.REV_NO,
    s.primary_time_issue,
    b.INBOUND_DT AS inbound_raw,
    s.inbound_dt_kst,
    b.INSP_DONE_DT AS done_raw,
    s.insp_done_dt_kst,
    b.EXTRACTED_AT AS extracted_raw,
    s.extracted_at_kst
FROM samples AS s
JOIN kream_project_repro.bronze_inspection AS b
  ON b.bronze_row_id = s.bronze_row_id
WHERE s.sample_no <= 3
ORDER BY s.primary_time_issue, s.bronze_row_id;


-- 작업 13-16: 개정별 시간 검사 결과
-- 각 행은 한 분류에만 속함
-- 두 역전 조건에 동시에 해당하는 경우도 별도 표시
-- 아직 격리·제외를 실행하지 않음

WITH classified AS (
    SELECT
        REV_NO,
        CASE
            WHEN inbound_dt_kst IS NULL
              OR insp_done_dt_kst IS NULL
              OR extracted_at_kst IS NULL
            THEN 'CONVERSION_FAILED'

            WHEN insp_done_dt_kst < inbound_dt_kst
             AND extracted_at_kst < insp_done_dt_kst
            THEN 'BOTH_TIME_REVERSALS'

            WHEN insp_done_dt_kst < inbound_dt_kst
            THEN 'DONE_BEFORE_INBOUND'

            WHEN extracted_at_kst < insp_done_dt_kst
            THEN 'EXTRACTED_BEFORE_DONE'

            ELSE 'ORDER_OK'
        END AS time_check_status
    FROM kream_project_repro.asis_inspection_datetime_check_v1
)
SELECT
    REV_NO,
    time_check_status,
    COUNT(*) AS row_count
FROM classified
GROUP BY REV_NO, time_check_status
ORDER BY REV_NO, time_check_status;


-- 작업 13-17: 개정 1·2의 시각 순서 비교
-- 양쪽 개정에 각각 1행이 있는 22,600쌍 대상
-- 추출 시각 함정과 개정 간 완료 시각의 관계 확인
-- 시각이 늦다는 이유로 최신 상태를 선택하지 않음

WITH pairs AS (
    SELECT
        HEX(INSP_ID) AS id_hex,
        MAX(CASE WHEN REV_NO = '1'
                 THEN bronze_row_id END) AS row_1,
        MAX(CASE WHEN REV_NO = '2'
                 THEN bronze_row_id END) AS row_2
    FROM kream_project_repro.bronze_inspection
    GROUP BY HEX(INSP_ID)
    HAVING SUM(REV_NO = '1') = 1
       AND SUM(REV_NO = '2') = 1
),
compared AS (
    SELECT
        CASE
            WHEN a.insp_done_dt_kst IS NULL
              OR b.insp_done_dt_kst IS NULL
            THEN 'UNCOMPARABLE'
            WHEN b.insp_done_dt_kst > a.insp_done_dt_kst
            THEN 'REV_2_LATER'
            WHEN b.insp_done_dt_kst = a.insp_done_dt_kst
            THEN 'SAME_TIME'
            ELSE 'REV_2_EARLIER'
        END AS done_time_relation,

        CASE
            WHEN a.extracted_at_kst IS NULL
              OR b.extracted_at_kst IS NULL
            THEN 'UNCOMPARABLE'
            WHEN b.extracted_at_kst > a.extracted_at_kst
            THEN 'REV_2_LATER'
            WHEN b.extracted_at_kst = a.extracted_at_kst
            THEN 'SAME_TIME'
            ELSE 'REV_2_EARLIER'
        END AS extracted_time_relation

    FROM pairs AS p
    JOIN kream_project_repro.asis_inspection_datetime_check_v1 AS a
      ON a.bronze_row_id = p.row_1
    JOIN kream_project_repro.asis_inspection_datetime_check_v1 AS b
      ON b.bronze_row_id = p.row_2
)
SELECT
    done_time_relation,
    extracted_time_relation,
    COUNT(*) AS pair_count
FROM compared
GROUP BY done_time_relation, extracted_time_relation
ORDER BY done_time_relation, extracted_time_relation;


-- 작업 13-18: 개정 1의 시간 문제와 추출 시각 함정 대조
-- 대상: 개정 1·2가 각각 1행씩 있는 검수 ID
-- 목적: 이전 개정 제외와 불량 행 격리의 처리 순서 검토
-- 원본 수정 없음

WITH pairs AS (
    SELECT
        HEX(INSP_ID) AS id_hex,
        MAX(CASE WHEN REV_NO = '1'
                 THEN bronze_row_id END) AS row_1,
        MAX(CASE WHEN REV_NO = '2'
                 THEN bronze_row_id END) AS row_2
    FROM kream_project_repro.bronze_inspection
    GROUP BY HEX(INSP_ID)
    HAVING SUM(REV_NO = '1') = 1
       AND SUM(REV_NO = '2') = 1
),
classified AS (
    SELECT
        CASE
            WHEN a.inbound_dt_kst IS NULL
              OR a.insp_done_dt_kst IS NULL
              OR a.extracted_at_kst IS NULL
            THEN 'CONVERSION_FAILED'

            WHEN a.insp_done_dt_kst < a.inbound_dt_kst
             AND a.extracted_at_kst < a.insp_done_dt_kst
            THEN 'BOTH_TIME_REVERSALS'

            WHEN a.insp_done_dt_kst < a.inbound_dt_kst
            THEN 'DONE_BEFORE_INBOUND'

            WHEN a.extracted_at_kst < a.insp_done_dt_kst
            THEN 'EXTRACTED_BEFORE_DONE'

            ELSE 'ORDER_OK'
        END AS revision_1_time_status,

        CASE
            WHEN a.extracted_at_kst IS NULL
              OR b.extracted_at_kst IS NULL
            THEN 'UNCOMPARABLE'

            WHEN a.extracted_at_kst > b.extracted_at_kst
            THEN 'REV_1_EXTRACTED_LATER'

            WHEN a.extracted_at_kst = b.extracted_at_kst
            THEN 'SAME_EXTRACTION_TIME'

            ELSE 'REV_2_EXTRACTED_LATER'
        END AS extraction_relation

    FROM pairs AS p
    JOIN kream_project_repro.asis_inspection_datetime_check_v1 AS a
      ON a.bronze_row_id = p.row_1
    JOIN kream_project_repro.asis_inspection_datetime_check_v1 AS b
      ON b.bronze_row_id = p.row_2
)
SELECT
    revision_1_time_status,
    extraction_relation,
    COUNT(*) AS pair_count
FROM classified
GROUP BY revision_1_time_status, extraction_relation
ORDER BY revision_1_time_status, extraction_relation;
