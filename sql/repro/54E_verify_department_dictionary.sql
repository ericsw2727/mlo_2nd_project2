-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 54E-1: 공식 부서와 금지 부서의 원본 사전 규정 확인

SELECT
    DICT_ID,
    CODE_TYPE,
    STD_CODE,
    STD_KOR_NM,
    SYNONYM_LIST,
    BANNED_WORD_YN
FROM kream_project_repro.silver_product_std_dict
WHERE CODE_TYPE IN (
    'DEPT_STD',
    'BANNED_DEPT'
)
ORDER BY
    CODE_TYPE,
    STD_CODE;