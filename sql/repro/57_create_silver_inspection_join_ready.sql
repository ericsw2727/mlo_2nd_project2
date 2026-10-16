-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 57-1: 저장 테이블 존재 여부 확인

SELECT COUNT(*) AS existing_tables
FROM information_schema.tables
WHERE table_schema = 'kream_project_repro'
  AND table_name = 'silver_inspection_join_ready';


-- 작업 57-2: 정상 검수의 마스터 연결 확인
-- 기준 행 수는 271787
-- 두 누락 값은 모두 0이어야 함

SELECT
    COUNT(*) AS inspection_rows,

    SUM(
        CASE WHEN i.EMP_NO IS NULL
             THEN 1 ELSE 0 END
    ) AS missing_inspector_master_rows,

    SUM(
        CASE WHEN c.CAT_ID IS NULL
             THEN 1 ELSE 0 END
    ) AS missing_category_master_rows

FROM kream_project_repro.silver_inspection AS f

LEFT JOIN kream_project_repro.silver_inspector_master AS i
  ON i.EMP_NO = f.INSPECTOR_EMP_NO

LEFT JOIN kream_project_repro.silver_category_parent_lookup AS c
  ON c.CAT_ID = f.PARENT_CAT_ID;


-- 작업 57-3: 정상 조인 통합 테이블 생성
-- 업무 컬럼 18개와 검수 원천 추적용 컬럼 3개
-- 배상금은 원화 소수 4자리 보존
-- 거래가의 3배를 저장할 수 있도록 금액보다 큰 범위 사용

CREATE TABLE kream_project_repro.silver_inspection_join_ready (
    INSP_ID VARCHAR(20) NOT NULL,
    REV_NO INT NOT NULL,
    ITEM_STD_CODE VARCHAR(50) NOT NULL,
    ITEM_NM VARCHAR(150) NOT NULL,
    PARENT_CAT_ID VARCHAR(20),
    PARENT_CAT_NM VARCHAR(100) NOT NULL,
    TRADE_PRICE_KRW DECIMAL(18,4) NOT NULL,
    INSP_DURATION_MIN DECIMAL(12,8) NOT NULL,
    INSP_RESULT VARCHAR(50) NOT NULL,
    COMPENSATION_LOSS_KRW DECIMAL(19,4) NOT NULL,
    INSPECTOR_EMP_NO VARCHAR(20) NOT NULL,
    INSPECTOR_EMP_NM VARCHAR(50) NOT NULL,
    INSPECTOR_DEPT_NM VARCHAR(100) NOT NULL,
    INSPECTOR_POSITION_NM VARCHAR(50) NOT NULL,
    INBOUND_DT DATETIME NOT NULL,
    INSP_DONE_DT DATETIME NOT NULL,
    EXTRACTED_AT DATETIME NOT NULL,
    INSP_MEMO TEXT,

    source_bronze_row_id BIGINT UNSIGNED NOT NULL,
    source_file VARCHAR(255) NOT NULL,
    rule_version VARCHAR(32) NOT NULL,

    PRIMARY KEY (INSP_ID, REV_NO),
    UNIQUE KEY uq_silver_join_inspection_id (INSP_ID),
    UNIQUE KEY uq_silver_join_source (source_bronze_row_id),

    INDEX ix_silver_join_employee (INSPECTOR_EMP_NO),
    INDEX ix_silver_join_department (INSPECTOR_DEPT_NM),

    CONSTRAINT fk_silver_join_inspection
        FOREIGN KEY (INSP_ID, REV_NO)
        REFERENCES kream_project_repro.silver_inspection (INSP_ID, REV_NO),

    CONSTRAINT ck_silver_join_compensation
        CHECK (
            COMPENSATION_LOSS_KRW =
                CASE
                    WHEN INSP_RESULT = 'CLAIM_FAKE_PASS'
                    THEN TRADE_PRICE_KRW * 3
                    ELSE 0
                END
        )
)
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin;


-- 작업 57-4: 정규 마스터 재조인 및 배상금 재계산
-- 검수원은 이름 대신 사번으로 연결
-- 추적용 출처는 검수 원천의 출처임

INSERT INTO kream_project_repro.silver_inspection_join_ready (
    INSP_ID,
    REV_NO,
    ITEM_STD_CODE,
    ITEM_NM,
    PARENT_CAT_ID,
    PARENT_CAT_NM,
    TRADE_PRICE_KRW,
    INSP_DURATION_MIN,
    INSP_RESULT,
    COMPENSATION_LOSS_KRW,
    INSPECTOR_EMP_NO,
    INSPECTOR_EMP_NM,
    INSPECTOR_DEPT_NM,
    INSPECTOR_POSITION_NM,
    INBOUND_DT,
    INSP_DONE_DT,
    EXTRACTED_AT,
    INSP_MEMO,
    source_bronze_row_id,
    source_file,
    rule_version
)
SELECT
    f.INSP_ID,
    f.REV_NO,
    f.ITEM_STD_CODE,
    f.ITEM_NM,
    f.PARENT_CAT_ID,
    c.CAT_NM,
    f.TRADE_PRICE_KRW,
    f.INSP_DURATION_MIN,
    f.INSP_RESULT,

    CASE
        WHEN f.INSP_RESULT = 'CLAIM_FAKE_PASS'
        THEN f.TRADE_PRICE_KRW * 3
        ELSE 0
    END,

    f.INSPECTOR_EMP_NO,
    i.EMP_NM,
    i.DEPT_NM,
    i.POSITION_NM,
    f.INBOUND_DT,
    f.INSP_DONE_DT,
    f.EXTRACTED_AT,
    f.INSP_MEMO,
    f.source_bronze_row_id,
    f.source_file,
    f.rule_version

