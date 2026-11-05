# api-infra — план API-тестов (3 s2s-контракта: email, notify, purge)

Все три живут под `pmapa.api.*` — дом для контрактов, которые многие сервисы
реализуют одинаково. Это **s2s-поверхности** (доверенные пиры кластера), НЕ за
gateway-auth как end-user RPC, и в coverage.csv как owner-RPC НЕ учитываются.
Коды ошибок и каскады подтверждены по impl (purge.connect.go и шесть PurgeUser:
user/blocks.go, travel/store/purge.go, post/store/purge.go, message/*, media/*),
не угаданы.

## Границы контракта (важно)

- **api.email.SendEmail** и **api.notify.Notify** физически реализованы в сервисе
  notification. Их тест-матрицы уже лежат в `TEST/plan/notification.md` (блок
  «s2s-контракты», S1 и S2). Здесь НЕ дублируются — только ссылка, чтобы хэндофф
  был полным.
- **api.purge.PurgeService.PurgeUser** (pmapa.api.purge, UNVERSIONED by design) —
  один контракт, реализуемый **пятью** сервисами идентично по форме:
  **user, travel, post, message, media** (список подтверждён комментарием
  purge.connect.go). Каждый стирает ТОЛЬКО свой срез данных пользователя.
- **Scope-инвариант (ключевой для стабильности системы):** PurgeUser —
  **self-scoped по верифицированному caller**. Хендлер берёт `svckit.CallerID(req)`
  и стирает данные ИМЕННО этого id; тела запроса с «чужим» id нет. Auth во время
  удаления аккаунта зовёт каждый сервис s2s, проставляя X-User-Id удаляемого юзера.
  Поэтому «пользователь удаляется из auth, а в сервисе его нет» — НЕ ошибка:
  PurgeUser идемпотентен, стирание отсутствующих данных возвращает OK (no-op).

## Подтверждённые по impl свойства PurgeUser (общие для всех пяти)

- **AUTH:** нет X-User-Id -> `svckit.CallerID` возвращает ошибку -> **Unauthenticated**
  (в отличие от geo/stats, здесь caller ОБЯЗАТЕЛЕН — это записываемый контракт).
- **VALID:** есть данные caller -> удалены, пустой ответ `PurgeUserResponse{}`, OK.
- **IDEMP:** повтор / нет данных / неизвестный юзер -> OK, состояние не меняется.
- **FAIL:** ошибка стора -> `svckit.InternalErr` -> **Internal**.
- **Транзакционность:** user/travel/post/message стирают в ОДНОЙ транзакции
  (всё или ничего); media удаляет строки одним DELETE … RETURNING.

### Каскад по сервисам (что именно стирается — для ассертов полноты)

| Сервис | Стирает | Особенность |
|--------|---------|-------------|
| user | reports (filed), follow_requests (обе стороны), blocks (обе стороны), follows (обе стороны), profiles | одна tx |
| travel | trip_members (owner ИЛИ user), trip_shares (owner), visited, trips | одна tx |
| post | likes, saves, comments, reviews, posts (посты каскадят зависимые строки ON DELETE CASCADE) | счётчики engagement на ЧУЖИХ постах НЕ декрементятся (их лечит stats reconcile — ассерт: это ожидаемо, не баг) |
| message | reactions, read_cursors, members (выход из всех бесед); authored messages ТОМБСТОН�ятся (deleted=true, body='', image_url='') — строки остаются | структура беседы у других членов цела |
| media | строки media; для S3-backed — блобы best-effort (Delete, ошибка только логируется); inline-байты уходят со строкой | возвращает s3IDs внутри; ошибка блоба НЕ валит RPC |

## Подъём теста

- PurgeUser тестируется **общей гарнитурой** на каждом из пяти сервисов: поднять
  сервис на его обычном тире (postgres; media — + опционально S3/minio), засеять
  данные двух юзеров A и B, вызвать PurgeUser s2s с X-User-Id=A, проверить, что
  срез A стёрт, а срез B нетронут.
- Команда (пример для одного сервиса): `cd post && go test ./internal/service/ -run 'TestAPI_PurgeUser' -count=1 -v`
- SendEmail/Notify: см. notification.md (fake mail.Sender / push.Pusher).

## Легенда категорий

AUTH, VALID, IDEMP, FAIL (определения — в TEST/README.md).
NOTFOUND неприменим (стирание отсутствующего — валидный no-op, не ошибка).

---

## P. PurgeUser (единая матрица, применяется к каждому из 5 сервисов)

Вход: — (self-scoped по caller). Правила: caller обязателен; идемпотентен; одна tx.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | у caller есть данные в сервисе | OK, срез caller стёрт, срез другого юзера нетронут |
| 3 | IDEMP | повтор сразу после успешного purge | OK (no-op), повторное стирание безопасно |
| 4 | IDEMP | юзер без данных / неизвестный id | OK (no-op) — «нет данных» не ошибка |
| 5 | FAIL | стор/транзакция вернули ошибку | Internal |

### Доп. ассерты изоляции среза (per-service, к кейсу #2)

| Сервис | Проверить ПОСЛЕ purge A |
|--------|--------------------------|
| user | профиль A нет; follows/blocks/requests с участием A в обе стороны нет; reports, поданные A, нет; данные B целы |
| travel | trips/visited/shares A нет; членство A в чужих поездках снято; поездки B и их не-A участники целы |
| post | posts/comments/reviews/likes/saves A нет; посты B целы (их счётчики могут быть завышены — ожидаемо) |
| message | reactions/read_cursors/members A нет; сообщения A тумбстоун (deleted, пустое тело), но строки на месте; беседы B читаемы |
| media | строки media A нет; для S3 — Delete блоба вызван на каждый s3ID (best-effort, ошибка не валит); media B целы |

---

## E. EmailService.SendEmail — см. TEST/plan/notification.md (блок S1)

6 кейсов: VALID, INV-required (template/to), INV-format (to), INV-required
(missing template var), VALID (password_reset enrichment), FAIL (Sender error).

## N. NotifyService.Notify — см. TEST/plan/notification.md (блок S2)

5 кейсов: VALID (insert+push), INV-required (type/user_ids), VALID (все замьютили →
no-op), FAIL (insert error), VALID (pusher=nil/нет токенов → push пропущен).
