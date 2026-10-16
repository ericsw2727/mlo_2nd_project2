-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 55-1: 저장 테이블 존재 여부 확인

SELECT COUNT(*) AS existing_tables
FROM information_schema.tables
WHERE table_schema = 'kream_project_repro'
  AND table_name = 'silver_inspection';


-- 작업 55-2: 저장 자료형의 길이, 범위, 정밀도 확인
-- 세 결과 모두 0이어야 함
-- 값의 잘림이나 반올림이 발생하는 경우 적재하지 않음

SELECT
    SUM(
        CASE
            WHEN s.normalized_insp_id IS NULL
              OR b.ITEM_STD_CODE IS NULL
              OR s.standard_item_name IS NULL
              OR s.insp_result_candidate IS NULL
              OR s.inspector_emp_no_candidate IS NULL
              OR CHAR_LENGTH(s.normalized_insp_id) > 20
              OR CHAR_LENGTH(b.ITEM_STD_CODE) > 50
              OR CHAR_LENGTH(s.standard_item_name) > 150
              OR CHAR_LENGTH(s.parent_cat_id_candidate) > 20
              OR CHAR_LENGTH(s.insp_result_candidate) > 50
              OR CHAR_LENGTH(s.inspector_emp_no_candidate) > 20
            THEN 1 ELSE 0
        END
    ) AS text_storage_error_rows,

    SUM(
        CASE
            WHEN s.price_krw_candidate IS NULL
              OR s.price_krw_candidate < 0
              OR s.price_krw_candidate > 99999999999999.9999
              OR s.price_krw_candidate
                    <> ROUND(s.price_krw_candidate, 4)
            THEN 1 ELSE 0
        END
    ) AS price_storage_error_rows,

    SUM(
        CASE
            WHEN s.duration_min_candidate IS NULL
              OR s.duration_min_candidate < 0
              OR s.duration_min_candidate > 9999.99999999
              OR s.duration_min_candidate
                    <> ROUND(s.duration_min_candidate, 8)
            THEN 1 ELSE 0
        END
    ) AS duration_storage_error_rows

FROM kream_project_repro.asis_inspection_disposition_stage_v2 AS s
JOIN kream_project_repro.bronze_inspection AS b
  ON b.bronze_row_id = s.bronze_row_id
WHERE s.disposition = 'SILVER_CANDIDATE';


-- 작업 55-3: 검수 원천 Silver 테이블 생성
-- 원천의 업무 컬럼 13개와 추적용 컬럼 3개
-- 금액 소수 4자리, 검수 시간 소수 8자리 보존
-- 현재 상태이므로 검수 ID마다 한 행만 허용

CREATE TABLE kream_project_repro.silver_inspection (
    INSP_ID VARCHAR(20) NOT NULL,
    REV_NO INT NOT NULL,
    ITEM_STD_CODE VARCHAR(50) NOT NULL,
    ITEM_NM VARCHAR(150) NOT NULL,
    PARENT_CAT_ID VARCHAR(20),
    TRADE_PRICE_KRW DECIMAL(18,4) NOT NULL,
    INSP_DURATION_MIN DECIMAL(12,8) NOT NULL,
    INSP_RESULT VARCHAR(50) NOT NULL,
    INSPECTOR_EMP_NO VARCHAR(20) NOT NULL,
    INBOUND_DT DATETIME NOT NULL,
    INSP_DONE_DT DATETIME NOT NULL,
    EXTRACTED_AT DATETIME NOT NULL,
    INSP_MEMO TEXT,

    source_bronze_row_id BIGINT UNSIGNED NOT NULL,
    source_file VARCHAR(255) NOT NULL,
    rule_version VARCHAR(32) NOT NULL,

    PRIMARY KEY (INSP_ID, REV_NO),

    UNIQUE KEY uq_silver_inspection_id (INSP_ID),
    UNIQUE KEY uq_silver_inspection_source (source_bronze_row_id),

    INDEX ix_silver_inspection_employee (INSPECTOR_EMP_NO),
    INDEX ix_silver_inspection_category (PARENT_CAT_ID),
    INDEX ix_silver_inspection_item (ITEM_STD_CODE),

    CONSTRAINT fk_silver_inspection_employee
        FOREIGN KEY (INSPECTOR_EMP_NO)
        REFERENCES kream_project_repro.silver_inspector_master (EMP_NO),

    CONSTRAINT fk_silver_inspection_category
        FOREIGN KEY (PARENT_CAT_ID)
        REFERENCES kream_project_repro.silver_category_parent_lookup (CAT_ID),

    CONSTRAINT ck_silver_inspection_revision
        CHECK (REV_NO >= 1),

    CONSTRAINT ck_silver_inspection_price
        CHECK (TRADE_PRICE_KRW >= 0),

    CONSTRAINT ck_silver_inspection_duration
        CHECK (INSP_DURATION_MIN >= 0),

    CONSTRAINT ck_silver_inspection_datetime
        CHECK (
            INBOUND_DT <= INSP_DONE_DT
            AND INSP_DONE_DT <= EXTRACTED_AT
        )
)
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin;


-- 작업 55-4: 새 버전의 정상 후보 적재
-- 표준 상품명과 정규화된 값을 사용
-- 원본 메모는 보존하고 그 안의 지시문은 처리에 사용하지 않음

