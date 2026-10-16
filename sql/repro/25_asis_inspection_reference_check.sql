-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 25-1: 보정 후보 기준 마스터 참조 검사
-- 대상: 검수 담당 사번, 부모 카테고리
-- 마스터의 키별 집계 결과에 조인해 행 증식 방지
-- 원본 수정·격리·결측 복구 없음
-- 마스터 키 존재 여부만 검사하며,
-- 부서·재직·날짜 등 마스터의 전체 품질 통과를 뜻하지 않음

CREATE OR REPLACE VIEW
    kream_project_repro.asis_inspection_reference_check_v1 AS
SELECT
    n.bronze_row_id,
    n.column_name,
    n.raw_value,
    n.proposed_id,
    n.normalization_status,
    m.normalized_id AS matched_master_id,

    CASE
        WHEN n.normalization_status = 'MISSING_CANDIDATE'
        THEN 'MISSING_REFERENCE'

        WHEN n.proposed_id IS NULL
        THEN 'UNRESOLVED_REFERENCE'

        WHEN m.normalized_id IS NULL
        THEN 'MASTER_KEY_NOT_FOUND'

        WHEN m.raw_payload_versions > 1
        THEN 'MASTER_PAYLOAD_REVIEW'

        ELSE 'MASTER_KEY_FOUND'
    END AS reference_status

FROM kream_project_repro.asis_identifier_normalization_v1 AS n

LEFT JOIN kream_project_repro.asis_master_normalized_key_check_v1 AS m
  ON m.source_name =
        CASE n.column_name
            WHEN 'INSPECTOR_EMP_NO' THEN 'INSPECTOR_MASTER'
            WHEN 'PARENT_CAT_ID' THEN 'CATEGORY_MASTER'
        END
 AND HEX(m.normalized_id) = HEX(n.proposed_id)

WHERE n.source_name = 'INSPECTION'
  AND n.column_name IN (
      'INSPECTOR_EMP_NO',
      'PARENT_CAT_ID'
  );


-- 작업 25-2: 참조 검사 결과 집계
-- 각 컬럼의 row_count 합계는 335,000이어야 함

SELECT
    column_name,
    reference_status,
    COUNT(*) AS row_count
FROM kream_project_repro.asis_inspection_reference_check_v1
GROUP BY column_name, reference_status
ORDER BY column_name, reference_status;


-- 작업 25-3: 참조 문제 유형별 샘플
-- 컬럼·문제 유형별 최대 3행
-- 원본 검수 ID와 개정 번호를 함께 표시

WITH samples AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY column_name, reference_status
            ORDER BY bronze_row_id
        ) AS sample_no
    FROM kream_project_repro.asis_inspection_reference_check_v1
    WHERE reference_status <> 'MASTER_KEY_FOUND'
)
SELECT
    s.bronze_row_id,
    b.INSP_ID,
    b.REV_NO,
    s.column_name,
    s.raw_value,
    s.proposed_id,
    s.reference_status
FROM samples AS s
JOIN kream_project_repro.bronze_inspection AS b
  ON b.bronze_row_id = s.bronze_row_id
WHERE s.sample_no <= 3
ORDER BY s.column_name, s.reference_status, s.sample_no;