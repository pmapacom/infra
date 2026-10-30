-- PMapa — ЕДИНАЯ login-роль pmapa_user + ОТДЕЛЬНАЯ база под один сервис
-- на внешнем сервере.
--
--   psql -d postgres -v ON_ERROR_STOP=1 \
--        -v role=pmapa_user -v db=pmapa_travel -v pw='change-me' -f database.sql
--
-- Роль одна на все сервисы — pmapa_user; база у каждого своя — pmapa_<svc>
-- (pmapa_auth, pmapa_travel, …), владелец каждой базы — pmapa_user.
--
-- Все сервисы живут на одной машине, доступ к базе закрыт фаерволом (allow-list
-- по IP на стороне Postgres), а утечка одного пароля всё равно означает утечку
-- всех — поэтому раздельные роли смысла не имеют: один пользователь, один
-- пароль. Разделение теперь ТОЛЬКО логическое (разные базы), без разграничения
-- доступа между сервисами на стороне СУБД: pmapa_user подключается ко всем базам.
--
-- Идемпотентно. ПАРОЛЬ ставится ТОЛЬКО при создании роли: при повторном запуске
-- существующая роль не трогается, выставленный вручную пароль не перезаписывается.
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

-- Чужой PUBLIC в базу не пускаем (трастовая граница — фаервол, не роль);
-- владелец pmapa_user имеет доступ неявно, GRANT ниже — для явности.
SELECT format('REVOKE CONNECT ON DATABASE %I FROM PUBLIC', :'db');
\gexec

SELECT format('GRANT CONNECT, TEMPORARY ON DATABASE %I TO %I', :'db', :'role');
\gexec

SELECT d.datname AS database,
       pg_get_userbyid(d.datdba) AS owner,
       pg_encoding_to_char(d.encoding) AS encoding
  FROM pg_database AS d
 WHERE d.datname = :'db';
