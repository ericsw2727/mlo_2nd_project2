SELECT
    VERSION() AS mysql_version,
    DATABASE() AS current_database,
    @@character_set_server AS server_charset,
    @@collation_server AS server_collation,
    @@session.sql_mode AS session_sql_mode,
    @@session.time_zone AS session_time_zone,
    @@local_infile AS local_infile_enabled;