-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 51-1: 저장 테이블 존재 여부 확인

SELECT COUNT(*) AS existing_tables
FROM information_schema.tables
WHERE table_schema = 'kream_project_repro'
  AND table_name = 'asis_product_name_snapshot_v1';


-- 작업 51-2: 기존 제품명 검사 결과 전체 저장
-- 기존 매핑 기준과 검사 결과를 그대로 유지

CREATE TABLE kream_project_repro.asis_product_name_snapshot_v1
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin
AS
SELECT *
FROM kream_project_repro.asis_product_name_mapping_check_v1;

SHOW WARNINGS;


-- 작업 51-3: 검사 상태 조회용 인덱스 설정

ALTER TABLE kream_project_repro.asis_product_name_snapshot_v1
    ADD INDEX ix_product_name_check_status (name_check_status);


-- 작업 51-4: 검사 상태별 그룹 수와 원천 행 수 확인

SELECT
    name_check_status,
    COUNT(*) AS saved_name_groups,
    SUM(source_rows) AS represented_source_rows
FROM kream_project_repro.asis_product_name_snapshot_v1
GROUP BY name_check_status
ORDER BY name_check_status;


-- 작업 51-5: 전체 검사 대상 건수 확인
-- represented_source_rows와 bronze_rows가 같아야 함

SELECT
    COUNT(*) AS saved_name_groups,
    SUM(source_rows) AS represented_source_rows,

    (
        SELECT COUNT(*)
        FROM kream_project_repro.bronze_inspection
    ) AS bronze_rows

FROM kream_project_repro.asis_product_name_snapshot_v1;


-- 작업 51-6: 최종 분류 연결에 사용할 컬럼과 자료형 확인

SELECT
    ordinal_position,
    column_name,
    column_type,
    collation_name
FROM information_schema.columns
WHERE table_schema = 'kream_project_repro'
  AND table_name = 'asis_product_name_snapshot_v1'
ORDER BY ordinal_position;