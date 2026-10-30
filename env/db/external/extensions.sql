-- PMapa — расширения ВНУТРИ базы сервиса. Запускается под админом, уже
-- подключённым к pmapa_<svc>:
--
--   psql -d pmapa_message -v ON_ERROR_STOP=1 -f extensions.sql
--
-- Зачем: миграции message/0006_search.sql (pg_trgm) и stay/0002_bookings.sql
-- (btree_gist) делают CREATE EXTENSION IF NOT EXISTS, а это требует superuser.
-- Админ ставит расширение заранее — и в миграции оно становится no-op, без
-- проверки прав. Ставим оба во все базы: лишнее расширение ничего не стоит, а
-- сервисам не нужно помнить, какое именно им понадобится после очередной
-- миграции.
\set ON_ERROR_STOP on

CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS btree_gist;

SELECT current_database() AS database, extname, extversion
  FROM pg_extension
 WHERE extname IN ('pg_trgm', 'btree_gist')
 ORDER BY extname;
