# notification — план API-тестов (6 end-user RPC + 2 s2s-контракта)

Коды ошибок и правила подтверждены по реализации
(notification/internal/service/notification.go) и контракту
(proto/.../notificationv1connect/notification.connect.go), не угаданы.

## Границы контракта (важно)

- **NotificationService** (v1, end-user surface, через gateway за auth) —
  6 RPC: ListNotifications, MarkNotificationsRead, RegisterDevice,
  UnregisterDevice, GetNotificationPrefs, UpdateNotificationPrefs.
  Все owner-scoped: svckit.CallerID -> нет X-User-Id -> Unauthenticated.
- **EmailService.SendEmail** и **NotifyService.Notify** реализованы в том же
  сервисе, но это ОТДЕЛЬНЫЕ s2s-контракты (pmapa.api.email / pmapa.api.notify),
  НЕ в v1 и НЕ за gateway: вызываются доверенными пирами, без caller-проверки.
  Тестируются отдельной s2s-гарнитурой (как PurgeUser) — вынесены в конец файла.
- Замечание по impl: `feed == nil` деградирует в no-op/пустой ответ (push и in-app
  feed выключены). В API-тестах feed поднят, поэтому проверяем нормальный путь;
  nil-ветку покрывает отдельный unit-тест, не API-матрица.

## Подъём сервиса

- Тир данных: postgres (из env/db/notification); feed = store.DB
- Креды тестовой БД: из notification/internal/service/notification_test.go
  (подтвердить при написании теста)
- Команда: cd notification && go test ./internal/service/ -run 'TestAPI' -count=1 -v
- Фейки: Sender (mail.LogSender), push.Pusher — подменяются для SendEmail/Notify.

## Подтверждённые по impl особенности контракта

- RegisterDevice: token (trim) ОБЯЗАТЕЛЕН -> InvalidArgument; platform опционален;
  upsert по (caller, token) — идемпотентен.
- UnregisterDevice: АСИММЕТРИЯ с RegisterDevice — пустой token НЕ ошибка, а тихий
  no-op (OK). Снятие несуществующего токена -> OK. Идемпотентен.
- GetNotificationPrefs: возвращает map явных per-type override (Enabled); нет
  override -> пустая map (дефолт — включено, трактуется на стороне EnabledRecipients).
- UpdateNotificationPrefs: пишет req.Enabled как есть, БЕЗ валидации ключей/типов
  (неизвестный тип примется) — upsert.
- ListNotifications: newest-first; возвращает next_cursor и unread_count;
  нет oversize-валидации; cursor/limit — пагинация.
- MarkNotificationsRead: MarkAllRead для caller; идемпотентен (повтор -> OK, unread=0).

## Легенда категорий

AUTH, VALID, INV-required, INV-oversize, INV-format, NOTFOUND, PERM, IDEMP, CONFLICT,
PAGE-clamp (определения — в TEST/README.md).

---

## 1. ListNotifications

Вход: cursor, limit. Правила: caller обязателен; newest-first; next_cursor, unread_count.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | свои уведомления | OK, newest-first, unread_count |
| 3 | VALID | пустой feed | OK, 0, next_cursor="" |
| 4 | PAGE-clamp | limit границы / следующая страница по cursor | OK, обрезано/next_cursor |

## 2. MarkNotificationsRead

Вход: —. Правила: caller обязателен; MarkAllRead; идемпотентен.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | отметить все прочитанными | OK, затем ListNotifications: unread_count=0 |
| 3 | IDEMP | повторно без непрочитанных | OK (no-op), unread=0 |

## 3. RegisterDevice

Вход: token, platform?. Правила: caller обязателен; token обязателен (trim); upsert.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | token + platform | OK, устройство зарегистрировано |
| 3 | INV-required | token="" или только пробелы | InvalidArgument |
| 4 | IDEMP | тот же token повторно | OK, ровно одна запись (upsert) |

## 4. UnregisterDevice

Вход: token. Правила: caller обязателен; пустой token -> тихий no-op OK (НЕ ошибка); идемпотентен.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | снять зарегистрированный token | OK, токена больше нет |
| 3 | IDEMP | token="" | OK (no-op, НЕ InvalidArgument — асимметрия с RegisterDevice) |
| 4 | IDEMP | снять несуществующий / повторно | OK (no-op) |

## 5. GetNotificationPrefs

Вход: —. Правила: caller обязателен; возвращает map override.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | после UpdateNotificationPrefs | OK, Enabled содержит заданные override |
| 3 | VALID | без заданных override | OK, пустая map (дефолты) |

## 6. UpdateNotificationPrefs

Вход: enabled (map type->bool). Правила: caller обязателен; пишет как есть, без валидации ключей; upsert.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | {"message.new":false} | OK, Get возвращает тот же override |
| 3 | VALID | пустая map | OK (no-op/сброс по контракту store) |
| 4 | IDEMP | повтор того же набора | OK, состояние не меняется (upsert) |

---

## s2s-контракты (отдельная гарнитура, без caller-проверки)

Эти два RPC НЕ входят в 6 end-user RPC и НЕ идут в coverage.csv как notification-строки
(аналогично PurgeUser). Матрицы приведены для полноты s2s-покрытия.

### S1. EmailService.SendEmail

Вход: template, to, vars. Правила (impl): template и to обязательны (trim);
to валиден (mail.ParseAddress); все Required(template) vars непустые; render ok;
password_reset -> enrichment link=base+token при resetURLBase.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | VALID | известный template + валидный to + все vars | OK, Sender.Send вызван |
| 2 | INV-required | template="" или to="" | InvalidArgument |
| 3 | INV-format | to не email-адрес | InvalidArgument |
| 4 | INV-required | отсутствует обязательная template-переменная | InvalidArgument (missing template variable: X) |
| 5 | VALID | password_reset + resetURLBase | OK, link=base+token подставлен |
| 6 | FAIL | Sender.Send вернул ошибку | Internal |

### S2. NotifyService.Notify

Вход: type, user_ids, actor_id, data. Правила (impl): type и user_ids обязательны;
EnabledRecipients фильтрует замьюченных; пустой список получателей -> OK no-op;
Insert err -> Internal; push best-effort (ошибки глотаются); data НЕ логируется.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | VALID | type + user_ids | OK, Insert на разрешённых получателей, push вызван |
| 2 | INV-required | type="" или user_ids пуст | InvalidArgument |
| 3 | VALID | все получатели замьютили тип | OK, Insert НЕ вызван (no-op) |
| 4 | FAIL | Insert вернул ошибку | Internal |
| 5 | VALID | pusher=nil или нет токенов | OK (push пропущен, событие успешно) |
