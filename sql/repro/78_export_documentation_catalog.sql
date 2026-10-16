-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 원문 보완용 복원본. 현재 kream_project_repro에서 다시 실행하지 않음.
-- 기존 업무 규칙과 분류는 변경하지 않음.
-- 별도 재현 스키마용 복제본은 repro_sql 폴더에 제공.
-- 작업 78 복원: 구조 목록과 품질 결과 CSV 저장
-- 명시적 LIMIT로 조회 결과 제한 방지. 기존 파일이 있으면 오류 발생.

SELECT *
FROM kream_project_repro.documentation_table_catalog_v1
ORDER BY table_name
LIMIT 18446744073709551615
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_repro_documentation_table_catalog_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

SELECT *
FROM kream_project_repro.documentation_column_catalog_v1
ORDER BY table_name, column_position
LIMIT 18446744073709551615
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_repro_documentation_column_catalog_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

SELECT *
FROM kream_project_repro.documentation_constraint_catalog_v1
ORDER BY table_name, constraint_type, constraint_name, column_position
LIMIT 18446744073709551615
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_repro_documentation_constraint_catalog_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';

SELECT *
FROM kream_project_repro.data_quality_check_results_v1
ORDER BY target_table, check_id
LIMIT 18446744073709551615
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/kream_repro_data_quality_check_results_v1.csv'
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '\\'
LINES TERMINATED BY '\r\n';
