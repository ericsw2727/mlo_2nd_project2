-- 작업 54E-1: 공식 부서와 금지 부서의 원본 사전 규정 확인

SELECT
    DICT_ID,
    CODE_TYPE,
    STD_CODE,
    STD_KOR_NM,
    SYNONYM_LIST,
    BANNED_WORD_YN
FROM kream_project.silver_product_std_dict
WHERE CODE_TYPE IN (
    'DEPT_STD',
    'BANNED_DEPT'
)
ORDER BY
    CODE_TYPE,
    STD_CODE;