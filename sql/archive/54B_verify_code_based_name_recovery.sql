-- 작업 54B-1: 미매핑 제품명이 공식 상품 코드로 연결되는지 확인

SELECT
    CASE
        WHEN d.DICT_ID IS NULL
            THEN 'ITEM_CODE_NOT_FOUND'
        WHEN d.BANNED_WORD_YN = 'N'
            THEN 'VALID_ITEM_CODE_FOUND'
        ELSE 'BANNED_OR_INVALID_ITEM_CODE'
    END AS code_recovery_check,

    COUNT(*) AS source_rows

FROM kream_project.asis_inspection_disposition_stage_v1 AS s

JOIN kream_project.bronze_inspection AS b
  ON b.bronze_row_id = s.bronze_row_id

LEFT JOIN kream_project.silver_product_std_dict AS d
  ON d.CODE_TYPE = 'ITEM_MODEL'
 AND HEX(d.STD_CODE) = HEX(b.ITEM_STD_CODE)

WHERE s.name_check_status = 'UNMAPPED_NAME_REVIEW'

GROUP BY code_recovery_check
ORDER BY code_recovery_check;


-- 작업 54B-2: 공식 코드로 복구 가능한 제품명과 다른 오류 중첩 확인
-- 제품명 문제만 있는 행과 다른 오류도 있는 행을 분리
-- 금지 제품 코드의 행은 이 조회 대상이 아님

SELECT
    CASE
        WHEN
            s.integrated_missing_check_flag
          + s.inspection_key_error_flag
          + s.price_error_flag
          + s.duration_error_flag
          + s.datetime_missing_flag
          + s.done_before_inbound_flag
          + s.extracted_before_done_flag
          + s.employee_reference_error_flag
          + s.category_reference_error_flag
          + s.revision_conflict_flag
          + s.result_error_flag
          + s.required_value_missing_flag = 0
        THEN 'PRODUCT_NAME_ONLY'
        ELSE 'HAS_OTHER_RULE_ERROR'
    END AS recovery_impact_group,

    COUNT(*) AS source_rows

FROM kream_project.asis_inspection_disposition_stage_v1 AS s

JOIN kream_project.bronze_inspection AS b
  ON b.bronze_row_id = s.bronze_row_id

JOIN kream_project.silver_product_std_dict AS d
  ON d.CODE_TYPE = 'ITEM_MODEL'
 AND HEX(d.STD_CODE) = HEX(b.ITEM_STD_CODE)
 AND d.BANNED_WORD_YN = 'N'

WHERE s.name_check_status = 'UNMAPPED_NAME_REVIEW'

GROUP BY recovery_impact_group
ORDER BY recovery_impact_group;


-- 작업 54B-3: 시간 역전 이전 개정과 추출 시각 함정의 중첩 확인
-- 기존 키 인덱스를 사용하여 같은 검수 ID의 개정 2를 조회

SELECT
    COUNT(*) AS reversed_old_revision_rows,

    SUM(
        CASE
            WHEN newer.extracted_at_kst < older.extracted_at_kst
            THEN 1 ELSE 0
        END
    ) AS newer_extracted_earlier_rows,

    SUM(
        CASE
            WHEN older.disposition = 'QUARANTINE'
            THEN 1 ELSE 0
        END
    ) AS old_revision_quarantine_rows

FROM kream_project.asis_inspection_disposition_stage_v1 AS older

JOIN kream_project.asis_inspection_key_snapshot_v1 AS newer_key
  ON newer_key.normalized_insp_id = older.normalized_insp_id
 AND newer_key.normalized_rev_no = 2

JOIN kream_project.asis_inspection_disposition_stage_v1 AS newer
  ON newer.bronze_row_id = newer_key.bronze_row_id

WHERE older.normalized_rev_no = 1
  AND older.done_before_inbound_flag = 1;