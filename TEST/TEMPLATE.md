# Шаблон план-файла сервиса

Копировать в TEST/plan/<svc>.md для каждого сервиса. Один раздел на RPC.
Матрица — минимум 10 строк на API.

## Подъём сервиса

- Тир данных: <postgres/redis/s3 — образы и порты>
- Креды тестовой БД: <из <svc>/internal/service/*_test.go>
- Команда: cd <svc> && go test ./internal/service/ -run 'TestAPI' -count=1 -v
- Чёрный ящик: docker compose -f env/db/<svc>/docker-compose.yml up -d + бинарь из <svc>/Dockerfile

## Легенда категорий

AUTH, VALID, INV-required, INV-oversize, INV-format, NOTFOUND, PERM, IDEMP, CONFLICT,
PAGE-clamp, RATE (определения — в TEST/README.md).
