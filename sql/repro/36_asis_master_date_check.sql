-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 36-1: 마스터 날짜의 달력·시간 유효성 검사
-- 대상: 검수원 HIRE_DT, 카테고리 REG_DT
-- 조회만 수행하며 시각 제거·날짜 보정 없음
-- DATE_ONLY는 날짜만, DATETIME은 시각까지 검사

WITH date_values AS (
    SELECT
        'INSPECTOR_MASTER' AS source_name,
        'HIRE_DT' AS column_name,
        HIRE_DT AS raw_value
    FROM kream_project_repro.bronze_inspector_master

    UNION ALL

    SELECT
        'CATEGORY_MASTER', 'REG_DT', REG_DT
    FROM kream_project_repro.bronze_category_parent_lookup
),
formats AS (
    SELECT
        *,
        CASE
            WHEN NULLIF(TRIM(raw_value), '') IS NULL
            THEN 'MISSING'

            WHEN REGEXP_LIKE(
                raw_value,
                '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
            )
            THEN 'DATE_ONLY'

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
            'DATE_ONLY', 'HYPHEN_DATETIME', 'SLASH_DATETIME'
        ) THEN CAST(SUBSTRING(raw_value, 1, 4) AS UNSIGNED)
        END AS y,

        CASE WHEN date_format IN (
            'DATE_ONLY', 'HYPHEN_DATETIME', 'SLASH_DATETIME'
        ) THEN CAST(SUBSTRING(raw_value, 6, 2) AS UNSIGNED)
        END AS m,

        CASE WHEN date_format IN (
            'DATE_ONLY', 'HYPHEN_DATETIME', 'SLASH_DATETIME'
        ) THEN CAST(SUBSTRING(raw_value, 9, 2) AS UNSIGNED)
        END AS d,

        CASE
            WHEN date_format = 'DATE_ONLY' THEN 0
            WHEN date_format IN (
                'HYPHEN_DATETIME', 'SLASH_DATETIME'
            )
            THEN CAST(SUBSTRING(raw_value, 12, 2) AS UNSIGNED)
        END AS hh,

        CASE
            WHEN date_format = 'DATE_ONLY' THEN 0
            WHEN date_format IN (
                'HYPHEN_DATETIME', 'SLASH_DATETIME'
            )
            THEN CAST(SUBSTRING(raw_value, 15, 2) AS UNSIGNED)
        END AS mi,

        CASE
            WHEN date_format = 'DATE_ONLY' THEN 0
            WHEN date_format IN (
                'HYPHEN_DATETIME', 'SLASH_DATETIME'
            )
            THEN CAST(SUBSTRING(raw_value, 18, 2) AS UNSIGNED)
        END AS ss
    FROM formats
),
checked AS (
    SELECT
        *,
        CASE
            WHEN date_format = 'MISSING'
            THEN 'MISSING'

            WHEN date_format = 'OTHER_FORMAT'
            THEN 'FORMAT_REVIEW'

            WHEN y BETWEEN 1 AND 9999
             AND m BETWEEN 1 AND 12
             AND d BETWEEN 1 AND
                CASE
                    WHEN m = 2 THEN
                        CASE
                            WHEN MOD(y, 400) = 0
                              OR (
                                  MOD(y, 4) = 0
                                  AND MOD(y, 100) <> 0
                              )
                            THEN 29 ELSE 28
                        END
                    WHEN m IN (4, 6, 9, 11) THEN 30
                    ELSE 31
                END
             AND hh BETWEEN 0 AND 23
             AND mi BETWEEN 0 AND 59
             AND ss BETWEEN 0 AND 59
            THEN
                CASE
                    WHEN y < 1000
                    THEN 'MYSQL_YEAR_RANGE_REVIEW'
                    ELSE 'CALENDAR_TIME_VALID'
                END

            ELSE 'INVALID_DATE_OR_TIME'
        END AS validation_status
    FROM parts
)
SELECT
    source_name,
    column_name,
    date_format,
    validation_status,
    COUNT(*) AS row_count,
    SUM(
        CASE WHEN hh <> 0 OR mi <> 0 OR ss <> 0
             THEN 1 ELSE 0 END
    ) AS non_midnight_time_rows
FROM checked
GROUP BY
    source_name, column_name,
    date_format, validation_status
ORDER BY source_name, column_name, date_format;