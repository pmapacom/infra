#!/usr/bin/env bash
# PMapa — подготовка ВНЕШНЕГО Postgres: ОДНА login-роль pmapa_user + своя база
# на каждый сервис.
#
#   PGPASSWORD=<админский> ./env/db/external/provision.sh
#   PGPASSWORD=<админский> ./env/db/external/provision.sh --with-test
#   ./env/db/external/provision.sh "postgres://postgres:pw@80.66.64.227:5432/postgres?sslmode=require"
#
# Роль одна на все сервисы — pmapa_user; база у каждого своя — pmapa_<svc>
# (pmapa_auth, pmapa_user, pmapa_travel, …), владелец каждой базы — pmapa_user.
# Все сервисы на одной машине, доступ к базе закрыт фаерволом по IP, а утечка
# одного пароля = утечка всех, поэтому раздельные роли смысла не имеют: один
# пользователь, один пароль. Разделение теперь только логическое (разные базы).
#
# Хост/порт по умолчанию — внешний сервер 80.66.64.227:5432 (переопределяется
# DB_HOST / DB_PORT / DB_SSLMODE / DB_ADMIN_USER / DB_ADMIN_DB).
#
# Что делает (идемпотентно):
#   1. роль pmapa_user (один раз) и базу pmapa_<svc> (владелец — pmapa_user);
#   2. pg_trgm и btree_gist внутри каждой базы (под админом, чтобы миграциям
#      message/stay не требовался superuser);
#   3. --with-test — ещё и базы pmapa_<svc>_test для интеграционных тестов;
#   4. печатает готовые строки <SVC>_DATABASE_URL для корневого .env.
#
# ПАРОЛЬ скрипт НЕ генерирует и НЕ меняет. Роль создаётся с паролем из
# PMAPA_DB_PASSWORD (или с заглушкой change-me); существующая роль не трогается —
# пароль меняется вручную: ALTER ROLE pmapa_user PASSWORD '…';
set -euo pipefail
cd "$(dirname "$0")"

PREFIX="pmapa_"
ROLE="pmapa_user"
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

# Один пароль на единую роль pmapa_user (см. шапку). Пусто ⇒ заглушка change-me.
PW="${PMAPA_DB_PASSWORD:-change-me}"
placeholders=0
[ "$PW" = "change-me" ] && placeholders=1

urls=""
for svc in "${SERVICES[@]}"; do
	db="${PREFIX}${svc}"

	echo "==> роль ${ROLE} и база ${db}"
	psql -d "$DB_ADMIN_DB" -v ON_ERROR_STOP=1 -q \
		-v role="$ROLE" -v db="$db" -v pw="$PW" -f database.sql
	psql -d "$db" -v ON_ERROR_STOP=1 -q -f extensions.sql

	if [ "$WITH_TEST" = 1 ]; then
		echo "==> база ${db}_test"
		psql -d "$DB_ADMIN_DB" -v ON_ERROR_STOP=1 -q \
			-v role="$ROLE" -v db="${db}_test" -f test_database.sql
		psql -d "${db}_test" -v ON_ERROR_STOP=1 -q -f extensions.sql
	fi

	urls="${urls}$(printf '%s' "$svc" | tr '[:lower:]' '[:upper:]')_DATABASE_URL=postgres://${ROLE}:${PW}@${DB_HOST}:${DB_PORT}/${db}?sslmode=${DB_SSLMODE}
"
done

cat <<EOF

Готово. Вставьте в корневой .env (локальный стек):

$(printf '%s' "$urls")
EOF

if [ "$placeholders" = 1 ]; then
	cat <<EOF
Пароль скрипт не выставлял. Задайте его сам, например:

  psql -d postgres -c "ALTER ROLE ${ROLE} PASSWORD 'ваш-пароль'"

и подставьте тот же пароль в URL выше (в prod он идёт отдельно, через
PGPASSWORD — см. env/prod/<svc>/.env.example).
EOF
fi
