-- PMapa — база pmapa_<svc>_test для интеграционных тестов сервиса.
-- Роль pmapa_user уже создана database.sql; здесь только отдельная база под
-- тесты, чтобы TRUNCATE в тестах не трогал рабочие данные.
--
--   psql -d postgres -v ON_ERROR_STOP=1 \
--        -v role=pmapa_user -v db=pmapa_travel_test -f test_database.sql
\set ON_ERROR_STOP on

SELECT format('CREATE DATABASE %I OWNER %I', :'db', :'role')
 WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'db');
\gexec

SELECT format('REVOKE CONNECT ON DATABASE %I FROM PUBLIC', :'db');
\gexec

SELECT format('GRANT CONNECT, TEMPORARY ON DATABASE %I TO %I', :'db', :'role');
\gexec

SELECT d.datname AS test_database, pg_get_userbyid(d.datdba) AS owner
  FROM pg_database AS d
 WHERE d.datname = :'db';
