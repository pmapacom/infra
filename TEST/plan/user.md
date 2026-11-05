# user — план API-тестов (19 RPC)

Коды ошибок и лимиты ниже подтверждены по реализации
(user/internal/service/{profile,social,requests,blocks}.go), не угаданы.

## Подъём сервиса

- Тир данных: postgres (из env/db/user)
- Креды тестовой БД: из user/internal/service/user_test.go (подтвердить при написании теста)
- Команда: cd user && go test ./internal/service/ -run 'TestAPI' -count=1 -v
- Идентичность: заголовок X-User-Id (gateway). Профиль провижинится лениво при первом
  аутентифицированном запросе (EnsureProfile).

## Подтверждённые по impl особенности контракта

- Лимиты профиля (байты): maxDisplayName=100, maxBio=500, maxLocation=100,
  maxAvatarURL=512, maxSearchQuery=128 (рун, клампится, НЕ ошибка).
- handle: regexp ^[A-Za-z0-9_]{2,30}$. Занятый handle в UpdateMyProfile -> AlreadyExists.
- GetProfile: ровно одно из user_id|handle, иначе InvalidArgument; не найдено -> NotFound;
  если цель заблокировала вызывающего -> PermissionDenied (fail-closed, НЕ NotFound).
- Follow/Unfollow/Approve/Decline/Block/Unblock: пустой user_id -> InvalidArgument.
  Follow себя и Block себя -> InvalidArgument. Блок в любую сторону -> PermissionDenied (Follow).
- is_private — спящий маркер: каждый Follow немедленный, Requested=false;
  ListFollowRequests всегда пуст (dormant).
- Unfollow / Approve / Decline / Unblock — идемпотентны (нет цели -> OK, не NotFound).
- ReportContent: target_type in {user,post,message,listing}; reason in
  {spam,harassment,nudity,violence,hate,other}; details <= 2000; нельзя репортить себя
  (target_type=user & target_id=caller). Любое нарушение -> InvalidArgument.
- CheckHandle: некорректный handle -> Available=false БЕЗ ошибки.
- ListReports / ResolveReport — только админ (USER_ADMIN_IDS), иначе PermissionDenied.
  ResolveReport: пустой id или status not in {open,reviewing,resolved} -> InvalidArgument;
  неизвестный id -> NotFound.

## Легенда категорий

AUTH, VALID, INV-required, INV-oversize, INV-format, NOTFOUND, PERM, IDEMP, CONFLICT,
PAGE-clamp (определения — в TEST/README.md).

---

## 1. GetMyProfile

Вход: — (self по X-User-Id). Правила: ленивый провижининг, IsAdmin из allowlist.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | первый вызов нового пользователя | OK, профиль создан |
| 3 | IDEMP | повторный вызов | OK, тот же профиль |
| 4 | VALID | caller в USER_ADMIN_IDS | OK, IsAdmin=true |

## 2. UpdateMyProfile

Вход: display_name?, handle?, bio?, avatar_url?, current_location?, is_private.
Правила: patch (nil=как есть); лимиты; handle regex; занятый handle -> AlreadyExists.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | display_name="Alice" | OK |
| 3 | VALID | bio установлен (<=500) | OK |
| 4 | VALID | handle="alice_1" | OK |
| 5 | VALID | is_private=true (спящий) | OK |
| 6 | INV-oversize | bio >500 байт | InvalidArgument |
| 7 | INV-oversize | location >100 | InvalidArgument |
| 8 | INV-oversize | display_name >100 | InvalidArgument |
| 9 | INV-oversize | avatar_url >512 | InvalidArgument |
| 10 | INV-format | handle="a" / "bad handle!" | InvalidArgument |
| 11 | CONFLICT | handle уже занят | AlreadyExists |

## 3. GetProfile

Вход: ровно одно из user_id|handle. Правила: NotFound; блок цели -> PermissionDenied.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | по user_id | OK |
| 3 | VALID | по handle | OK |
| 4 | INV-format | и user_id, и handle | InvalidArgument |
| 5 | INV-required | ни одного | InvalidArgument |
| 6 | NOTFOUND | неизвестный user_id | NotFound |
| 7 | NOTFOUND | неизвестный handle | NotFound |
| 8 | PERM | цель заблокировала вызывающего | PermissionDenied |

## 4. BatchGetProfiles

Вход: user_ids[]. Правила: неизвестные молча отфильтровываются.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | список из 3 существующих | OK, 3 профиля |
| 3 | VALID | пустой список | OK, 0 профилей |
| 4 | VALID | смесь известных и неизвестных | OK, только известные |
| 5 | VALID | дубли id | OK, без ошибки |

## 5. Follow

