-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 54C-1: 새 버전 테이블 존재 여부 확인
-- 결과가 0일 때만 다음 작업 실행

SELECT COUNT(*) AS existing_tables
FROM information_schema.tables
WHERE table_schema = 'kream_project_repro'
  AND table_name IN (
      'asis_inspection_disposition_stage_v2',
      'asis_valid_revision_rank_snapshot_v2'
  );


-- 작업 54C-2: 기존 분류를 새 버전으로 복사
-- 기존 테이블과 결과는 보존

CREATE TABLE kream_project_repro.asis_inspection_disposition_stage_v2
LIKE kream_project_repro.asis_inspection_disposition_stage_v1;

INSERT INTO kream_project_repro.asis_inspection_disposition_stage_v2
SELECT *
FROM kream_project_repro.asis_inspection_disposition_stage_v1;

SHOW WARNINGS;


-- 작업 54C-3: 제품명 복구 근거를 기록할 컬럼 추가

ALTER TABLE kream_project_repro.asis_inspection_disposition_stage_v2
    ADD COLUMN product_name_rule_source VARCHAR(40) NOT NULL
        DEFAULT 'ORIGINAL_NAME_CHECK';


-- 작업 54C-4: 정상 행의 개정 순위 저장 테이블 생성

CREATE TABLE kream_project_repro.asis_valid_revision_rank_snapshot_v2 (
    bronze_row_id BIGINT UNSIGNED NOT NULL,
    valid_occurrence_no BIGINT UNSIGNED NOT NULL,
    latest_valid_rev_no INT NOT NULL,

    PRIMARY KEY (bronze_row_id)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin;


-- 작업 54C-5: 현재 연결의 안전 업데이트 설정 보존
-- 새 버전 테이블의 전체 재계산을 위해 잠시 해제
-- 작업 종료 후 원래 설정으로 복원

SET @kream_previous_safe_updates = @@SESSION.SQL_SAFE_UPDATES;
SET SESSION SQL_SAFE_UPDATES = 0;

START TRANSACTION;


-- 작업 54C-6: 공식 상품 코드로 미매핑 제품명 복구
-- 정상 상품 코드가 정확히 연결된 경우만 적용
-- 금지 코드와 다른 품질 오류는 변경하지 않음

UPDATE kream_project_repro.asis_inspection_disposition_stage_v2 AS s

JOIN kream_project_repro.bronze_inspection AS b
  ON b.bronze_row_id = s.bronze_row_id

JOIN kream_project_repro.silver_product_std_dict AS d
  ON d.CODE_TYPE = 'ITEM_MODEL'
 AND HEX(d.STD_CODE) = HEX(b.ITEM_STD_CODE)
 AND d.BANNED_WORD_YN = 'N'

SET
    s.standard_item_name = d.STD_KOR_NM,
    s.name_check_status = 'RECOVERED_BY_ITEM_CODE',
    s.product_name_error_flag = 0,
    s.product_name_rule_source = 'STANDARD_ITEM_CODE'

WHERE s.name_check_status = 'UNMAPPED_NAME_REVIEW';


-- 작업 54C-7: 변경된 제품명 검사 결과를 반영해 품질 오류 재계산
-- 제품명 외의 기존 오류는 모두 유지

UPDATE kream_project_repro.asis_inspection_disposition_stage_v2
SET record_error_flag =
    CASE
        WHEN inspection_key_error_flag = 1
          OR price_error_flag = 1
          OR duration_error_flag = 1
          OR datetime_missing_flag = 1
          OR done_before_inbound_flag = 1
          OR extracted_before_done_flag = 1
          OR employee_reference_error_flag = 1
          OR category_reference_error_flag = 1
          OR product_name_error_flag = 1
          OR revision_conflict_flag = 1
          OR result_error_flag = 1
          OR required_value_missing_flag = 1
        THEN 1 ELSE 0
    END;


-- 작업 54C-8: 정상 행끼리 중복 순서와 최신 유효 개정 재계산
-- 추출 시각은 개정 선택에 사용하지 않음

INSERT INTO kream_project_repro.asis_valid_revision_rank_snapshot_v2 (
    bronze_row_id,
    valid_occurrence_no,
    latest_valid_rev_no
)
SELECT
    bronze_row_id,

    ROW_NUMBER() OVER (
        PARTITION BY
            normalized_insp_id,
            normalized_rev_no
        ORDER BY bronze_row_id
    ) AS valid_occurrence_no,

    MAX(normalized_rev_no) OVER (
        PARTITION BY normalized_insp_id
    ) AS latest_valid_rev_no

FROM kream_project_repro.asis_inspection_disposition_stage_v2

WHERE integrated_missing_check_flag = 0
  AND record_error_flag = 0;


-- 작업 54C-9: 새 버전의 분류와 처리 근거 재계산

UPDATE kream_project_repro.asis_inspection_disposition_stage_v2 AS s

LEFT JOIN kream_project_repro.asis_valid_revision_rank_snapshot_v2 AS r
  ON r.bronze_row_id = s.bronze_row_id

SET
    s.valid_occurrence_no = r.valid_occurrence_no,
    s.latest_valid_rev_no = r.latest_valid_rev_no,

    s.disposition =
        CASE
            WHEN s.integrated_missing_check_flag = 1
                THEN 'CHECK_MISSING'
            WHEN s.record_error_flag = 1
                THEN 'QUARANTINE'
            WHEN r.valid_occurrence_no > 1
                THEN 'EXCLUDED'
            WHEN s.normalized_rev_no < r.latest_valid_rev_no
                THEN 'EXCLUDED'
            ELSE 'SILVER_CANDIDATE'
        END,

    s.primary_reason =
        CASE
            WHEN s.integrated_missing_check_flag = 1
                THEN 'CHECK_RESULT_MISSING'
            WHEN s.record_error_flag = 1
                THEN 'QUALITY_RULE_VIOLATION'
            WHEN r.valid_occurrence_no > 1
                THEN 'IDENTICAL_DUPLICATE'
            WHEN s.normalized_rev_no < r.latest_valid_rev_no
                THEN 'SUPERSEDED_VALID_REVISION'
            ELSE 'LATEST_VALID_REVISION'
        END,

    s.rule_version = '20261014_v2';

COMMIT;

SET SESSION SQL_SAFE_UPDATES = @kream_previous_safe_updates;


-- 작업 54C-10: 전체 건수와 복구 적용 확인

SELECT
    COUNT(*) AS classified_rows,
    COUNT(DISTINCT bronze_row_id) AS distinct_source_rows,
    SUM(integrated_missing_check_flag) AS missing_check_rows,

    SUM(
        CASE
            WHEN product_name_rule_source = 'STANDARD_ITEM_CODE'
            THEN 1 ELSE 0
        END
    ) AS code_recovered_name_rows,

    SUM(
        CASE
            WHEN product_name_rule_source = 'STANDARD_ITEM_CODE'
             AND disposition = 'QUARANTINE'
            THEN 1 ELSE 0
        END
    ) AS recovered_name_with_other_error_rows

FROM kream_project_repro.asis_inspection_disposition_stage_v2;


-- 작업 54C-11: 새 분류 건수 확인

SELECT
    disposition,
    primary_reason,
    COUNT(*) AS source_rows
FROM kream_project_repro.asis_inspection_disposition_stage_v2
GROUP BY
    disposition,
    primary_reason
ORDER BY
    disposition,
    primary_reason;


-- 작업 54C-12: 기존 분류에서 새 분류로 이동한 건수 확인

SELECT
    old_stage.disposition AS previous_disposition,
    new_stage.disposition AS revised_disposition,
    COUNT(*) AS source_rows

FROM kream_project_repro.asis_inspection_disposition_stage_v1 AS old_stage

JOIN kream_project_repro.asis_inspection_disposition_stage_v2 AS new_stage
  ON new_stage.bronze_row_id = old_stage.bronze_row_id

GROUP BY
    old_stage.disposition,
    new_stage.disposition

ORDER BY
    previous_disposition,
    revised_disposition;


-- 작업 54C-13: Silver 후보의 품질과 개정 선택 검증
-- 세 오류 값 모두 0이어야 함
-- 후보 행 수와 서로 다른 검수 ID 수가 같아야 함

SELECT
    COUNT(*) AS silver_candidate_rows,
    COUNT(DISTINCT normalized_insp_id) AS distinct_inspection_ids,

    SUM(
        CASE WHEN record_error_flag = 1
             THEN 1 ELSE 0 END
    ) AS candidate_with_rule_error_rows,

    SUM(
        CASE WHEN integrated_missing_check_flag = 1
             THEN 1 ELSE 0 END
    ) AS candidate_with_missing_check_rows,

    SUM(
        CASE
            WHEN valid_occurrence_no IS NULL
              OR latest_valid_rev_no IS NULL
              OR valid_occurrence_no <> 1
              OR normalized_rev_no <> latest_valid_rev_no
            THEN 1 ELSE 0
        END
    ) AS incorrect_revision_selection_rows

FROM kream_project_repro.asis_inspection_disposition_stage_v2
WHERE disposition = 'SILVER_CANDIDATE';



