-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 원문 보완용 복원본. 현재 kream_project_repro에서 다시 실행하지 않음.
-- 기존 업무 규칙과 분류는 변경하지 않음.
-- 별도 재현 스키마용 복제본은 repro_sql 폴더에 제공.
-- 작업 77 복원: 문서용 테이블·컬럼·제약조건 목록
-- 실제 생성 정의와 기존 업로드 목록 28개를 근거로 복원

CREATE TABLE kream_project_repro.documentation_table_catalog_v1 (
    table_name VARCHAR(64) NOT NULL,
    table_role VARCHAR(32) NOT NULL,
    table_purpose VARCHAR(500) NOT NULL,
    catalog_version VARCHAR(32) NOT NULL,
    captured_at_kst DATETIME NOT NULL,
    PRIMARY KEY (table_name)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin;

INSERT INTO kream_project_repro.documentation_table_catalog_v1 (
    table_name, table_role, table_purpose, catalog_version, captured_at_kst
)
SELECT p.table_name, p.table_role, p.table_purpose,
       '20261015_catalog_v1', DATE_ADD(UTC_TIMESTAMP(), INTERVAL 9 HOUR)
FROM (
SELECT 'asis_inspection_join_row_pair_v1' AS table_name, 'TRACEABILITY' AS table_role, '검수 원본과 조인 원본 사이의 동일 공유 내용에 따른 행 대응' AS table_purpose
UNION ALL
SELECT 'asis_join_ready_disposition_snapshot_v1' AS table_name, 'TRACEABILITY' AS table_role, '조인 원본 각 행의 정상 격리 제외 분류와 검수 원본 대응' AS table_purpose
UNION ALL
SELECT 'data_quality_check_results_v1' AS table_name, 'QUALITY' AS table_role, '품질 검사 결과와 미검증 항목 및 기준 건수 차이 기록' AS table_purpose
UNION ALL
SELECT 'excluded_category_parent_lookup' AS table_name, 'EXCLUDED' AS table_role, '중복 등의 사유로 정상 마스터 적재에서 제외한 카테고리 기록' AS table_purpose
UNION ALL
SELECT 'excluded_inspection' AS table_name, 'EXCLUDED' AS table_role, '동일 내용 중복과 정상 이전 개정으로 최종 상태에서 제외한 검수 기록' AS table_purpose
UNION ALL
SELECT 'excluded_inspector_master' AS table_name, 'EXCLUDED' AS table_role, '중복 등의 사유로 정상 마스터 적재에서 제외한 검수원 기록' AS table_purpose
UNION ALL
SELECT 'gold_department_risk_summary_v1' AS table_name, 'GOLD_ANALYSIS' AS table_role, '현재 마스터 부서별 최종 유효 검수의 가품 오판정과 배상금' AS table_purpose
UNION ALL
SELECT 'gold_inspection_result_daily_v1' AS table_name, 'GOLD_ANALYSIS' AS table_role, '최종 유효 검수의 날짜별 판정과 거래가 및 배상금 집계' AS table_purpose
UNION ALL
SELECT 'gold_inspection_workload_daily_v1' AS table_name, 'GOLD_ANALYSIS' AS table_role, '정상 이전 개정을 포함한 날짜별 최초 검수 및 재검수 작업량' AS table_purpose
UNION ALL
SELECT 'gold_inspection_workload_hourly_v1' AS table_name, 'GOLD_ANALYSIS' AS table_role, '완료 날짜와 시간대 및 현재 마스터 부서 기준 검수 작업량' AS table_purpose
UNION ALL
SELECT 'gold_prediction_actual_daily_v1' AS table_name, 'EVALUATION' AS table_role, '예측 입력과 분리해 저장한 평가 기간의 날짜별 실제 검수 작업량' AS table_purpose
UNION ALL
SELECT 'gold_prediction_input_daily_v1' AS table_name, 'PREDICTION_INPUT' AS table_role, '예측 입력 상세의 날짜별 검수 건수와 소요시간 집계' AS table_purpose
UNION ALL
SELECT 'gold_prediction_input_record_v1' AS table_name, 'PREDICTION_INPUT' AS table_role, '예측 기준일 이전 추출 조건을 충족한 최근 28일의 정상 최초 검수 상세' AS table_purpose
UNION ALL
SELECT 'gold_product_risk_summary_v1' AS table_name, 'GOLD_ANALYSIS' AS table_role, '상품별 최종 유효 검수의 가품 오판정과 배상금 및 관측 상태' AS table_purpose
UNION ALL
SELECT 'gold_risk_cross_summary_v1' AS table_name, 'GOLD_ANALYSIS' AS table_role, '상품 부서 최종 개정 유형 및 분석 기간별 위험 교차 집계' AS table_purpose
UNION ALL
SELECT 'gold_staffing_scenario_v1' AS table_name, 'STAFFING_SCENARIO' AS table_role, '한 명의 검수 가능 시간을 가정한 최초 검수 필요 인원 시나리오' AS table_purpose
UNION ALL
SELECT 'gold_workload_forecast_evaluation_v1' AS table_name, 'EVALUATION' AS table_role, '예측 방법과 날짜별 예측값 및 실제값과 오차' AS table_purpose
UNION ALL
SELECT 'gold_workload_forecast_summary_v1' AS table_name, 'EVALUATION' AS table_role, '예측 방법별 주간 합계와 건수 및 소요시간의 MAE와 WAPE' AS table_purpose
UNION ALL
SELECT 'gold_workload_forecast_v1' AS table_name, 'PREDICTION' AS table_role, '최근 28일 평균과 같은 요일 평균으로 생성한 7일 예측값' AS table_purpose
UNION ALL
SELECT 'quarantine_category_parent_lookup' AS table_name, 'QUARANTINE' AS table_role, '정상 기준을 충족하지 못해 격리한 카테고리 원본 기록' AS table_purpose
UNION ALL
SELECT 'quarantine_inspection' AS table_name, 'QUARANTINE' AS table_role, '품질 오류와 동일 개정 충돌 등으로 격리한 검수 기록 및 원본 값' AS table_purpose
UNION ALL
SELECT 'quarantine_inspector_master' AS table_name, 'QUARANTINE' AS table_role, '정상 기준을 충족하지 못해 격리한 검수원 원본 기록' AS table_purpose
UNION ALL
SELECT 'silver_category_parent_lookup' AS table_name, 'SILVER_MASTER' AS table_role, '정제된 카테고리 코드와 이름 및 분류 단계' AS table_purpose
UNION ALL
SELECT 'silver_inspection' AS table_name, 'SILVER_FACT' AS table_role, '검수 ID별 최종 유효 개정과 정제된 검수 정보' AS table_purpose
UNION ALL
SELECT 'silver_inspection_correction_log' AS table_name, 'TRACEABILITY' AS table_role, '정상 검수와 조인 결과의 컬럼별 원본 값 및 수정 값과 적용 규칙' AS table_purpose
UNION ALL
SELECT 'silver_inspection_join_ready' AS table_name, 'SILVER_FACT' AS table_role, '최종 유효 검수에 정규 마스터 정보를 연결하고 배상금을 재계산한 결과' AS table_purpose
UNION ALL
SELECT 'silver_inspector_master' AS table_name, 'SILVER_MASTER' AS table_role, '정제된 검수원 정보와 현재 마스터 기준 부서 및 재직 상태' AS table_purpose
UNION ALL
SELECT 'silver_product_std_dict' AS table_name, 'SILVER_MASTER' AS table_role, '상품과 검수 결과 등의 표준 코드 및 금지 값 기준' AS table_purpose
) AS p;

-- information_schema에서 가져온 컬럼 문자셋은 기존 CTAS 방식대로 유지
CREATE TABLE kream_project_repro.documentation_column_catalog_v1
ENGINE = InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_bin
AS
SELECT
    c.TABLE_NAME AS table_name,
    c.ORDINAL_POSITION AS column_position,
    c.COLUMN_NAME AS column_name,
    c.COLUMN_TYPE AS column_type,
    c.IS_NULLABLE AS is_nullable,
    c.COLUMN_DEFAULT AS column_default,
    c.COLUMN_KEY AS column_key,
    c.COLLATION_NAME AS collation_name,
    c.EXTRA AS extra,
    p.catalog_version,
    p.captured_at_kst
FROM information_schema.COLUMNS AS c
JOIN kream_project_repro.documentation_table_catalog_v1 AS p
  ON p.table_name = c.TABLE_NAME
WHERE c.TABLE_SCHEMA = 'kream_project_repro';

ALTER TABLE kream_project_repro.documentation_column_catalog_v1
ADD PRIMARY KEY (table_name, column_position);

CREATE TABLE kream_project_repro.documentation_constraint_catalog_v1
ENGINE = InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_bin
AS
SELECT
    t.TABLE_NAME AS table_name,
    t.CONSTRAINT_NAME AS constraint_name,
    t.CONSTRAINT_TYPE AS constraint_type,
    COALESCE(k.ORDINAL_POSITION, 0) AS column_position,
    k.COLUMN_NAME AS column_name,
    k.REFERENCED_TABLE_SCHEMA AS referenced_schema,
    k.REFERENCED_TABLE_NAME AS referenced_table,
    k.REFERENCED_COLUMN_NAME AS referenced_column,
    r.UPDATE_RULE AS update_rule,
    r.DELETE_RULE AS delete_rule,
    c.CHECK_CLAUSE AS check_clause,
    t.ENFORCED AS enforced,
    p.catalog_version,
    p.captured_at_kst
FROM information_schema.TABLE_CONSTRAINTS AS t
JOIN kream_project_repro.documentation_table_catalog_v1 AS p
  ON p.table_name = t.TABLE_NAME
LEFT JOIN information_schema.KEY_COLUMN_USAGE AS k
  ON k.CONSTRAINT_SCHEMA = t.CONSTRAINT_SCHEMA
 AND k.TABLE_NAME = t.TABLE_NAME
 AND k.CONSTRAINT_NAME = t.CONSTRAINT_NAME
LEFT JOIN information_schema.REFERENTIAL_CONSTRAINTS AS r
  ON r.CONSTRAINT_SCHEMA = t.CONSTRAINT_SCHEMA
 AND r.TABLE_NAME = t.TABLE_NAME
 AND r.CONSTRAINT_NAME = t.CONSTRAINT_NAME
LEFT JOIN information_schema.CHECK_CONSTRAINTS AS c
  ON c.CONSTRAINT_SCHEMA = t.CONSTRAINT_SCHEMA
 AND c.CONSTRAINT_NAME = t.CONSTRAINT_NAME
WHERE t.TABLE_SCHEMA = 'kream_project_repro';

ALTER TABLE kream_project_repro.documentation_constraint_catalog_v1
ADD PRIMARY KEY (table_name, constraint_name, column_position);

SELECT 'TABLE_CATALOG' AS catalog_name, COUNT(*) AS stored_rows,
       COUNT(DISTINCT table_name) AS covered_tables
FROM kream_project_repro.documentation_table_catalog_v1
UNION ALL
SELECT 'COLUMN_CATALOG', COUNT(*), COUNT(DISTINCT table_name)
FROM kream_project_repro.documentation_column_catalog_v1
UNION ALL
SELECT 'CONSTRAINT_CATALOG', COUNT(*), COUNT(DISTINCT table_name)
FROM kream_project_repro.documentation_constraint_catalog_v1;

SELECT constraint_type,
       COUNT(*) AS constraint_column_rows,
       COUNT(DISTINCT table_name, constraint_name) AS constraint_count
FROM kream_project_repro.documentation_constraint_catalog_v1
GROUP BY constraint_type;
