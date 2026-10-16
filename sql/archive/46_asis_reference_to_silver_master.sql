-- 작업 46-1: 검증된 부모 카테고리 복구 후보 저장
-- 복구 후보와 최종 Silver 참조 유효성은 별도로 검사

CREATE TABLE
    kream_project.asis_parent_category_recovery_snapshot_v1 AS
SELECT
    bronze_row_id AS source_bronze_row_id,
    proposed_category_id,
    '20261014_v1' AS rule_version
FROM kream_project.asis_parent_category_recovery_check_v1
WHERE recovery_status = 'RECOVERABLE_CANDIDATE';

SHOW WARNINGS;

ALTER TABLE
    kream_project.asis_parent_category_recovery_snapshot_v1
    ADD PRIMARY KEY (source_bronze_row_id);


-- 작업 46-2: 복구 후보 저장 확인
-- 예상: 1,000행

SELECT COUNT(*) AS recovery_candidate_rows
FROM kream_project.asis_parent_category_recovery_snapshot_v1;


-- 작업 46-3: 최종 Silver 마스터 기준 참조 검사
-- 격리 마스터는 ID를 한 번씩만 연결해 행 증식 방지
-- 재직 여부 N 자체는 사번 참조 오류로 처리하지 않음

CREATE OR REPLACE VIEW
    kream_project.asis_reference_to_silver_master_v1 AS

WITH candidates AS (
    SELECT
        n.bronze_row_id,
        n.column_name,
        n.raw_value,
        n.proposed_id,
        n.normalization_status,

        CASE
            WHEN n.column_name = 'PARENT_CAT_ID'
             AND n.normalization_status = 'MISSING_CANDIDATE'
             AND r.source_bronze_row_id IS NOT NULL
            THEN r.proposed_category_id
            ELSE n.proposed_id
        END AS effective_reference_id,

        CASE
            WHEN n.column_name = 'PARENT_CAT_ID'
             AND n.normalization_status = 'MISSING_CANDIDATE'
             AND r.source_bronze_row_id IS NOT NULL
            THEN 'RECOVERY_CANDIDATE'
            ELSE 'ORIGINAL_OR_NORMALIZED'
        END AS reference_origin

    FROM kream_project.asis_reference_id_snapshot_v1 AS n

    LEFT JOIN
        kream_project.asis_parent_category_recovery_snapshot_v1 AS r
      ON n.column_name = 'PARENT_CAT_ID'
     AND r.source_bronze_row_id = n.bronze_row_id

    WHERE n.source_name = 'INSPECTION'
      AND n.column_name IN (
          'INSPECTOR_EMP_NO',
          'PARENT_CAT_ID'
      )
),
quarantined_employees AS (
    SELECT DISTINCT normalized_emp_no
    FROM kream_project.quarantine_inspector_master
    WHERE normalized_emp_no IS NOT NULL
),
quarantined_categories AS (
    SELECT DISTINCT normalized_cat_id
    FROM kream_project.quarantine_category_parent_lookup
    WHERE normalized_cat_id IS NOT NULL
)
SELECT
    c.*,

    CASE
        WHEN c.effective_reference_id IS NULL
         AND c.normalization_status = 'MISSING_CANDIDATE'
        THEN 'MISSING_REFERENCE'

        WHEN c.effective_reference_id IS NULL
        THEN 'UNRESOLVED_REFERENCE'

        WHEN e.EMP_NO IS NOT NULL
          OR a.CAT_ID IS NOT NULL
        THEN 'SILVER_MASTER_FOUND'

        WHEN qe.normalized_emp_no IS NOT NULL
          OR qa.normalized_cat_id IS NOT NULL
        THEN 'MASTER_QUARANTINED'

        ELSE 'MASTER_KEY_NOT_FOUND'
    END AS final_reference_status

FROM candidates AS c

LEFT JOIN kream_project.silver_inspector_master AS e
  ON c.column_name = 'INSPECTOR_EMP_NO'
 AND e.EMP_NO = c.effective_reference_id

LEFT JOIN kream_project.silver_category_parent_lookup AS a
  ON c.column_name = 'PARENT_CAT_ID'
 AND a.CAT_ID = c.effective_reference_id

LEFT JOIN quarantined_employees AS qe
  ON c.column_name = 'INSPECTOR_EMP_NO'
 AND qe.normalized_emp_no = c.effective_reference_id

LEFT JOIN quarantined_categories AS qa
  ON c.column_name = 'PARENT_CAT_ID'
 AND qa.normalized_cat_id = c.effective_reference_id;


-- 작업 46-4: 최종 마스터 참조 상태 집계
-- 컬럼별 row_count 합계는 각각 335,000이어야 함

SELECT
    column_name,
    reference_origin,
    final_reference_status,
    COUNT(*) AS row_count
FROM kream_project.asis_reference_to_silver_master_v1
GROUP BY
    column_name,
    reference_origin,
    final_reference_status
ORDER BY
    column_name,
    reference_origin,
    final_reference_status;


-- 작업 46-5: 최종 참조 문제의 유형별 샘플

WITH samples AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY
                column_name,
                reference_origin,
                final_reference_status
            ORDER BY bronze_row_id
        ) AS sample_no
    FROM kream_project.asis_reference_to_silver_master_v1
    WHERE final_reference_status <> 'SILVER_MASTER_FOUND'
)
SELECT
    s.bronze_row_id,
    b.INSP_ID,
    b.REV_NO,
    s.column_name,
    s.raw_value,
    s.effective_reference_id,
    s.reference_origin,
    s.final_reference_status
FROM samples AS s
JOIN kream_project.bronze_inspection AS b
  ON b.bronze_row_id = s.bronze_row_id
WHERE s.sample_no <= 3
ORDER BY
    s.column_name,
    s.reference_origin,
    s.final_reference_status,
    s.sample_no;