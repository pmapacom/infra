# post — план API-тестов (19 RPC)

Коды ошибок и лимиты подтверждены по реализации
(post/internal/service/{post,posts,engagement,reviews}.go), не угаданы.

## Подъём сервиса

- Тир данных: postgres (из env/db/post). Зависимости user-сервиса (FolloweeSource,
  ProfileGate) в тестах подменяются фейками — как в post_test.go.
- Креды тестовой БД: из post/internal/service/post_test.go (подтвердить при написании теста)
- Команда: cd post && go test ./internal/service/ -run 'TestAPI' -count=1 -v
- Идентичность: все RPC требуют X-User-Id (svckit.CallerID) -> нет -> Unauthenticated.

## Подтверждённые по impl особенности контракта

- Лимиты (байты): maxPostBytes=10240, maxPlaceBytes=256, maxURLBytes=2048,
  maxCommentBytes=2048, maxReviewBytes=4096, maxSubjectBytes=256. Превышение -> InvalidArgument.
- authorize(): свой контент (author=="" или author==caller) всегда виден; для чужого —
  спрашивает user.CanView. Приватный автор -> PermissionDenied; user-сервис недоступен ->
  Unavailable (fail-closed, контент скрыт).
- PutPost: id обязателен (InvalidArgument); чужой id (ErrWrongOwner) -> AlreadyExists.
- DeletePost / DeleteReview: DeleteOwn/DeleteReview не возвращают NotFound на отсутствие —
  идемпотентны (нет цели -> OK).
- GetPost: id обязателен; ErrNotFound -> NotFound; затем authorize (приватный -> PermissionDenied).
- ListUserPosts: user_id пуст -> caller; приватный автор -> PermissionDenied.
- ListFeed: follow-граф берётся у user (Followees); недоступен -> Unavailable.
- Like/Save (добавление ребра) проходят через authorize цели (NotFound на неизвестный post,
  PermissionDenied на приватного). Unlike/Unsave НЕ проверяют приватность (своё ребро),
  но post_id обязателен и неизвестный post -> NotFound.
- AddComment: post_id и text обязательны; text > 2048 -> InvalidArgument; AuthorOf ->
  NotFound; authorize цели.
- DeleteComment: id обязателен; чужой комментарий (ErrForbidden) -> PermissionDenied.
- ListComments: post_id обязателен; AuthorOf -> NotFound; authorize.
- PutReview: id и subject обязательны; subject>256 / text>4096 -> InvalidArgument;
  rating вне 1..5 -> InvalidArgument; чужой id -> AlreadyExists.
- ListReviews: subject обязателен.

## Легенда категорий

AUTH, VALID, INV-required, INV-oversize, INV-format, NOTFOUND, PERM, IDEMP, CONFLICT,
PAGE-clamp (определения — в TEST/README.md).

---

## 1. ListMyPosts

Вход: cursor, limit.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | свои посты | OK, страница |
| 3 | VALID | пустой результат | OK, 0 |
| 4 | PAGE-clamp | limit=0 / большой | OK, обрезано |

## 2. GetMyStats

Вход: — (self).

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | есть активность | OK, счётчики |
| 3 | VALID | нет активности | OK, нули |

## 3. PutPost

Вход: id, type, text, place?, image_url?. Правила: id обязателен; лимиты; чужой id -> AlreadyExists.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | создать пост | OK |
| 3 | VALID | обновить свой (тот же id) | OK |
| 4 | INV-required | id="" | InvalidArgument |
| 5 | INV-oversize | text >10240 байт | InvalidArgument |
| 6 | INV-oversize | place >256 / image_url >2048 | InvalidArgument |
| 7 | CONFLICT | id принадлежит другому | AlreadyExists |
| 8 | VALID | с place и image_url | OK |

## 4. DeletePost

Вход: id. Идемпотентен.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | удалить свой пост | OK |
| 3 | INV-required | id="" | InvalidArgument |
| 4 | IDEMP | удалить несуществующий | OK (no-op) |

## 5. GetPost

Вход: id. Правила: id обязателен; NotFound; authorize.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | свой/публичный пост | OK |
| 3 | INV-required | id="" | InvalidArgument |
| 4 | NOTFOUND | неизвестный id | NotFound |
| 5 | PERM | приватный автор | PermissionDenied |

## 6. ListUserPosts

