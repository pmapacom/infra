# travel — план API-тестов (11 RPC)

Коды ошибок и лимиты подтверждены по реализации
(travel/internal/service/{travel,visited,sharing}.go), не угаданы.

## Подъём сервиса

- Тир данных: postgres (из env/db/travel)
- Креды тестовой БД: из travel/internal/service/travel_test.go (подтвердить при написании теста)
- Команда: cd travel && go test ./internal/service/ -run 'TestAPI' -count=1 -v
- Идентичность: все 11 RPC owner-scoped: svckit.CallerID -> нет -> Unauthenticated.
  Trip хранится как непрозрачный клиентский документ — сервис его НЕ парсит.
- PurgeUser (из purge-proto) в число 11 RPC не входит: это s2s-очистка, self-scoped,
  идемпотентна; тестируется отдельно вместе с остальными PurgeUser.

## Подтверждённые по impl особенности контракта

- Лимиты: maxDocumentBytes=262144 (256*1024) для trip-документа;
  maxKindBytes=64, maxKeyBytes=256, maxVisitedDocBytes=16384 (16*1024) для visited.
  Превышение -> InvalidArgument.
- PutTrip: id обязателен (trim) -> InvalidArgument; document > 256KB -> InvalidArgument;
  запись в чужой trip без прав коллаборатора (ErrForbidden) -> PermissionDenied.
  owner_id берётся из запроса (trim); серверное время ставит сервис.
- DeleteTrip: id обязателен; Delete идемпотентен (нет цели -> OK, не NotFound).
- ShareTrip / UnshareTrip: id обязателен; идемпотентны; ErrNotFound -> NotFound,
  ErrForbidden -> PermissionDenied (shareErr). ShareTrip возвращает share_code.
- JoinTrip: share_code обязателен -> InvalidArgument; неизвестный/отозванный код
  -> NotFound (shareErr).
- LeaveTrip: id обязателен; owner_id из запроса; идемпотентен; shareErr.
- RemoveTripMember: id И user_id обязательны -> InvalidArgument; чужой trip (не владелец)
  -> PermissionDenied, неизвестный trip -> NotFound (shareErr); идемпотентен.
- ListVisited: kind обязателен (≤64 байта) -> InvalidArgument; key НЕ требуется.
- PutVisited: kind (≤64) и key (≤256) обязательны -> InvalidArgument;
  document > 16KB -> InvalidArgument.
- DeleteVisited: kind и key обязательны -> InvalidArgument; идемпотентен.

## Легенда категорий

AUTH, VALID, INV-required, INV-oversize, INV-format, NOTFOUND, PERM, IDEMP, CONFLICT,
PAGE-clamp (определения — в TEST/README.md).

---

## 1. ListMyTrips

Вход: cursor, limit, since.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | свои поездки | OK, страница |
| 3 | VALID | пустой результат | OK, 0 |
| 4 | PAGE-clamp | limit границы | OK, обрезано |

## 2. PutTrip

Вход: id, owner_id?, document. Правила: id обязателен; document ≤256KB; чужой trip без прав -> PermissionDenied.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | создать свою поездку | OK |
| 3 | VALID | обновить свою (тот же id) | OK |
| 4 | INV-required | id="" | InvalidArgument |
| 5 | INV-oversize | document > 256KB | InvalidArgument |
| 6 | PERM | запись в чужой trip без прав | PermissionDenied |

## 3. DeleteTrip

Вход: id. Идемпотентен.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | удалить свою поездку | OK |
| 3 | INV-required | id="" | InvalidArgument |
| 4 | IDEMP | удалить несуществующую | OK (no-op) |

## 4. ShareTrip

Вход: id. Правила: id обязателен; идемпотентен; NotFound/PermissionDenied.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | включить шеринг своей поездки | OK, share_code |
| 3 | INV-required | id="" | InvalidArgument |
| 4 | NOTFOUND | неизвестный trip | NotFound |
| 5 | PERM | чужой trip | PermissionDenied |
| 6 | IDEMP | повторный шеринг | OK |

## 5. UnshareTrip

Вход: id. Правила: id обязателен; идемпотентен; NotFound/PermissionDenied.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | отключить шеринг своей поездки | OK |
| 3 | INV-required | id="" | InvalidArgument |
| 4 | NOTFOUND | неизвестный trip | NotFound |
| 5 | IDEMP | повторный unshare | OK |

## 6. JoinTrip

Вход: share_code. Правила: код обязателен; неизвестный/отозванный -> NotFound.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | присоединиться по коду | OK, trip |
| 3 | INV-required | share_code="" | InvalidArgument |
| 4 | NOTFOUND | неизвестный/отозванный код | NotFound |
| 5 | IDEMP | повторное присоединение | OK |

## 7. LeaveTrip

Вход: id, owner_id?. Идемпотентен.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | выйти из общей поездки | OK |
| 3 | INV-required | id="" | InvalidArgument |
| 4 | IDEMP | выйти без участия | OK (no-op) |

## 8. RemoveTripMember

Вход: id, user_id. Правила: оба обязательны; не владелец -> PermissionDenied; неизвестный trip -> NotFound.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | удалить участника из своей поездки | OK |
| 3 | INV-required | id="" или user_id="" | InvalidArgument |
| 4 | NOTFOUND | неизвестный trip | NotFound |
| 5 | PERM | не владелец trip | PermissionDenied |

## 9. ListVisited

Вход: kind, cursor, limit, since. Правила: kind обязателен (≤64); key не требуется.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | список посещённого по kind | OK |
| 3 | INV-required | kind="" или >64 байт | InvalidArgument |
| 4 | VALID | пустой результат | OK, 0 |
| 5 | PAGE-clamp | limit границы | OK, обрезано |

## 10. PutVisited

Вход: kind, key, document. Правила: kind≤64 и key≤256 обязательны; document≤16KB.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | добавить/обновить запись | OK |
| 3 | INV-required | kind="" или key="" | InvalidArgument |
| 4 | INV-oversize | kind >64 / key >256 / document >16KB | InvalidArgument |

## 11. DeleteVisited

Вход: kind, key. Идемпотентен.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | удалить запись | OK |
| 3 | INV-required | kind="" или key="" | InvalidArgument |
| 4 | IDEMP | удалить несуществующую | OK (no-op) |
