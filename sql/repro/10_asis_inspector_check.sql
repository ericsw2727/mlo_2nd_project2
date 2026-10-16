-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 10-1: 검수원 마스터 현황과 필수값 누락 검사
-- 근거: 명세서의 원본 6개 컬럼은 필수
-- 누락 행 수는 한 행에 여러 누락이 있어도 한 번만 계산

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT EMP_NO) AS distinct_employee_ids,
    SUM(
        CASE
            WHEN NULLIF(TRIM(EMP_NO), '') IS NULL
              OR NULLIF(TRIM(EMP_NM), '') IS NULL
              OR NULLIF(TRIM(DEPT_NM), '') IS NULL
              OR NULLIF(TRIM(POSITION_NM), '') IS NULL
              OR NULLIF(TRIM(HIRE_DT), '') IS NULL
              OR NULLIF(TRIM(ACTIVE_YN), '') IS NULL
            THEN 1 ELSE 0
        END
    ) AS missing_required_rows
FROM kream_project_repro.bronze_inspector_master;


-- 작업 10-2: 원문 기준 반복 사번 집계
-- 같은 사번의 추가 행을 세며, 동일 내용인지 여부는 아직 판정하지 않음

SELECT
    COUNT(*) AS duplicate_employee_groups,
    COALESCE(SUM(rows_per_employee - 1), 0)
        AS additional_rows_for_same_employee
FROM (
    SELECT
        EMP_NO,
        COUNT(*) AS rows_per_employee
    FROM kream_project_repro.bronze_inspector_master
    GROUP BY EMP_NO
    HAVING COUNT(*) > 1
) AS repeated_employees;


-- 작업 10-3: 재직 코드 원문 분포 확인
-- 목적: Y/N, 의미가 명확한 별칭, 판단 불가 값을 구분
-- HEX로 공백·대소문자 등 실제 표기 차이 확인

SELECT
    ACTIVE_YN,
    HEX(ACTIVE_YN) AS raw_active_hex,
    COUNT(*) AS row_count
FROM kream_project_repro.bronze_inspector_master
GROUP BY ACTIVE_YN, HEX(ACTIVE_YN)
ORDER BY row_count DESC, raw_active_hex;


-- 작업 10-4: 재직 코드 표준화 처리안의 건수 확인
-- 목적: 의미가 명확한 별칭을 Y/N으로 매핑했을 때 결과 확인
-- 원본 수정 없이 조회에서만 계산
-- 해석할 수 없는 값은 NULL로 남기고 UNRESOLVED로 표시

WITH active_mapping AS (
    SELECT
        bronze_row_id,
        CASE
            WHEN LOWER(TRIM(ACTIVE_YN)) IN (
                'y', 'yes', 'true', '1', '재직'
            ) THEN 'Y'

            WHEN LOWER(TRIM(ACTIVE_YN)) IN (
                'n', 'no', 'false', '0', '퇴사', '계약만료'
            ) THEN 'N'

            ELSE NULL
        END AS proposed_active_yn
    FROM kream_project_repro.bronze_inspector_master
)
SELECT
    COALESCE(proposed_active_yn, 'UNRESOLVED') AS proposed_active_yn,
    COUNT(*) AS row_count
FROM active_mapping
GROUP BY proposed_active_yn
ORDER BY proposed_active_yn;


-- 작업 10-5: 재직 여부를 판단할 수 없는 '-' 원본 확인
-- 목적: 사번과 원본값을 확인하고 후속 처리 근거로 기록
-- '-'를 Y 또는 N으로 추측해서 채우지 않음

SELECT
    bronze_row_id,
    EMP_NO,
    EMP_NM,
    DEPT_NM,
    ACTIVE_YN,
    HEX(ACTIVE_YN) AS raw_active_hex
FROM kream_project_repro.bronze_inspector_master
WHERE TRIM(ACTIVE_YN) = '-'
ORDER BY bronze_row_id;


-- 작업 10-6: 반복 사번의 원본 내용 비교
-- 목적: 완전히 동일한 재전송 후보와 같은 사번의 값 충돌 구분
-- 관리 컬럼을 제외한 원본 6개 컬럼을 비교
-- HEX로 공백·대소문자 등 실제 문자 차이까지 구분