Вход: user_id?, cursor, limit. Правила: пусто -> caller; приватный -> PermissionDenied.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | свои посты (user_id="") | OK |
| 3 | VALID | публичный автор | OK |
| 4 | PERM | приватный автор | PermissionDenied |
| 5 | PAGE-clamp | limit границы | OK, обрезано |

## 7. ListFeed

Вход: cursor, limit. Правила: follow-граф у user; недоступен -> Unavailable.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | лента по подпискам | OK |
| 3 | VALID | пустая лента | OK, 0 |
| 4 | PAGE-clamp | limit границы | OK, обрезано |

## 8. ListSavedPosts

Вход: cursor, limit.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | сохранённые посты | OK |
| 3 | VALID | пусто | OK, 0 |
| 4 | PAGE-clamp | limit границы | OK, обрезано |

## 9. LikePost

Вход: post_id. Правила: authorize цели; NotFound/PermissionDenied.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | лайк публичного поста | OK |
| 3 | INV-required | post_id="" | InvalidArgument |
| 4 | NOTFOUND | неизвестный post | NotFound |
| 5 | PERM | приватный автор | PermissionDenied |

## 10. UnlikePost

Вход: post_id. Правила: приватность НЕ проверяется; post_id обязателен; NotFound.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | снять лайк | OK |
| 3 | INV-required | post_id="" | InvalidArgument |
| 4 | NOTFOUND | неизвестный post | NotFound |
| 5 | IDEMP | снять лайк без лайка | OK (no-op) |

## 11. SavePost

Вход: post_id. Правила: authorize цели; NotFound/PermissionDenied.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | сохранить публичный пост | OK |
| 3 | INV-required | post_id="" | InvalidArgument |
| 4 | NOTFOUND | неизвестный post | NotFound |
| 5 | PERM | приватный автор | PermissionDenied |

## 12. UnsavePost

Вход: post_id. Правила: приватность НЕ проверяется; post_id обязателен; NotFound.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | убрать из сохранённых | OK |
| 3 | INV-required | post_id="" | InvalidArgument |
| 4 | NOTFOUND | неизвестный post | NotFound |
| 5 | IDEMP | убрать без сохранения | OK (no-op) |

## 13. AddComment

Вход: post_id, text. Правила: оба обязательны; text>2048; AuthorOf -> NotFound; authorize.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | комментарий к публичному посту | OK |
| 3 | INV-required | post_id="" или text="" | InvalidArgument |
| 4 | INV-oversize | text >2048 | InvalidArgument |
| 5 | NOTFOUND | неизвестный post | NotFound |
| 6 | PERM | приватный автор | PermissionDenied |

## 14. DeleteComment

Вход: id. Правила: id обязателен; чужой -> PermissionDenied.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | удалить свой комментарий | OK |
| 3 | INV-required | id="" | InvalidArgument |
| 4 | PERM | чужой комментарий | PermissionDenied |

## 15. ListComments

Вход: post_id, cursor, limit. Правила: post_id обязателен; AuthorOf -> NotFound; authorize.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | комментарии публичного поста | OK |
| 3 | INV-required | post_id="" | InvalidArgument |
| 4 | NOTFOUND | неизвестный post | NotFound |
| 5 | PERM | приватный автор | PermissionDenied |
| 6 | PAGE-clamp | limit границы | OK, обрезано |

## 16. PutReview

Вход: id, subject, rating, text?. Правила: id+subject обязательны; rating 1..5; чужой id -> AlreadyExists.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | отзыв rating=5 | OK |
| 3 | INV-required | id="" или subject="" | InvalidArgument |
| 4 | INV-oversize | subject >256 / text >4096 | InvalidArgument |
| 5 | INV-format | rating=0 или 6 | InvalidArgument |
| 6 | CONFLICT | id принадлежит другому | AlreadyExists |

## 17. DeleteReview

Вход: id. Идемпотентен.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | удалить свой отзыв | OK |
| 3 | INV-required | id="" | InvalidArgument |
| 4 | IDEMP | удалить несуществующий | OK (no-op) |

## 18. ListReviews

Вход: subject, cursor, limit. Правила: subject обязателен; возвращает avg+count.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | отзывы по subject | OK, avg+count |
| 3 | INV-required | subject="" | InvalidArgument |
| 4 | VALID | subject без отзывов | OK, 0 |
| 5 | PAGE-clamp | limit границы | OK, обрезано |

## 19. ListMyReviews

Вход: cursor, limit.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | свои отзывы | OK |
| 3 | VALID | пустой результат | OK, 0 |
| 4 | PAGE-clamp | limit границы | OK, обрезано |