FROM kream_project_repro.silver_inspection AS f

LEFT JOIN kream_project_repro.silver_inspector_master AS i
  ON i.EMP_NO = f.INSPECTOR_EMP_NO

LEFT JOIN kream_project_repro.silver_category_parent_lookup AS c
  ON c.CAT_ID = f.PARENT_CAT_ID;

SHOW WARNINGS;


-- 작업 57-5: 저장 건수와 검수 ID 수 확인

SELECT
    COUNT(*) AS joined_rows,
    COUNT(DISTINCT INSP_ID) AS distinct_inspection_ids,
    COUNT(DISTINCT source_bronze_row_id) AS distinct_source_rows
FROM kream_project_repro.silver_inspection_join_ready;


-- 작업 57-6: 정상 검수 대비 저장 누락과 추가 행 확인
-- 두 값 모두 0이어야 함

SELECT
    (
        SELECT COUNT(*)
        FROM kream_project_repro.silver_inspection AS f
        LEFT JOIN kream_project_repro.silver_inspection_join_ready AS j
          ON j.source_bronze_row_id = f.source_bronze_row_id
        WHERE j.source_bronze_row_id IS NULL
    ) AS missing_joined_rows,

    (
        SELECT COUNT(*)
        FROM kream_project_repro.silver_inspection_join_ready AS j
        LEFT JOIN kream_project_repro.silver_inspection AS f
          ON f.source_bronze_row_id = j.source_bronze_row_id
        WHERE f.source_bronze_row_id IS NULL
    ) AS unexpected_joined_rows;


-- 작업 57-7: 업무 컬럼과 추적 정보의 값 비교
-- 배상금은 공식으로 다시 비교
-- 결과는 0이어야 함

SELECT
    SUM(
        CASE
            WHEN f.source_bronze_row_id IS NULL
              OR i.EMP_NO IS NULL
              OR c.CAT_ID IS NULL
              OR NOT (
                    (j.INSP_ID <=> f.INSP_ID)
                AND (j.REV_NO <=> f.REV_NO)
                AND (HEX(j.ITEM_STD_CODE) <=> HEX(f.ITEM_STD_CODE))
                AND (HEX(j.ITEM_NM) <=> HEX(f.ITEM_NM))
                AND (j.PARENT_CAT_ID <=> f.PARENT_CAT_ID)
                AND (HEX(j.PARENT_CAT_NM) <=> HEX(c.CAT_NM))
                AND (j.TRADE_PRICE_KRW <=> f.TRADE_PRICE_KRW)
                AND (j.INSP_DURATION_MIN <=> f.INSP_DURATION_MIN)
                AND (j.INSP_RESULT <=> f.INSP_RESULT)
                AND (
                    j.COMPENSATION_LOSS_KRW <=>
                    CASE
                        WHEN f.INSP_RESULT = 'CLAIM_FAKE_PASS'
                        THEN f.TRADE_PRICE_KRW * 3
                        ELSE 0
                    END
                )
                AND (j.INSPECTOR_EMP_NO <=> f.INSPECTOR_EMP_NO)
                AND (HEX(j.INSPECTOR_EMP_NM) <=> HEX(i.EMP_NM))
                AND (HEX(j.INSPECTOR_DEPT_NM) <=> HEX(i.DEPT_NM))
                AND (HEX(j.INSPECTOR_POSITION_NM) <=> HEX(i.POSITION_NM))
                AND (j.INBOUND_DT <=> f.INBOUND_DT)
                AND (j.INSP_DONE_DT <=> f.INSP_DONE_DT)
                AND (j.EXTRACTED_AT <=> f.EXTRACTED_AT)
                AND (HEX(j.INSP_MEMO) <=> HEX(f.INSP_MEMO))
                AND (HEX(j.source_file) <=> HEX(f.source_file))
                AND (j.rule_version <=> f.rule_version)
              )
            THEN 1 ELSE 0
        END
    ) AS stored_value_difference_rows

FROM kream_project_repro.silver_inspection_join_ready AS j

LEFT JOIN kream_project_repro.silver_inspection AS f
  ON f.source_bronze_row_id = j.source_bronze_row_id

LEFT JOIN kream_project_repro.silver_inspector_master AS i
  ON i.EMP_NO = f.INSPECTOR_EMP_NO

LEFT JOIN kream_project_repro.silver_category_parent_lookup AS c
  ON c.CAT_ID = f.PARENT_CAT_ID;


-- 작업 57-8: 결과별 검수 건수와 배상금 합계 확인
-- 배상금은 가품 오판정 결과에만 발생해야 함

SELECT
    INSP_RESULT,
    COUNT(*) AS inspection_rows,
    SUM(COMPENSATION_LOSS_KRW) AS compensation_loss_krw
FROM kream_project_repro.silver_inspection_join_ready
GROUP BY INSP_RESULT
ORDER BY INSP_RESULT;