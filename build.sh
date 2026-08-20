#!/usr/bin/env bash
# PMapa — сборка и проверка всего проекта.
#
#   ./build.sh              полный цикл: proto → go build/vet/test → flutter → docker
#   ./build.sh proto        только buf generate + lint
#   ./build.sh go           только Go: build + vet + test всех модулей
#   ./build.sh test-db      поднять data-tier и создать тестовые БД (<svc>_test)
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
# Сервисы с интеграционными тестами: имя:порт (пользователь и пароль = имя/devpass).
DB_SVCS=(auth:5432 user:5433 travel:5434 post:5435 store:5436 message:5437 media:5438 notification:5439)

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
# Тесты ищут TEST_DATABASE_URL, иначе postgres://<svc>:devpass@localhost:<port>/<svc>_test
# и без неё делают t.Skip. Поднимаем только data-tier и заводим <svc>_test.
test_db() {
  say "data-tier + тестовые БД"
  docker compose up -d auth-postgres user-postgres travel-postgres post-postgres \
                       store-postgres message-postgres media-postgres notification-postgres \
                       auth-redis stats-redis
  for e in "${DB_SVCS[@]}"; do
    svc=${e%%:*}
    for i in $(seq 30); do
      docker compose exec -T "$svc-postgres" pg_isready -U "$svc" -q && break || sleep 1
    done
    docker compose exec -T "$svc-postgres" \
      psql -U "$svc" -d "$svc" -v ON_ERROR_STOP=0 \
      -c "CREATE DATABASE ${svc}_test" 2>/dev/null || true
    echo "  ✓ ${svc}_test @ localhost:${e##*:}"
  done
}

# ── 3. Go ───────────────────────────────────────────────────────────────────
go_all() {
  say "go build + vet + test (${#MODULES[@]} модулей)"
  go work sync
  for m in "${MODULES[@]}"; do
    printf '\n\033[1m── %s\033[0m\n' "$m"
    ( cd "$m"
      go build ./...
      go vet ./...
      # Порт тестовой БД по имени модуля; у notification/stats своей БД нет.
      url=""
      for e in "${DB_SVCS[@]}"; do
        [ "${e%%:*}" = "$m" ] && url="postgres://$m:devpass@localhost:${e##*:}/${m}_test?sslmode=disable"
      done
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
  url=""
  for e in "${DB_SVCS[@]}"; do
    [ "${e%%:*}" = "$m" ] && url="postgres://$m:devpass@localhost:${e##*:}/${m}_test?sslmode=disable"
  done
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
