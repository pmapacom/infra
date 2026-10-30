-- PMapa — login-роль + ОТДЕЛЬНАЯ база для одного сервиса на внешнем сервере.
--
--   psql -d postgres -v ON_ERROR_STOP=1 \
--        -v role=pmapa_travel -v db=pmapa_travel -v pw='change-me' -f database.sql
--
-- Имя базы и имя роли совпадают: pmapa_<svc> (pmapa_travel, pmapa_auth, …).
-- Идемпотентно. ПАРОЛЬ ставится ТОЛЬКО при создании роли: при повторном запуске
-- существующая роль не трогается, так что выставленный вручную пароль
-- (ALTER ROLE … PASSWORD …) не перезаписывается.
--
-- CREATE DATABASE нельзя выполнять внутри транзакции, поэтому файл подаётся без
-- -1/--single-transaction (psql в autocommit).
--
-- \gexec вместо DO $$…$$: psql НЕ подставляет переменные внутри dollar-quoted
-- строк, поэтому имена и пароль собираются через format() в обычном SELECT.
\set ON_ERROR_STOP on

SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'role', :'pw')
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'role');
\gexec

SELECT format('CREATE DATABASE %I OWNER %I', :'db', :'role')
 WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'db');
\gexec

-- Изоляция как при локальных контейнерах: в базу сервиса не может войти ни один
-- другой сервис, даже зная имя базы.
SELECT format('REVOKE CONNECT ON DATABASE %I FROM PUBLIC', :'db');
\gexec

SELECT format('GRANT CONNECT, TEMPORARY ON DATABASE %I TO %I', :'db', :'role');
\gexec

SELECT d.datname AS database,
       pg_get_userbyid(d.datdba) AS owner,
       pg_encoding_to_char(d.encoding) AS encoding
  FROM pg_database AS d
 WHERE d.datname = :'db';
