-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 63-1: 변경 이력 테이블 존재 여부 확인

SELECT COUNT(*) AS existing_tables
FROM information_schema.tables
WHERE table_schema = 'kream_project_repro'
  AND table_name = 'silver_inspection_correction_log';


-- 작업 63-2: 변경 이력 테이블 생성
-- 두 원본 파일의 행 번호를 구분하여 기록
-- 한 원천 행의 한 컬럼은 한 번만 기록

CREATE TABLE kream_project_repro.silver_inspection_correction_log (
    source_name VARCHAR(32) NOT NULL,
    source_bronze_row_id BIGINT UNSIGNED NOT NULL,
    inspection_bronze_row_id BIGINT UNSIGNED NOT NULL,
    column_name VARCHAR(32) NOT NULL,
    original_value TEXT,
    corrected_value TEXT,
    rule_id VARCHAR(64) NOT NULL,
    rule_version VARCHAR(32) NOT NULL,

    PRIMARY KEY (
        source_name,
        source_bronze_row_id,
        column_name
    ),

    INDEX ix_correction_inspection (
        inspection_bronze_row_id
    )
)
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin;


-- 작업 63-3: 검수 원천의 업무 컬럼 13개 변경 이력 저장
-- 원본값과 표준 저장 표현이 다른 컬럼만 기록
-- 메모는 그대로 보존되므로 변경이 없으면 기록하지 않음
-- 규칙 이름은 우리 작업의 규칙이며 상대팀 규칙 번호와 구분

INSERT INTO kream_project_repro.silver_inspection_correction_log (
    source_name,
    source_bronze_row_id,
    inspection_bronze_row_id,
    column_name,
    original_value,
    corrected_value,
    rule_id,
    rule_version
)
SELECT
    'INSPECTION',
    b.bronze_row_id,
    b.bronze_row_id,
    d.column_name,
    d.original_value,
    d.corrected_value,
    d.rule_id,
    f.rule_version

FROM kream_project_repro.silver_inspection AS f

JOIN kream_project_repro.bronze_inspection AS b
  ON b.bronze_row_id = f.source_bronze_row_id

JOIN JSON_TABLE(
    JSON_ARRAY(
        JSON_OBJECT(
            'column', 'INSP_ID',
            'original', b.INSP_ID,
            'corrected', f.INSP_ID,
            'rule', 'OUR_ID_NORMALIZATION'
        ),
        JSON_OBJECT(
            'column', 'REV_NO',
            'original', b.REV_NO,
            'corrected', CAST(f.REV_NO AS CHAR),
            'rule', 'OUR_REVISION_TYPE_STANDARDIZATION'
        ),
        JSON_OBJECT(
            'column', 'ITEM_STD_CODE',
            'original', b.ITEM_STD_CODE,
            'corrected', f.ITEM_STD_CODE,
            'rule', 'OUR_PRODUCT_CODE_STANDARDIZATION'
        ),
        JSON_OBJECT(
            'column', 'ITEM_NM',
            'original', b.ITEM_NM,
            'corrected', f.ITEM_NM,
            'rule', 'OUR_PRODUCT_DICTIONARY_STANDARDIZATION'
        ),
        JSON_OBJECT(
            'column', 'PARENT_CAT_ID',
            'original', b.PARENT_CAT_ID,
            'corrected', f.PARENT_CAT_ID,
            'rule', 'OUR_CATEGORY_REFERENCE_STANDARDIZATION'
        ),
        JSON_OBJECT(
            'column', 'TRADE_PRICE_KRW',
            'original', b.TRADE_PRICE_KRW,
            'corrected', CAST(f.TRADE_PRICE_KRW AS CHAR),
            'rule', 'OUR_KRW_STANDARDIZATION'
        ),
        JSON_OBJECT(
            'column', 'INSP_DURATION_MIN',
            'original', b.INSP_DURATION_MIN,
            'corrected', CAST(f.INSP_DURATION_MIN AS CHAR),
            'rule', 'OUR_DURATION_MINUTE_STANDARDIZATION'
        ),
        JSON_OBJECT(
            'column', 'INSP_RESULT',
            'original', b.INSP_RESULT,
            'corrected', f.INSP_RESULT,
            'rule', 'OUR_RESULT_CODE_STANDARDIZATION'
        ),
        JSON_OBJECT(
            'column', 'INSPECTOR_EMP_NO',
            'original', b.INSPECTOR_EMP_NO,
            'corrected', f.INSPECTOR_EMP_NO,
            'rule', 'OUR_EMPLOYEE_ID_NORMALIZATION'
        ),
        JSON_OBJECT(
            'column', 'INBOUND_DT',
            'original', b.INBOUND_DT,
            'corrected', CAST(f.INBOUND_DT AS CHAR),
            'rule', 'OUR_KST_DATETIME_STANDARDIZATION'
        ),
        JSON_OBJECT(
            'column', 'INSP_DONE_DT',
            'original', b.INSP_DONE_DT,
            'corrected', CAST(f.INSP_DONE_DT AS CHAR),
            'rule', 'OUR_KST_DATETIME_STANDARDIZATION'
        ),
        JSON_OBJECT(
            'column', 'EXTRACTED_AT',
            'original', b.EXTRACTED_AT,
            'corrected', CAST(f.EXTRACTED_AT AS CHAR),
            'rule', 'OUR_KST_DATETIME_STANDARDIZATION'
        ),
        JSON_OBJECT(
            'column', 'INSP_MEMO',
            'original', b.INSP_MEMO,
            'corrected', f.INSP_MEMO,
            'rule', 'OUR_MEMO_PRESERVATION'
        )
    ),
    '$[*]' COLUMNS (
        column_name VARCHAR(32) PATH '$.column',
        original_value TEXT PATH '$.original',
        corrected_value TEXT PATH '$.corrected',
        rule_id VARCHAR(64) PATH '$.rule'
    )
) AS d ON TRUE

