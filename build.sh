#!/usr/bin/env bash
# PMapa — сборка и проверка всего проекта.
#
#   ./build.sh              полный цикл: proto → go build/vet/test → flutter → docker
#   ./build.sh proto        только buf generate + lint
#   ./build.sh go           только Go: build + vet + test всех модулей
#   ./build.sh test-db      создать базы pmapa_<svc>_test на внешнем сервере
#   ./build.sh app          только Flutter: pub get + analyze + test
#   ./build.sh docker       только docker compose up --build (весь стек)
#   ./build.sh stats        один сервис: build + test + пересобрать его и gateway
#
# Порядок обязателен: gen/go — зависимость всех модулей, svckit — зависимость сервисов.
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$PWD"

# protoc-gen-dart ставится через `dart pub global` в ~/.pub-cache/bin, которого
# обычно нет в $PATH — без него buf generate падает на Dart-плагине.
export PATH="$PATH:$HOME/.pub-cache/bin"

# Модули go.work в порядке зависимостей.
MODULES=(svckit auth user travel post store message media notification stats)
# Сервисы с интеграционными тестами: у каждого своя база pmapa_<svc>_test
# на ВНЕШНЕМ сервере.
DB_SVCS=(auth user travel post store stay message media notification)
# Префикс баз (см. env/db/external/provision.sh): база каждого сервиса —
# pmapa_<svc> (pmapa_travel, pmapa_auth, …); пользователь у всех один — pmapa_user.
DB_PREFIX=pmapa_

# URL внешней базы лежат в .env (<SVC>_DATABASE_URL — их печатает
# env/db/external/provision.sh). Берём ТОЛЬКО эти строки, а не весь .env:
# в нём есть значения с пробелами и '<' (SMTP_FROM), которые ломают source.
load_db_urls() {
  [ -f .env ] || return 0
  while IFS= read -r line; do export "$line"; done \
    < <(grep -E '^[A-Z]+_DATABASE_URL=' .env)
}

# TEST_DATABASE_URL — тот же URL, но на базу pmapa_<svc>_test: тесты делают
# TRUNCATE, поэтому в рабочую базу их пускать нельзя. Пусто ⇒ интеграционные
# тесты делают t.Skip.
test_url() {
  local m=$1 var val db out
  var="$(printf '%s' "$m" | tr '[:lower:]' '[:upper:]')_DATABASE_URL"
  val="${!var:-}"
  [ -n "$val" ] || return 0
  db="${DB_PREFIX}${m}"
  case "$val" in
    */"$db"\?*) out="${val/"/$db?"//${db}_test?}" ;;
    */"$db")    out="${val}_test" ;;
    # URL не указывает на базу сервиса — молча писать тестами туда нельзя.
    *)
      echo "  ⚠ $var не указывает на базу $db — тесты $m пропускаю" >&2
      return 0
      ;;
  esac
  printf '%s' "$out"
}

say() { printf '\n\033[1;36m▸ %s\033[0m\n' "$*"; }

# ── 1. proto ────────────────────────────────────────────────────────────────
proto() {
  say "buf generate"
  # Сначала generate, потом lint: замечание к стилю .proto не должно оставлять
  # проект без сгенерированного кода (иначе не собирается вообще ничего).
  ( cd "$ROOT/proto" && buf generate )          # → gen/go, gen/dart
  for p in stats notification auth user travel post store message media; do
    test -d "$ROOT/proto/gen/go/pmapa/$p/v1" || {
      echo "gen/go/pmapa/$p/v1 отсутствует — buf generate не отработал"; exit 1; }
  done
  say "buf lint"
  ( cd "$ROOT/proto" && buf lint ) || echo "  ⚠ lint ругается — сборку не блокирую"
}

# ── 2. тестовые БД ──────────────────────────────────────────────────────────
# Тесты ищут TEST_DATABASE_URL (база pmapa_<svc>_test на внешнем сервере), без
# неё — t.Skip. Базы заводит provision.sh. Redis тоже внешний — поднимать
# локально нечего, тестам хватает REDIS_URL + REDIS_PASSWORD из .env.
test_db() {
  say "базы ${DB_PREFIX}<svc>_test на внешнем сервере"
  load_db_urls   # ADMIN_DATABASE_URL может лежать в .env, а не в окружении
  if [ -z "${ADMIN_DATABASE_URL:-}" ]; then
    echo "  ⚠ ADMIN_DATABASE_URL не задан — пропускаю (см. env/db/external/README.md)"
    echo "    export ADMIN_DATABASE_URL=postgres://postgres:PW@80.66.64.227:5432/postgres?sslmode=require"
  else
    ./env/db/external/provision.sh --with-test "$ADMIN_DATABASE_URL"
    for svc in "${DB_SVCS[@]}"; do echo "  ✓ база ${DB_PREFIX}${svc}_test"; done
  fi
  say "redis"
  echo "  ✓ внешний (managed) — контейнер поднимать не нужно"
}

# ── 3. Go ───────────────────────────────────────────────────────────────────
go_all() {
  say "go build + vet + test (${#MODULES[@]} модулей)"
  load_db_urls
  go work sync
  for m in "${MODULES[@]}"; do
    printf '\n\033[1m── %s\033[0m\n' "$m"
    # Считаем ДО subshell: test_url читает .env из корня репозитория.
    url=$(test_url "$m")
    ( cd "$m"
      go build ./...
      go vet ./...
      TEST_DATABASE_URL="$url" go test ./... )
  done
}

# ── 4. Flutter ──────────────────────────────────────────────────────────────
app() {
  say "flutter analyze + test"
  cd "$ROOT/app"
  flutter pub get
  flutter analyze
  flutter test
  cd "$ROOT"
}

# ── 5. docker ───────────────────────────────────────────────────────────────
docker_all() {
  say "docker compose up --build (весь стек)"
  test -f .env || cp .env.example .env
  docker compose up -d --build
  docker compose ps
  echo
  echo "  gateway  → http://localhost:8088"
  echo "  Mailpit  → http://localhost:8025"
  echo "  MinIO    → http://localhost:9001  (minioadmin/minioadmin)"
  echo "  клиент   → cd app && flutter run --dart-define=PMAPA_API_URL=http://localhost:8088"
}

# ── один сервис ─────────────────────────────────────────────────────────────
one() {
  local m=$1
  proto
  say "svckit + $m"
  ( cd svckit && go build ./... )
  load_db_urls
  url=$(test_url "$m")
  ( cd "$m" && go build ./... && go vet ./... && TEST_DATABASE_URL="$url" go test ./... )
  docker compose up -d --build "$m" gateway
}

case "${1:-all}" in
  proto)   proto ;;
  test-db) test_db ;;
  go)      go_all ;;
  app)     app ;;
  docker)  docker_all ;;
  all)     proto; test_db; go_all; app; docker_all
           say "готово" ;;
  *)       one "$1" ;;
esac