Вход: user_id. Правила: обязателен; не себя; блок любой стороны -> PermissionDenied.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | следовать за другим | OK, Requested=false |
| 3 | INV-required | user_id="" | InvalidArgument |
| 4 | INV-format | user_id=caller (сам себя) | InvalidArgument |
| 5 | PERM | блок в любую сторону | PermissionDenied |
| 6 | IDEMP | повторный Follow | OK |

## 6. Unfollow

Вход: user_id. Идемпотентен.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | отписаться от того, за кем следуешь | OK |
| 3 | INV-required | user_id="" | InvalidArgument |
| 4 | IDEMP | отписка без подписки | OK (no-op) |

## 7. ListFollowers

Вход: user_id? (пусто=сам), cursor, limit.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | свои подписчики | OK, страница |
| 3 | VALID | подписчики другого | OK |
| 4 | VALID | пустой результат | OK, 0 |
| 5 | PAGE-clamp | limit=0 / очень большой | OK, обрезано |

## 8. ListFollowing

Вход: user_id? (пусто=сам), cursor, limit.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | свои подписки | OK |
| 3 | VALID | подписки другого | OK |
| 4 | VALID | пустой результат | OK, 0 |
| 5 | PAGE-clamp | limit=0 / большой | OK, обрезано |

## 9. ListFollowRequests

Вход: cursor, limit. Правила: dormant — всегда пусто.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | есть «подписки» | OK, 0 (спящая фича) |
| 3 | PAGE-clamp | limit границы | OK, обрезано |

## 10. ApproveFollow

Вход: user_id. Идемпотентен (нет pending -> OK).

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | одобрить запрос | OK |
| 3 | INV-required | user_id="" | InvalidArgument |
| 4 | IDEMP | нет pending-запроса | OK (no-op) |

## 11. DeclineFollow

Вход: user_id. Идемпотентен.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | отклонить запрос | OK |
| 3 | INV-required | user_id="" | InvalidArgument |
| 4 | IDEMP | нет pending-запроса | OK (no-op) |

## 12. BlockUser

Вход: user_id. Правила: обязателен; не себя. Идемпотентен.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | заблокировать другого | OK |
| 3 | INV-required | user_id="" | InvalidArgument |
| 4 | INV-format | user_id=caller | InvalidArgument |
| 5 | IDEMP | повторный Block | OK |

## 13. UnblockUser

Вход: user_id. Идемпотентен.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | разблокировать | OK |
| 3 | INV-required | user_id="" | InvalidArgument |
| 4 | IDEMP | разблокировать незаблокированного | OK (no-op) |

## 14. ListBlocked

Вход: cursor, limit.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | список заблокированных | OK |
| 3 | VALID | пустой результат | OK, 0 |
| 4 | PAGE-clamp | limit границы | OK, обрезано |

## 15. ReportContent

Вход: target_type, target_id, reason, details?. Правила: enum target_type/reason;
details <=2000; нельзя себя.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | report post/spam | OK |
| 3 | VALID | report message/harassment | OK |
| 4 | VALID | report listing/other + details | OK |
| 5 | INV-format | target_type="foo" | InvalidArgument |
| 6 | INV-required | target_id="" | InvalidArgument |
| 7 | INV-format | reason="bar" | InvalidArgument |
| 8 | INV-oversize | details >2000 | InvalidArgument |
| 9 | INV-format | target_type=user & target_id=caller | InvalidArgument |

## 16. ListReports (ADMIN)

Вход: status?, cursor, limit. Правила: только админ; status enum.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | админ, без фильтра | OK |
| 3 | VALID | админ, status="open" | OK |
| 4 | INV-format | status="weird" | InvalidArgument |
| 5 | PERM | не-админ | PermissionDenied |
| 6 | PAGE-clamp | limit границы | OK, обрезано |

## 17. ResolveReport (ADMIN)

Вход: id, status. Правила: только админ; id+valid status; неизвестный -> NotFound.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | админ, id+status="resolved" | OK |
| 3 | INV-required | id="" | InvalidArgument |
| 4 | INV-format | status="weird" | InvalidArgument |
| 5 | PERM | не-админ | PermissionDenied |
| 6 | NOTFOUND | неизвестный id | NotFound |

## 18. CheckHandle

Вход: handle. Правила: некорректный -> Available=false без ошибки.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | свободный handle | OK, Available=true |
| 3 | VALID | занятый handle | OK, Available=false |
| 4 | VALID | некорректный "a" | OK, Available=false |
| 5 | VALID | граница 2 символа | OK |
| 6 | VALID | граница 30 символов | OK |
| 7 | VALID | 31 символ | OK, Available=false |

## 19. SearchProfiles

Вход: query, cursor, limit. Правила: query клампится до 128 рун (не ошибка).

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | query="alice" | OK |
| 3 | VALID | пустой результат | OK, 0 |
| 4 | VALID | query >128 рун | OK, обрезан |
| 5 | VALID | unicode query | OK |
| 6 | PAGE-clamp | limit границы | OK, обрезано |