WITH duplicate_groups AS (
    SELECT
        EMP_NO,
        COUNT(*) AS rows_per_employee,
        COUNT(DISTINCT
            COALESCE(HEX(EMP_NO), 'NULL'),
            COALESCE(HEX(EMP_NM), 'NULL'),
            COALESCE(HEX(DEPT_NM), 'NULL'),
            COALESCE(HEX(POSITION_NM), 'NULL'),
            COALESCE(HEX(HIRE_DT), 'NULL'),
            COALESCE(HEX(ACTIVE_YN), 'NULL')
        ) AS raw_content_versions
    FROM kream_project_repro.bronze_inspector_master
    GROUP BY EMP_NO
    HAVING COUNT(*) > 1
)
SELECT
    COUNT(*) AS duplicate_employee_groups,
    COALESCE(SUM(raw_content_versions = 1), 0)
        AS identical_content_groups,
    COALESCE(SUM(raw_content_versions > 1), 0)
        AS conflicting_content_groups,
    COALESCE(SUM(rows_per_employee - 1), 0)
        AS additional_rows_for_same_employee
FROM duplicate_groups;


-- 작업 10-7: 사번 원문 형식 검사
-- 기준: 이번 데이터의 정규 사번 형식인 KRM + 숫자 6자리
-- 표기 차이 검사이며, 존재하지 않는 직원이라고 판정하지 않음

SELECT
    COUNT(*) AS total_rows,
    SUM(
        CASE
            WHEN REGEXP_LIKE(EMP_NO, '^KRM[0-9]{6}$', 'c')
            THEN 1 ELSE 0
        END
    ) AS standard_employee_format_rows,
    SUM(
        CASE
            WHEN EMP_NO IS NULL
              OR NOT REGEXP_LIKE(EMP_NO, '^KRM[0-9]{6}$', 'c')
            THEN 1 ELSE 0
        END
    ) AS nonstandard_employee_format_rows
FROM kream_project_repro.bronze_inspector_master;


-- 작업 10-8: 비표준 사번 샘플 확인
-- 목적: 접두어·구분자·전각·보이지 않는 문자 등의 차이 파악

SELECT
    bronze_row_id,
    EMP_NO,
    HEX(EMP_NO) AS raw_employee_hex,
    CHAR_LENGTH(EMP_NO) AS character_count,
    LENGTH(EMP_NO) AS byte_count,
    EMP_NM
FROM kream_project_repro.bronze_inspector_master
WHERE EMP_NO IS NULL
   OR NOT REGEXP_LIKE(EMP_NO, '^KRM[0-9]{6}$', 'c')
ORDER BY bronze_row_id
LIMIT 10;


-- 작업 10-9: 표준 부서와 금칙 부서의 사전 근거 확인
-- 목적: 부서명 보정·격리 판단에 사용할 표준명과 동의어 확인

SELECT
    DICT_ID,
    CODE_TYPE,
    STD_CODE,
    STD_KOR_NM,
    SYNONYM_LIST,
    BANNED_WORD_YN
FROM kream_project_repro.bronze_product_std_dict
WHERE CODE_TYPE IN ('DEPT_STD', 'BANNED_DEPT')
ORDER BY CODE_TYPE, STD_CODE;


-- 작업 10-10: 금칙 부서 사전과 일치하는 원본 부서 집계
-- 기준: 금칙 부서의 표준명 또는 쉼표로 구분된 동의어와 일치
-- 현재 사전의 동의어 구분자와 내용을 확인하고 사용하는 검사
-- EXISTS를 사용하여 사전 매칭으로 원본 행 수가 늘어나지 않게 함

SELECT
    m.DEPT_NM,
    COUNT(*) AS affected_rows
FROM kream_project_repro.bronze_inspector_master AS m
WHERE EXISTS (
    SELECT 1
    FROM kream_project_repro.bronze_product_std_dict AS d
    WHERE d.CODE_TYPE = 'BANNED_DEPT'
      AND d.BANNED_WORD_YN = 'Y'
      AND (
          LOWER(TRIM(m.DEPT_NM)) = LOWER(TRIM(d.STD_KOR_NM))
          OR FIND_IN_SET(
              LOWER(TRIM(m.DEPT_NM)),
              LOWER(d.SYNONYM_LIST)
          ) > 0
      )
)
GROUP BY m.DEPT_NM
ORDER BY affected_rows DESC;


-- 작업 10-11: 입사일 원문 형식 분포 확인
-- 근거: 명세서의 HIRE_DT 자료형은 DATE
-- 형식만 분류하며 실제 날짜 유효성이나 시각 제거는 아직 수행하지 않음

SELECT
    CASE
        WHEN HIRE_DT IS NULL OR TRIM(HIRE_DT) = ''
            THEN 'MISSING'
        WHEN REGEXP_LIKE(
            HIRE_DT,
            '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
        )
            THEN 'DATE_ONLY'
        WHEN REGEXP_LIKE(
            HIRE_DT,
            '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$'
        )
            THEN 'DATETIME_WITH_TIME'
        ELSE 'OTHER_FORMAT'
    END AS hire_date_format,
    COUNT(*) AS row_count
FROM kream_project_repro.bronze_inspector_master
GROUP BY hire_date_format
ORDER BY row_count DESC;