INSERT INTO kream_project_repro.silver_inspection (
    INSP_ID,
    REV_NO,
    ITEM_STD_CODE,
    ITEM_NM,
    PARENT_CAT_ID,
    TRADE_PRICE_KRW,
    INSP_DURATION_MIN,
    INSP_RESULT,
    INSPECTOR_EMP_NO,
    INBOUND_DT,
    INSP_DONE_DT,
    EXTRACTED_AT,
    INSP_MEMO,
    source_bronze_row_id,
    source_file,
    rule_version
)
SELECT
    s.normalized_insp_id,
    s.normalized_rev_no,
    b.ITEM_STD_CODE,
    s.standard_item_name,
    s.parent_cat_id_candidate,
    s.price_krw_candidate,
    s.duration_min_candidate,
    s.insp_result_candidate,
    s.inspector_emp_no_candidate,
    s.inbound_dt_kst,
    s.insp_done_dt_kst,
    s.extracted_at_kst,
    b.INSP_MEMO,
    b.bronze_row_id,
    b.source_file,
    s.rule_version

FROM kream_project_repro.asis_inspection_disposition_stage_v2 AS s
JOIN kream_project_repro.bronze_inspection AS b
  ON b.bronze_row_id = s.bronze_row_id

WHERE s.disposition = 'SILVER_CANDIDATE';

SHOW WARNINGS;


-- 작업 55-5: 저장 건수와 고유 식별자 확인

SELECT
    COUNT(*) AS silver_rows,
    COUNT(DISTINCT INSP_ID) AS distinct_inspection_ids,
    COUNT(DISTINCT source_bronze_row_id) AS distinct_source_rows
FROM kream_project_repro.silver_inspection;


-- 작업 55-6: 정상 후보 중 저장 누락 확인
-- 결과는 0이어야 함

SELECT COUNT(*) AS missing_silver_rows

FROM kream_project_repro.asis_inspection_disposition_stage_v2 AS s

LEFT JOIN kream_project_repro.silver_inspection AS f
  ON f.source_bronze_row_id = s.bronze_row_id

WHERE s.disposition = 'SILVER_CANDIDATE'
  AND f.source_bronze_row_id IS NULL;


-- 작업 55-7: 저장 대상과 실제 값 비교
-- 업무 컬럼 13개와 추적 정보를 비교
-- 두 결과 모두 0이어야 함

SELECT
    SUM(
        CASE
            WHEN s.bronze_row_id IS NULL
              OR b.bronze_row_id IS NULL
              OR s.disposition <> 'SILVER_CANDIDATE'
            THEN 1 ELSE 0
        END
    ) AS unexpected_silver_rows,

    SUM(
        CASE
            WHEN s.bronze_row_id IS NOT NULL
             AND b.bronze_row_id IS NOT NULL
             AND NOT (
                    (f.INSP_ID <=> s.normalized_insp_id)
                AND (f.REV_NO <=> s.normalized_rev_no)
                AND (HEX(f.ITEM_STD_CODE) <=> HEX(b.ITEM_STD_CODE))
                AND (HEX(f.ITEM_NM) <=> HEX(s.standard_item_name))
                AND (f.PARENT_CAT_ID <=> s.parent_cat_id_candidate)
                AND (f.TRADE_PRICE_KRW <=> s.price_krw_candidate)
                AND (f.INSP_DURATION_MIN <=> s.duration_min_candidate)
                AND (f.INSP_RESULT <=> s.insp_result_candidate)
                AND (f.INSPECTOR_EMP_NO <=> s.inspector_emp_no_candidate)
                AND (f.INBOUND_DT <=> s.inbound_dt_kst)
                AND (f.INSP_DONE_DT <=> s.insp_done_dt_kst)
                AND (f.EXTRACTED_AT <=> s.extracted_at_kst)
                AND (HEX(f.INSP_MEMO) <=> HEX(b.INSP_MEMO))
                AND (HEX(f.source_file) <=> HEX(b.source_file))
                AND (f.rule_version <=> s.rule_version)
             )
            THEN 1 ELSE 0
        END
    ) AS stored_value_difference_rows

FROM kream_project_repro.silver_inspection AS f

LEFT JOIN kream_project_repro.asis_inspection_disposition_stage_v2 AS s
  ON s.bronze_row_id = f.source_bronze_row_id

LEFT JOIN kream_project_repro.bronze_inspection AS b
  ON b.bronze_row_id = f.source_bronze_row_id;


-- 작업 55-8: 저장된 상품 코드와 검수 결과의 공식 사전 연결 확인
-- 두 결과 모두 0이어야 함

SELECT
    SUM(
        CASE
            WHEN NOT EXISTS (
                SELECT 1
                FROM kream_project_repro.silver_product_std_dict AS d
                WHERE d.CODE_TYPE = 'ITEM_MODEL'
                  AND d.BANNED_WORD_YN = 'N'
                  AND HEX(d.STD_CODE) = HEX(f.ITEM_STD_CODE)
            )
            THEN 1 ELSE 0
        END
    ) AS invalid_item_code_rows,

    SUM(
        CASE
            WHEN NOT EXISTS (
                SELECT 1
                FROM kream_project_repro.silver_product_std_dict AS d
                WHERE d.CODE_TYPE = 'INSP_RESULT'
                  AND d.BANNED_WORD_YN = 'N'
                  AND HEX(d.STD_CODE) = HEX(f.INSP_RESULT)
            )
            THEN 1 ELSE 0
        END
    ) AS invalid_result_code_rows

FROM kream_project_repro.silver_inspection AS f;