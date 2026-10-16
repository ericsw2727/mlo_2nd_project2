-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 24-1: 마스터의 ID 보정 후 키 중복·내용 차이 검사
-- 입력: 23번 표준화 후보와 Bronze 마스터
-- 원본 ID 표기 차이와 나머지 컬럼의 내용 차이를 별도로 계산
-- 원본 수정·중복 제거·격리 없음
-- 나머지 컬럼은 아직 원문 비교이므로,
-- 내용 차이가 발견되면 표준화 규칙과 대조 후 충돌 여부 판단

CREATE OR REPLACE VIEW
    kream_project_repro.asis_master_normalized_key_check_v1 AS

SELECT
    'CATEGORY_MASTER' AS source_name,
    n.proposed_id AS normalized_id,
    COUNT(*) AS rows_per_key,

    COUNT(DISTINCT HEX(b.CAT_ID))
        AS raw_id_versions,

    COUNT(DISTINCT
        COALESCE(HEX(b.CAT_NM), 'NULL'),
        COALESCE(HEX(b.CAT_LEVEL), 'NULL'),
        COALESCE(HEX(b.REG_DT), 'NULL')
    ) AS raw_payload_versions,

    MIN(b.bronze_row_id) AS first_row_id

FROM kream_project_repro.bronze_category_parent_lookup AS b
JOIN kream_project_repro.asis_identifier_normalization_v1 AS n
  ON n.source_name = 'CATEGORY_MASTER'
 AND n.column_name = 'CAT_ID'
 AND n.bronze_row_id = b.bronze_row_id
WHERE n.proposed_id IS NOT NULL
GROUP BY n.proposed_id

UNION ALL

SELECT
    'INSPECTOR_MASTER',
    n.proposed_id,
    COUNT(*),

    COUNT(DISTINCT HEX(b.EMP_NO)),

    COUNT(DISTINCT
        COALESCE(HEX(b.EMP_NM), 'NULL'),
        COALESCE(HEX(b.DEPT_NM), 'NULL'),
        COALESCE(HEX(b.POSITION_NM), 'NULL'),
        COALESCE(HEX(b.HIRE_DT), 'NULL'),
        COALESCE(HEX(b.ACTIVE_YN), 'NULL')
    ),

    MIN(b.bronze_row_id)

FROM kream_project_repro.bronze_inspector_master AS b
JOIN kream_project_repro.asis_identifier_normalization_v1 AS n
  ON n.source_name = 'INSPECTOR_MASTER'
 AND n.column_name = 'EMP_NO'
 AND n.bronze_row_id = b.bronze_row_id
WHERE n.proposed_id IS NOT NULL
GROUP BY n.proposed_id;


-- 작업 24-2: 보정 후 마스터 키 현황
-- 유효 형식 후보에 포함된 행만 집계
-- 23번에서 두 마스터 모두 미해결·결측 후보가 없음을 확인함

SELECT
    source_name,

    SUM(rows_per_key) AS inspected_rows,

    COUNT(*) AS normalized_unique_ids,

    SUM(
        CASE WHEN rows_per_key > 1
             THEN 1 ELSE 0 END
    ) AS repeated_key_groups,

    SUM(rows_per_key - 1) AS additional_rows,

    SUM(
        CASE
            WHEN rows_per_key > 1
             AND raw_payload_versions = 1
            THEN 1 ELSE 0
        END
    ) AS same_payload_repeated_groups,

    SUM(
        CASE WHEN raw_payload_versions > 1
             THEN 1 ELSE 0 END
    ) AS different_payload_groups,

    SUM(
        CASE WHEN raw_id_versions > 1
             THEN 1 ELSE 0 END
    ) AS multiple_raw_id_spellings_groups

FROM kream_project_repro.asis_master_normalized_key_check_v1
GROUP BY source_name
ORDER BY source_name;


-- 작업 24-3: 보정 후 내용 차이·원본 ID 표기 차이 샘플
-- 결과가 없으면 해당 조건에 걸린 키가 없다는 뜻
-- 최대 20개 키 조회

SELECT
    source_name,
    normalized_id,
    rows_per_key,
    raw_id_versions,
    raw_payload_versions,
    first_row_id
FROM kream_project_repro.asis_master_normalized_key_check_v1
WHERE raw_payload_versions > 1
   OR raw_id_versions > 1
ORDER BY source_name, normalized_id
LIMIT 20;