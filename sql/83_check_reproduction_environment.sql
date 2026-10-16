-- 작업 83: 별도 재현 환경의 준비 상태 확인
-- 83-1만 먼저 실행. 데이터와 테이블 변경 없음.

-- 작업 83-1: 재현 스키마의 현재 상태
SELECT
    (SELECT COUNT(*) FROM information_schema.SCHEMATA
     WHERE SCHEMA_NAME = 'kream_project_repro') AS existing_repro_schema,
    (SELECT COUNT(*) FROM information_schema.TABLES
     WHERE TABLE_SCHEMA = 'kream_project_repro') AS existing_repro_objects;

SELECT
    VERSION() AS mysql_version,
    @@GLOBAL.secure_file_priv AS file_directory,
    @@SESSION.sql_mode AS session_sql_mode;

-- 이후 단계는 검증용 스키마 준비에 대한 안내를 받은 뒤 실행
-- 기존 kream_project에는 어떤 생성·삭제·적재 작업도 하지 않음
