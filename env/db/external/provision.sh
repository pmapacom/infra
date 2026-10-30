#!/usr/bin/env bash
# PMapa — подготовка ВНЕШНЕГО Postgres: своя база + login-роль на каждый сервис.
#
#   PGPASSWORD=<админский> ./env/db/external/provision.sh
#   PGPASSWORD=<админский> ./env/db/external/provision.sh --with-test
#   ./env/db/external/provision.sh "postgres://postgres:pw@80.66.64.227:5432/postgres?sslmode=require"
#
# Имя базы = имя роли = pmapa_<svc>: pmapa_auth, pmapa_user, pmapa_travel, …
# Хост/порт по умолчанию — внешний сервер 80.66.64.227:5432 (переопределяется
# DB_HOST / DB_PORT / DB_SSLMODE / DB_ADMIN_USER / DB_ADMIN_DB).
#
# Что делает (идемпотентно):
#   1. роль pmapa_<svc> и базу pmapa_<svc> (владелец — эта роль);
#   2. pg_trgm и btree_gist внутри каждой базы (под админом, чтобы миграциям
#      message/stay не требовался superuser);
#   3. --with-test — ещё и базы pmapa_<svc>_test для интеграционных тестов;
#   4. печатает готовые строки <SVC>_DATABASE_URL для корневого .env.
#
# ПАРОЛИ скрипт НЕ генерирует и НЕ меняет. Новая роль создаётся с паролем из
# <SVC>_DB_PASSWORD (или с заглушкой change-me); существующая роль не трогается —
# пароль меняется вручную: ALTER ROLE pmapa_travel PASSWORD '…';
set -euo pipefail
cd "$(dirname "$0")"

PREFIX="pmapa_"
SERVICES=(auth user travel post store stay message media notification)

DB_HOST="${DB_HOST:-80.66.64.227}"
DB_PORT="${DB_PORT:-5432}"
# Внешняя база ходит через публичную сеть: при sslmode=disable пароль ушёл бы
# открытым текстом, поэтому по умолчанию require.
DB_SSLMODE="${DB_SSLMODE:-require}"
DB_ADMIN_USER="${DB_ADMIN_USER:-postgres}"
# CREATE DATABASE нельзя выполнить, будучи подключённым к создаваемой базе, —
# нужна служебная база для входа админа.
DB_ADMIN_DB="${DB_ADMIN_DB:-postgres}"

WITH_TEST=0
ADMIN_URL=""

usage() {
	sed -n '2,24p' "$0" >&2
	exit 2
}

while [ $# -gt 0 ]; do
	case "$1" in
	--with-test) WITH_TEST=1 ;;
	-h | --help) usage ;;
	-*)
		echo "неизвестный флаг: $1" >&2
		usage
		;;
	*) ADMIN_URL="$1" ;;
	esac
	shift
done

ADMIN_URL="${ADMIN_URL:-${ADMIN_DATABASE_URL:-}}"

# Полный админский URL разбираем в libpq-переменные: имя базы меняется на каждом
# шаге (postgres → pmapa_<svc>), а хост/пользователь/пароль остаются общими.
# Пароль берётся как есть, без percent-декодирования: если в нём есть @ : / ?,
# передайте его через PGPASSWORD вместо URL.
if [ -n "$ADMIN_URL" ]; then
	re='^postgres(ql)?://([^:/?@]+)(:([^@]*))?@([^:/?]+)(:([0-9]+))?(/([^?]*))?(\?(.*))?$'
	if [[ ! "$ADMIN_URL" =~ $re ]]; then
		echo "не разобрал URL (ожидаю postgres://user:pw@host:port/db?sslmode=…): $ADMIN_URL" >&2
		exit 2
	fi
	DB_ADMIN_USER="${BASH_REMATCH[2]}"
	if [ -n "${BASH_REMATCH[4]}" ]; then export PGPASSWORD="${BASH_REMATCH[4]}"; fi
	DB_HOST="${BASH_REMATCH[5]}"
	if [ -n "${BASH_REMATCH[7]}" ]; then DB_PORT="${BASH_REMATCH[7]}"; fi
	if [ -n "${BASH_REMATCH[9]}" ]; then DB_ADMIN_DB="${BASH_REMATCH[9]}"; fi
	query="${BASH_REMATCH[11]}"
	case "$query" in
	*sslmode=*)
		DB_SSLMODE="${query#*sslmode=}"
		DB_SSLMODE="${DB_SSLMODE%%&*}"
		;;
	esac
fi

command -v psql >/dev/null 2>&1 || {
	echo "psql не найден: brew install libpq && brew link --force libpq" >&2
	exit 1
}

# Пароль остаётся в PGPASSWORD / ~/.pgpass и не попадает в командную строку.
export PGHOST="$DB_HOST" PGPORT="$DB_PORT" PGUSER="$DB_ADMIN_USER" PGSSLMODE="$DB_SSLMODE"

echo "==> сервер ${DB_HOST}:${DB_PORT} (admin ${DB_ADMIN_USER}/${DB_ADMIN_DB}, sslmode=${DB_SSLMODE})"

urls=""
placeholders=0
for svc in "${SERVICES[@]}"; do
	role="${PREFIX}${svc}"
	db="$role"
	var="$(printf '%s' "$svc" | tr '[:lower:]' '[:upper:]')_DB_PASSWORD"
	pw="${!var:-change-me}"
	[ "$pw" = "change-me" ] && placeholders=1

	echo "==> роль и база ${db}"
	psql -d "$DB_ADMIN_DB" -v ON_ERROR_STOP=1 -q \
		-v role="$role" -v db="$db" -v pw="$pw" -f database.sql
	psql -d "$db" -v ON_ERROR_STOP=1 -q -f extensions.sql

	if [ "$WITH_TEST" = 1 ]; then
		echo "==> база ${db}_test"
		psql -d "$DB_ADMIN_DB" -v ON_ERROR_STOP=1 -q \
			-v role="$role" -v db="${db}_test" -f test_database.sql
		psql -d "${db}_test" -v ON_ERROR_STOP=1 -q -f extensions.sql
	fi

	urls="${urls}$(printf '%s' "$svc" | tr '[:lower:]' '[:upper:]')_DATABASE_URL=postgres://${role}:${pw}@${DB_HOST}:${DB_PORT}/${db}?sslmode=${DB_SSLMODE}
"
done

cat <<EOF

Готово. Вставьте в корневой .env (локальный стек):

$(printf '%s' "$urls")
EOF

if [ "$placeholders" = 1 ]; then
	cat <<EOF
Пароли скрипт не выставлял. Задайте их сами, например:

  psql -d postgres -c "ALTER ROLE ${PREFIX}travel PASSWORD 'ваш-пароль'"

и подставьте тот же пароль в URL выше (в prod он идёт отдельно, через
PGPASSWORD — см. env/prod/<svc>/.env.example).
EOF
fi
