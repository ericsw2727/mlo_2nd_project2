-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 49 복원본: 날짜 검사 스냅샷 저장
-- 파일: 49_save_datetime_checks_restored.sql
-- 복원 근거: 82번 SHOW CREATE VIEW와 SHOW CREATE TABLE 결과
-- 생성 정의는 실제 스냅샷 구조와 일치하도록 작성
-- 날짜 변환은 13번 검사 뷰의 기존 규칙을 그대로 사용
-- 원본 제공 파일의 49번은 조회만 있고 저장 구간이 없어 별도 복원
-- 이 파일은 재현용 원문 보완 자료이며 현재 DB에 다시 실행하지 않음
-- 재현 환경의 스키마와 13번 뷰를 준비한 뒤 복제본에서 사용

-- 작업 49-1: 테이블 존재 여부 확인
SELECT COUNT(*) AS existing_tables
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'kream_project_repro'
  AND TABLE_NAME = 'asis_inspection_datetime_snapshot_v1';

-- 작업 49-2: 실제 생성 정의에 맞춘 날짜 스냅샷 테이블 생성
CREATE TABLE kream_project_repro.asis_inspection_datetime_snapshot_v1 (
    bronze_row_id BIGINT UNSIGNED NOT NULL DEFAULT '0',
    inbound_dt_kst DATETIME DEFAULT NULL,
    insp_done_dt_kst DATETIME DEFAULT NULL,
    extracted_at_kst DATETIME DEFAULT NULL,
    PRIMARY KEY (bronze_row_id)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin;

-- 작업 49-3: 기존 검사 뷰에서 변환 결과 저장
-- 새로운 시간대 해석이나 오류 분류를 추가하지 않음
INSERT INTO kream_project_repro.asis_inspection_datetime_snapshot_v1 (
    bronze_row_id,
    inbound_dt_kst,
    insp_done_dt_kst,
    extracted_at_kst
)
SELECT
    bronze_row_id,
    inbound_dt_kst,
    insp_done_dt_kst,
    extracted_at_kst
FROM kream_project_repro.asis_inspection_datetime_check_v1;

SHOW WARNINGS;

-- 작업 49-4: 저장 건수와 날짜 오류 분포 확인
-- 이번 원본의 기준값: 335000행, 각 날짜 결측 0
-- 완료가 입고보다 빠름 3165행, 추출이 완료보다 빠름 2891행
SELECT
    COUNT(*) AS saved_rows,
    SUM(inbound_dt_kst IS NULL) AS missing_inbound_rows,
    SUM(insp_done_dt_kst IS NULL) AS missing_done_rows,
    SUM(extracted_at_kst IS NULL) AS missing_extracted_rows,
    SUM(insp_done_dt_kst < inbound_dt_kst) AS done_before_inbound_rows,
    SUM(extracted_at_kst < insp_done_dt_kst) AS extracted_before_done_rows
FROM kream_project_repro.asis_inspection_datetime_snapshot_v1;

-- 작업 49-5: 원본 행 대비 누락과 추가 확인
-- 두 값 모두 0이어야 함
SELECT
    (
        SELECT COUNT(*)
        FROM kream_project_repro.bronze_inspection AS b
        LEFT JOIN kream_project_repro.asis_inspection_datetime_snapshot_v1 AS s
          ON s.bronze_row_id = b.bronze_row_id
        WHERE s.bronze_row_id IS NULL
    ) AS missing_snapshot_rows,
    (
        SELECT COUNT(*)
        FROM kream_project_repro.asis_inspection_datetime_snapshot_v1 AS s
        LEFT JOIN kream_project_repro.bronze_inspection AS b
          ON b.bronze_row_id = s.bronze_row_id
        WHERE b.bronze_row_id IS NULL
    ) AS unexpected_snapshot_rows;
