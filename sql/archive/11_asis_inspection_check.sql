-- 작업 11-1: 검수 원본의 집계 기준 구분
-- 물리 행: 재전송·변경 이력·충돌을 포함한 수신 행
-- 검수 ID: 검수 대상 식별자
-- 개정 복합키: INSP_ID + REV_NO
-- COUNT(DISTINCT ...)는 NULL 키를 제외하므로 누락 검사는 별도 수행

SELECT
    COUNT(*) AS physical_rows,
    COUNT(DISTINCT INSP_ID) AS distinct_inspection_ids,
    COUNT(DISTINCT INSP_ID, REV_NO) AS distinct_revision_keys
FROM kream_project.bronze_inspection;


-- 작업 11-2: 같은 검수 ID·개정 번호의 반복 집계
-- 목적: 재전송 또는 동일 개정 충돌 가능성이 있는 키 파악
-- 키가 같다는 이유만으로 같은 내용이라고 판정하지 않음

SELECT
    COUNT(*) AS repeated_revision_key_groups,
    COALESCE(SUM(rows_per_key - 1), 0)
        AS additional_rows_for_same_key
FROM (
    SELECT
        INSP_ID,
        REV_NO,
        COUNT(*) AS rows_per_key
    FROM kream_project.bronze_inspection
    GROUP BY INSP_ID, REV_NO
    HAVING COUNT(*) > 1
) AS repeated_keys;


-- 작업 11-3: 검수 판정의 원문 분포 확인
-- 목적: 사전의 허용 판정과 비교할 기초 현황
-- 중복·이력이 포함된 물리 행 기준이며 Gold 판정 비율이 아님

SELECT
    INSP_RESULT,
    COUNT(*) AS physical_rows
FROM kream_project.bronze_inspection
GROUP BY INSP_RESULT
ORDER BY physical_rows DESC;


-- 작업 11-4: 거래금액의 원문 형식 분류
-- 목적: 단위 변환 후보, 환율 확인 대상, 결측·음수 구분
-- 형식만 분류하며 실제 금액 변환은 하지 않음

SELECT
    CASE
        WHEN COALESCE(LOWER(TRIM(TRADE_PRICE_KRW)), '') IN (
            '', 'null', 'none', 'na', 'n/a', 'nan', '-'
        )
            THEN 'MISSING_TOKEN'
        WHEN REGEXP_LIKE(
            TRADE_PRICE_KRW, '^-[0-9]+([.][0-9]+)?$'
        )
            THEN 'NEGATIVE_VALUE'
        WHEN REGEXP_LIKE(
            TRADE_PRICE_KRW, '^[$][0-9]+([.][0-9]+)?$'
        )
            THEN 'USD_NEEDS_FX'
        WHEN REGEXP_LIKE(
            TRADE_PRICE_KRW, '^[0-9]+([.][0-9]+)?만원$'
        )
            THEN 'TEN_THOUSAND_KRW'
        WHEN REGEXP_LIKE(
            TRADE_PRICE_KRW,
            '^([0-9]+|[0-9]{1,3}(,[0-9]{3})+)원$'
        )
            THEN 'KRW_WITH_UNIT'
        WHEN REGEXP_LIKE(
            TRADE_PRICE_KRW, '^[0-9]+([.][0-9]+)?$'
        )
            THEN 'KRW_NUMBER'
        ELSE 'OTHER_FORMAT'
    END AS price_format,
    COUNT(*) AS row_count
FROM kream_project.bronze_inspection
GROUP BY price_format
ORDER BY row_count DESC, price_format;


-- 작업 11-5: 검수 소요시간의 원문 형식 분류
-- 목적: 분·초 단위와 -999 대체값을 구분
-- -999를 정상 소요시간이나 0으로 처리하지 않음

SELECT
    CASE
        WHEN COALESCE(LOWER(TRIM(INSP_DURATION_MIN)), '') IN (
            '', 'null', 'none', 'na', 'n/a', 'nan', '-'
        )
            THEN 'MISSING_TOKEN'
        WHEN TRIM(INSP_DURATION_MIN) = '-999'
            THEN 'SENTINEL_MINUS_999'
        WHEN REGEXP_LIKE(
            INSP_DURATION_MIN, '^[0-9]+분[(]min[)]$', 'c'
        )
            THEN 'MINUTE_WITH_UNIT'
        WHEN REGEXP_LIKE(
            INSP_DURATION_MIN, '^[0-9]+초[(]sec[)]$', 'c'
        )
          OR REGEXP_LIKE(
            INSP_DURATION_MIN, '^[0-9]+s$', 'c'
        )
            THEN 'SECOND_WITH_UNIT'
        WHEN REGEXP_LIKE(
            INSP_DURATION_MIN, '^[0-9]+([.][0-9]+)?$'
        )
            THEN 'MINUTE_NUMBER'
        ELSE 'OTHER_FORMAT'
    END AS duration_format,
    COUNT(*) AS row_count
FROM kream_project.bronze_inspection
GROUP BY duration_format
ORDER BY row_count DESC, duration_format;


-- 작업 11-6: 담당 사번의 결측 표기 구분
-- 목적: SQL NULL, 빈 값, 문자열 결측 표기를 따로 기록
-- PRESENT는 값이 있다는 뜻이며 참조 무결성 통과를 의미하지 않음

SELECT
    CASE
        WHEN INSPECTOR_EMP_NO IS NULL
            THEN 'SQL_NULL'
        WHEN TRIM(INSPECTOR_EMP_NO) = ''
            THEN 'EMPTY_OR_SPACE'
        WHEN LOWER(TRIM(INSPECTOR_EMP_NO)) IN (
            'null', 'none', 'na', 'n/a', 'nan', '-'
        )
            THEN CONCAT(
                'TOKEN:',
                LOWER(TRIM(INSPECTOR_EMP_NO))
            )
        ELSE 'PRESENT'
    END AS employee_value_status,
    COUNT(*) AS row_count
FROM kream_project.bronze_inspection
GROUP BY employee_value_status
ORDER BY row_count DESC, employee_value_status;


-- 작업 11-7: CSV의 문자열 NULL이 SQL NULL로 해석된 영향 확인
-- 근거: 첨부 원본 두 파일의 INSPECTOR_EMP_NO에
-- 문자열 'NULL'이 각각 400행 존재
-- 데이터 수정 없이 현재 저장 상태만 조회

SELECT
    'bronze_inspection' AS table_name,
    COUNT(*) AS total_rows,
    SUM(
        CASE WHEN INSPECTOR_EMP_NO IS NULL
             THEN 1 ELSE 0 END
    ) AS sql_null_rows,
    SUM(
        CASE WHEN INSPECTOR_EMP_NO = 'NULL'
             THEN 1 ELSE 0 END
    ) AS literal_null_text_rows
FROM kream_project.bronze_inspection

UNION ALL

SELECT
    'bronze_inspection_join_ready',
    COUNT(*),
    SUM(
        CASE WHEN INSPECTOR_EMP_NO IS NULL
             THEN 1 ELSE 0 END
    ),
    SUM(
        CASE WHEN INSPECTOR_EMP_NO = 'NULL'
             THEN 1 ELSE 0 END
    )
FROM kream_project.bronze_inspection_join_ready;
