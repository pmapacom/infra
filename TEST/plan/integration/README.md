# Интеграционные тесты — методология (фаза 3)

Этот каталог — фаза 3 из `TEST/README.md`. Отличие от per-RPC планов в
`TEST/plan/*.md` (фаза 2): там каждый сервис поднимается в одиночку, а зависимости
(user для post, Sender/Pusher для notification) подменяются фейками. Здесь сервис
работает в **тест-контуре целиком**, по реальному пути и с реальными соседями.

## Что именно проверяет интеграция (и чего НЕ проверяет фаза 2)

1. **Реальный путь запроса.** Клиент бьёт по `http://localhost:8088/<pkg>.<Svc>/<RPC>`
   через gateway (nginx). Проверяется то, что in-process harness обходит:
   - `auth_request` на gateway: owner-scoped RPC без валидного токена -> 401 ДО сервиса;
   - инъекция `X-User-Id` gateway'ем из проверенного токена (сервис ему доверяет);
   - снятие identity на PUBLIC-маршрутах (geo, stay/store reads, media serve);
   - DPoP-биндинг токена на реальном транспорте (как в `app/tool/*.dart`).
2. **Межсервисные вызовы по сети (XSVC).** Зависимости, которые в фазе 2 были фейками,
   здесь настоящие: post -> user (`CanView`, `Followees`), message -> notification
   (`Notify`), auth -> user (провижининг handle), auth -> все (`PurgeUser` веер).
3. **Поведение при упавшей зависимости (CHAOS).** Остановить контейнер соседа и
   проверить код ответа. Это ровно те error-path, что просели в юнит-покрытии
   (post fail-closed -> Unavailable, auth.internalErr, *.shareErr).
4. **Стримы и фон (STREAM).** `message.Subscribe`, rate-limit `sweep` — живьём, с
   реальными горутинами и Redis, а не в юнит-вакууме.
5. **Гонки на реальной БД (RACE).** Двойное бронирование, двойной `PutStay` с одним id.

## Подъём контура

- Контур: `env/test/contour/docker-compose.yml` (сейчас уже поднят — gateway на :8088,
  25 контейнеров). Порты/креды каждого сервиса подтверждать по этому compose и по
  `env/db/<svc>/docker-compose.yml` в момент написания теста, не угадывать.
- Транспорт из тестов: переиспользовать готовые гарнитуры `app/tool/*.dart`
  (`auth_smoke`, `e2e_abuse`, `e2e_media`, `e2e_forms`) — они уже ходят через DPoP и
  сгенерированные Connect-клиенты. Новые сценарии добавлять в том же стиле.
- Для CHAOS-кейсов: `docker compose -f env/test/contour/docker-compose.yml stop <svc>`
  перед вызовом, `start` после. Проверяется КОД (Unavailable/Unauthenticated), не текст.

## Легенда категорий (интеграционные)

- **RPATH** — реальный путь через gateway: auth_request, инъекция X-User-Id, DPoP.
- **XSVC** — межсервисный вызов по сети, зависимость НЕ фейк.
- **FANOUT** — s2s-веер по нескольким сервисам (PurgeUser, Notify, SendEmail).
- **CHAOS** — зависимость/БД остановлена, проверяем код ответа (fail-closed).
- **STREAM** — долгоживущий стрим или фоновая задача.
- **RACE** — конкурентные запросы к реальной БД, проверка инварианта.
- **PUBLIC** — маршрут без auth_request (gateway снимает identity).
- **FLOW** — многошаговый сценарий с проверкой состояния между шагами.

Коды ошибок наследуются из per-RPC планов `TEST/plan/*.md` (подтверждены по impl).
Здесь добавляются только те проверки, которые существуют ТОЛЬКО на реальном пути.

## Порядок исполнения (от инфраструктуры пути к веерам)

gateway/auth path -> user<->post граф -> message<->notification -> media serve ->
stay/store public+race -> travel sharing -> geo/stats public+internal ->
fanout (purge/email/notify). Детали — в файлах `integration/<svc>.md` и `_fanout.md`.
