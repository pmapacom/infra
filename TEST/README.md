# TEST — план API-тестирования всех сервисов pmapa

Мастер-план. Цель: для КАЖДОГО сервиса поднять его целиком (сервис + его тир данных),
прогнать КАЖДЫЙ его API минимум 10 разнообразными запросами (валидные, невалидные,
границы, авторизация, идемпотентность, права, пагинация), собрать метрики и статистику
в таблицу. Этот каталог хранит планы и схему метрик. Сами тесты пишем на этапе 2,
интеграционные — на этапе 3.

## Структура каталога

    TEST/
      README.md              — этот файл: методология, инвентарь, фазы
      TEMPLATE.md            — шаблон матрицы на один API (>=10 кейсов)
      metrics/
        coverage.csv         — план покрытия (кейсов на API, по категориям)
        metrics.csv          — сводная статистика (заполняется после прогона)
      plan/
        message.md           — эталон (тесты уже написаны)
        user.md auth.md post.md stay.md store.md travel.md
        geo.md media.md notification.md stats.md api-infra.md

## Инвентарь сервисов и API

Источник — 14 .connect.go контрактов (124 RPC). Тир данных — из env/db/<svc> и
тест-контура env/test/contour/docker-compose.yml.

| Сервис | Go-модуль | RPC | Тир данных (для подъёма) | Есть тесты сервиса |
|--------|-----------|----:|--------------------------|--------------------|
| auth | auth/ | 13 | postgres + redis | да (service/auth_test.go) |
| user | user/ | 19 | postgres | да (service/user_test.go) |
| post | post/ | 19 | postgres (+ userclient) | да (service/post_test.go) |
| message | message/ | 20 + Subscribe | postgres :5437 | да, покрыто целиком |
| stay | stay/ | 13 | postgres | да (stays/bookings_test.go) |
| store | store/ | 8 | postgres | да (service/store_test.go) |
| travel | travel/ | 11 | postgres | да (service/travel_test.go) |
| geo | geo/ | 5 | статичный словарь (dict) | да (service/geo_test.go) |
| media | media/ | 2 | s3/minio + postgres | да (service/media_*_test.go) |
| notification | notification/ | 6 | postgres (+ smtp mock) | да (service/notification_test.go) |
| stats | stats/ | 5 | redis/postgres | да (service/stats_test.go) |
| api.email | в owner-сервисе | 1 | — | — |
| api.notify | в owner-сервисе | 1 | — | — |
| api.purge | fan-out | 1 | per-service | частично |
| Итого | | 124 | | |

Точные порты/креды тестовой БД берутся из <svc>/internal/service/*_test.go и
env/db/<svc>/docker-compose.yml при написании тестов (для message подтверждено:
message:devpass@localhost:5437/message_test). Коды ошибок по сервисам, кроме message,
в план-файлах помечаются «(подтвердить по impl)» — фиксируем по реализации в момент
написания теста, не угадываем.

## Два способа «поднять сервис целиком»

1. In-process harness (быстрый, основной) — как в message: реальный сервис-слой против
   реальной БД в контейнере, вызовы RPC напрямую методами сервиса с заголовком
   идентичности gateway (X-User-Id). Полное покрытие валидации и кодов ошибок, крутится
   в go test.
2. Чёрный ящик через HTTP (для метрик и реалистичности) — поднять бинарь в контейнере
   (его Dockerfile) + тир данных, бить по
   http://<svc>:8080/pmapa.<svc>.v1.<Svc>Service/<RPC> ConnectRPC-клиентом. Так меряем
   реальные HTTP-коды и латентность p50/p95.

План закладывает оба: матрицы кейсов (способ 1) + сценарий нагрузки >=10 запросов на API
с замером латентности (способ 2).

## Стандартные категории кейсов (гарантируют >=10 на API)

| Код | Категория | Что проверяет | Ожидаемый код |
|-----|-----------|---------------|---------------|
| AUTH | нет идентичности gateway | запрос без X-User-Id | Unauthenticated |
| VALID-1..n | happy path | валидные варианты входа | OK |
| INV-required | пустое обязательное поле | "" / отсутствует | InvalidArgument |
| INV-oversize | превышение лимита | длина > max | InvalidArgument |
| INV-format | битый формат/enum/схема | мусорное значение | InvalidArgument |
| NOTFOUND | неизвестная цель | случайный id | NotFound |
| PERM | нет прав | не-владелец / не-админ | PermissionDenied |
| IDEMP | повтор операции | тот же запрос дважды | OK (no-op) |
| CONFLICT | дубль уникального | занятый id | AlreadyExists |
| PAGE-clamp | границы пагинации | limit=0 / >Max / отрицательный | OK, обрезан до Max |
| RATE | превышение лимита | burst+1 за окно | ResourceExhausted |

Если применимых категорий < 10 (например, read-only geo.GetCountry), добираем до 10
вариациями VALID (разные валидные значения, регистр, локали, пагинация, пустой результат).

## Схема метрик и статистики

metrics/coverage.csv (план, заполняется из план-файлов), колонки:

    service,api,total,valid,invalid,auth,notfound,permission,idempotent,conflict,pagination,ratelimit

metrics/metrics.csv (результат прогона, заполняется после этапа 2), колонки:

    service,api,cases,passed,failed,skipped,invalid_arg_ok,notfound_ok,perm_ok,p50_ms,p95_ms,max_ms,coverage_pct,run_at

«Глубина проверки» API = число покрытых категорий из применимых.

## Фазы работы

1. План (этот каталог). Матрицы >=10 кейсов на каждый из 124 API + схема метрик.
2. Тесты. По матрицам пишем <svc>/internal/service/api_coverage_test.go (как у message),
   поднимаем тир данных сервиса, прогоняем, заполняем metrics/metrics.csv.
3. Интеграционные. Через тест-контур (env/test/contour) по реальному пути
   app -> gateway(nginx) -> сервис; межсервисные сценарии (post<->user,
   message<->notification, purge fan-out).

## Порядок исполнения сервисов (от ядра к периферии)

message (готово) -> user -> auth -> post -> stay -> store -> travel -> notification ->
media -> geo -> stats -> api-infra. Сначала сервисы с наибольшим числом API и
зависимостями ядра, затем read-mostly и инфраструктурные.
