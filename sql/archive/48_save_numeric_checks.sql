-- 작업 48-1: 저장 테이블 존재 여부 확인
-- existing_tables가 0일 때만 다음 작업 실행

SELECT COUNT(*) AS existing_tables
FROM information_schema.tables
WHERE table_schema = 'kream_project'
  AND table_name = 'asis_inspection_numeric_snapshot_v1';


-- 작업 48-2: 금액과 검수 시간 검사 결과 저장
-- 기존 검사 결과의 값과 자료형을 그대로 저장

CREATE TABLE kream_project.asis_inspection_numeric_snapshot_v1
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin
AS
SELECT
    bronze_row_id,
    INSP_ID,
    REV_NO,
    price_raw,
    duration_raw,
    price_krw_candidate,
    duration_min_candidate,
    price_status,
    duration_status
FROM kream_project.asis_inspection_numeric_check_v1;

SHOW WARNINGS;


-- 작업 48-3: 원천 행 기준 기본키 설정
-- 중복된 원천 행이 있으면 기본키 생성 단계에서 확인됨

ALTER TABLE kream_project.asis_inspection_numeric_snapshot_v1
    ADD PRIMARY KEY (bronze_row_id);


-- 작업 48-4: 원천 대비 누락과 불필요한 행 확인
-- 두 차이 값 모두 0이어야 함

SELECT
    (
        SELECT COUNT(*)
        FROM kream_project.bronze_inspection
    ) AS bronze_rows,

    (
        SELECT COUNT(*)
        FROM kream_project.asis_inspection_numeric_snapshot_v1
    ) AS saved_rows,

    (
        SELECT COUNT(*)
        FROM kream_project.bronze_inspection AS b
        LEFT JOIN
            kream_project.asis_inspection_numeric_snapshot_v1 AS n
          ON n.bronze_row_id = b.bronze_row_id
        WHERE n.bronze_row_id IS NULL
    ) AS missing_saved_rows,

    (
        SELECT COUNT(*)
        FROM kream_project.asis_inspection_numeric_snapshot_v1 AS n
        LEFT JOIN kream_project.bronze_inspection AS b
          ON b.bronze_row_id = n.bronze_row_id
        WHERE b.bronze_row_id IS NULL
    ) AS unknown_source_rows;


-- 작업 48-5: 검사 상태별 저장 결과 확인
-- 이전 38번 검사 결과와 비교

SELECT
    price_status,
    duration_status,
    COUNT(*) AS row_count
FROM kream_project.asis_inspection_numeric_snapshot_v1
GROUP BY
    price_status,
    duration_status
ORDER BY
    price_status,
    duration_status;


-- 작업 48-6: 정상 변환된 수치 확인
-- 금액의 소수 부분은 반올림하거나 버리지 않음

SELECT
    COUNT(*) AS converted_price_rows,
    MIN(price_krw_candidate) AS min_price_krw,
    MAX(price_krw_candidate) AS max_price_krw,
    SUM(
        CASE
            WHEN price_krw_candidate <> FLOOR(price_krw_candidate)
            THEN 1 ELSE 0
        END
    ) AS fractional_price_rows
FROM kream_project.asis_inspection_numeric_snapshot_v1
WHERE price_status = 'CONVERTED';

SELECT
    COUNT(*) AS converted_duration_rows,
    MIN(duration_min_candidate) AS min_duration_min,
    MAX(duration_min_candidate) AS max_duration_min,
    SUM(
        CASE
            WHEN duration_min_candidate <> FLOOR(duration_min_candidate)
            THEN 1 ELSE 0
        END
    ) AS fractional_duration_rows
FROM kream_project.asis_inspection_numeric_snapshot_v1
WHERE duration_status = 'CONVERTED';