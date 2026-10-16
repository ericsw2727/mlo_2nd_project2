-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 20-1: 확정한 재직 여부 규칙의 결과 집계
-- 정확한 원본 'Y'만 재직
-- 원본 'N'과 나머지 모든 값은 퇴사 처리
-- HEX 비교로 소문자·공백 차이를 구분
-- 조회에서만 계산하며 원본 수정 없음

WITH evaluated AS (
    SELECT
        bronze_row_id,
        EMP_NO,
        ACTIVE_YN,

        CASE
            WHEN HEX(ACTIVE_YN) = '59' THEN 'Y'
            ELSE 'N'
        END AS proposed_active_yn,

        CASE
            WHEN HEX(ACTIVE_YN) IN ('59', '4E')
            THEN 'STANDARD'
            ELSE 'NONSTANDARD'
        END AS raw_code_status

    FROM kream_project_repro.bronze_inspector_master
)
SELECT
    raw_code_status,
    proposed_active_yn,
    COUNT(*) AS row_count
FROM evaluated
GROUP BY raw_code_status, proposed_active_yn
ORDER BY raw_code_status, proposed_active_yn;


-- 작업 20-2: 비표준값의 처리 샘플
-- NULL도 비표준값으로 포함
-- 원본값·문자 정보·처리값을 함께 확인

SELECT
    bronze_row_id,
    EMP_NO,
    ACTIVE_YN AS raw_active_yn,
    HEX(ACTIVE_YN) AS raw_active_hex,
    'N' AS proposed_active_yn
FROM kream_project_repro.bronze_inspector_master
WHERE ACTIVE_YN IS NULL
   OR HEX(ACTIVE_YN) NOT IN ('59', '4E')
ORDER BY bronze_row_id
LIMIT 20;