WHERE NOT (
    HEX(d.original_value) <=> HEX(d.corrected_value)
);

SHOW WARNINGS;


-- 작업 63-4: 조인 통합본의 추가 컬럼 5개 변경 이력 저장
-- 연결 검증이 끝난 원본 행을 사용
-- 배상금의 산술 수정과 숫자 표시 형식 변경을 구분

INSERT INTO kream_project_repro.silver_inspection_correction_log (
    source_name,
    source_bronze_row_id,
    inspection_bronze_row_id,
    column_name,
    original_value,
    corrected_value,
    rule_id,
    rule_version
)
SELECT
    'JOIN_READY',
    e.join_ready_bronze_row_id,
    j.source_bronze_row_id,
    d.column_name,
    d.original_value,
    d.corrected_value,
    d.rule_id,
    j.rule_version

FROM kream_project_repro.silver_inspection_join_ready AS j

JOIN kream_project_repro.asis_join_extra_column_check_v1 AS e
  ON e.inspection_bronze_row_id = j.source_bronze_row_id

JOIN kream_project_repro.asis_join_compensation_check_v1 AS c
  ON c.inspection_bronze_row_id = j.source_bronze_row_id

JOIN JSON_TABLE(
    JSON_ARRAY(
        JSON_OBJECT(
            'column', 'PARENT_CAT_NM',
            'original', e.raw_category_name,
            'corrected', j.PARENT_CAT_NM,
            'rule', 'OUR_CATEGORY_MASTER_REJOIN'
        ),
        JSON_OBJECT(
            'column', 'INSPECTOR_EMP_NM',
            'original', e.raw_employee_name,
            'corrected', j.INSPECTOR_EMP_NM,
            'rule', 'OUR_EMPLOYEE_MASTER_REJOIN'
        ),
        JSON_OBJECT(
            'column', 'INSPECTOR_DEPT_NM',
            'original', e.raw_department_name,
            'corrected', j.INSPECTOR_DEPT_NM,
            'rule', 'OUR_EMPLOYEE_MASTER_REJOIN'
        ),
        JSON_OBJECT(
            'column', 'INSPECTOR_POSITION_NM',
            'original', e.raw_position_name,
            'corrected', j.INSPECTOR_POSITION_NM,
            'rule', 'OUR_EMPLOYEE_MASTER_REJOIN'
        ),
        JSON_OBJECT(
            'column', 'COMPENSATION_LOSS_KRW',
            'original', e.raw_compensation_loss,
            'corrected', CAST(j.COMPENSATION_LOSS_KRW AS CHAR),
            'rule',
                CASE
                    WHEN c.compensation_check_status = 'AMOUNT_DIFFERENT'
                    THEN 'OUR_COMPENSATION_RECALCULATION'
                    ELSE 'OUR_NUMERIC_FORMAT_STANDARDIZATION'
                END
        )
    ),
    '$[*]' COLUMNS (
        column_name VARCHAR(32) PATH '$.column',
        original_value TEXT PATH '$.original',
        corrected_value TEXT PATH '$.corrected',
        rule_id VARCHAR(64) PATH '$.rule'
    )
) AS d ON TRUE

WHERE NOT (
    HEX(d.original_value) <=> HEX(d.corrected_value)
);

SHOW WARNINGS;


-- 작업 63-5: 출처와 컬럼별 변경 이력 집계

SELECT
    source_name,
    column_name,
    rule_id,
    COUNT(*) AS correction_entries
FROM kream_project_repro.silver_inspection_correction_log
GROUP BY
    source_name,
    column_name,
    rule_id
ORDER BY
    source_name,
    column_name,
    rule_id;


-- 작업 63-6: 변경 이력의 실제 차이와 출처 연결 검증
-- 세 오류 값 모두 0이어야 함

SELECT
    COUNT(*) AS correction_entries,

    SUM(
        CASE
            WHEN HEX(l.original_value) <=> HEX(l.corrected_value)
            THEN 1 ELSE 0
        END
    ) AS unchanged_value_entries,

    SUM(
        CASE WHEN f.source_bronze_row_id IS NULL
             THEN 1 ELSE 0 END
    ) AS missing_silver_rows,

    SUM(
        CASE
            WHEN l.source_name = 'INSPECTION'
             AND l.source_bronze_row_id =
                 l.inspection_bronze_row_id
                THEN 0

            WHEN l.source_name = 'JOIN_READY'
             AND p.join_ready_bronze_row_id =
                 l.source_bronze_row_id
                THEN 0

            ELSE 1
        END
    ) AS incorrect_source_link_entries

FROM kream_project_repro.silver_inspection_correction_log AS l

LEFT JOIN kream_project_repro.silver_inspection AS f
  ON f.source_bronze_row_id = l.inspection_bronze_row_id

LEFT JOIN kream_project_repro.asis_inspection_join_row_pair_v1 AS p
  ON p.inspection_bronze_row_id = l.inspection_bronze_row_id;