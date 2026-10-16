-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
SELECT
    VERSION() AS mysql_version,
    DATABASE() AS current_database,
    @@character_set_server AS server_charset,
    @@collation_server AS server_collation,
    @@session.sql_mode AS session_sql_mode,
    @@session.time_zone AS session_time_zone,
    @@local_infile AS local_infile_enabled;