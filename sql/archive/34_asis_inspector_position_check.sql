-- 작업 34-1: 검수원 직급의 전체 원문 분포
-- 목적: 실제 직급 종류와 표기 차이 확인
-- HEX로 공백·대소문자 차이 구분
-- 원본 수정·직급 보정·격리 없음

SELECT
    POSITION_NM AS raw_position,
    HEX(POSITION_NM) AS raw_position_hex,
    CHAR_LENGTH(POSITION_NM) AS character_count,
    COUNT(*) AS source_rows
FROM kream_project.bronze_inspector_master
GROUP BY
    POSITION_NM,
    HEX(POSITION_NM),
    CHAR_LENGTH(POSITION_NM)
ORDER BY source_rows DESC, raw_position_hex;