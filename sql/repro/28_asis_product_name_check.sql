-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 28-1: 상품명 복구에 사용할 표준명·동의어 확인
-- 원본 수정 없음

SELECT
    DICT_ID,
    STD_CODE,
    STD_KOR_NM,
    SYNONYM_LIST
FROM kream_project_repro.bronze_product_std_dict
WHERE CODE_TYPE = 'ITEM_MODEL'
ORDER BY STD_CODE;


-- 작업 28-2: 표준 상품명과 원문이 다른 상품명 샘플
-- 정상 상품 코드에 연결되는 데이터만 대상으로 함
-- 원본 문자 기준으로 비교
-- 동의어 매핑이나 격리는 아직 수행하지 않음
-- 상품명 유형별 집계 중 수신 행 수가 많은 30개 표시

SELECT
    b.ITEM_STD_CODE,
    d.STD_KOR_NM AS standard_item_name,
    b.ITEM_NM AS raw_item_name,
    HEX(b.ITEM_NM) AS raw_name_hex,
    COUNT(*) AS source_rows
FROM kream_project_repro.bronze_inspection AS b
JOIN kream_project_repro.bronze_product_std_dict AS d
  ON d.CODE_TYPE = 'ITEM_MODEL'
 AND d.STD_CODE = b.ITEM_STD_CODE
WHERE NOT (
    HEX(b.ITEM_NM) <=> HEX(d.STD_KOR_NM)
)
GROUP BY
    b.ITEM_STD_CODE,
    HEX(b.ITEM_STD_CODE),
    d.STD_KOR_NM,
    HEX(d.STD_KOR_NM),
    b.ITEM_NM,
    HEX(b.ITEM_NM)
ORDER BY source_rows DESC, raw_name_hex, b.ITEM_STD_CODE
LIMIT 30;