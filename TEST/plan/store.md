# store — план API-тестов (8 RPC)

Коды ошибок и лимиты подтверждены по реализации
(store/internal/service/{goods,favourites,service}.go), не угаданы.

## Подъём сервиса

- Тир данных: postgres (из env/db/store)
- Креды тестовой БД: из store/internal/service/store_test.go (подтвердить при написании теста)
- Команда: cd store && go test ./internal/service/ -run 'TestAPI' -count=1 -v
- Идентичность: GetGood и ListGoods — ПУБЛИЧНЫЕ (gateway снимает identity-заголовок,
  optionalCaller -> ""), без X-User-Id работают как анонимный зритель. Остальные 6 RPC
  owner-scoped: svckit.CallerID -> нет -> Unauthenticated.

## Подтверждённые по impl особенности контракта

- Лимиты (байты): maxTitleBytes=256, maxDescBytes=8192 (8*1024), maxLocationBytes=256,
  maxURLBytes=2048, maxImages=10. Превышение -> InvalidArgument.
- PutGood: id и title (trim) обязательны -> InvalidArgument; title>256 ИЛИ description>8192
  ИЛИ location>256 -> InvalidArgument; price_cents <= 0 -> InvalidArgument;
  image_urls > 10 -> InvalidArgument; любой url > 2048 -> InvalidArgument;
  чужой id (ErrWrongOwner) -> AlreadyExists.
- DeleteGood: id (trim) обязателен; DeleteOwn НЕ возвращает NotFound на отсутствие —
  идемпотентен (нет цели -> OK).
- GetGood (PUBLIC): id (trim) обязателен -> InvalidArgument; ErrNotFound -> NotFound.
- ListGoods (PUBLIC): query, category_id, condition, cursor, limit. Неизвестный condition
  (UNSPECIFIED) -> фильтр не применяется (не ошибка). Пагинация cursor-based.
- SaveGood / UnsaveGood: good_id (trim) обязателен -> InvalidArgument; SaveFav/UnsaveFav
  идемпотентны (повтор -> OK).
- ListSavedGoodIds: owner-scoped; cursor, limit.

## Легенда категорий

AUTH, VALID, INV-required, INV-oversize, INV-format, NOTFOUND, PERM, IDEMP, CONFLICT,
PAGE-clamp (определения — в TEST/README.md).

---

## 1. ListMyGoods

Вход: cursor, limit.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | свои листинги | OK, страница |
| 3 | VALID | пусто | OK, 0 |
| 4 | PAGE-clamp | limit границы | OK, обрезано |

## 2. PutGood

Вход: id, title, description?, price_cents, currency?, category_id?, location?, image_urls?, condition, lat?, lng?.
Правила: id+title обязательны; лимиты; price_cents>0; images≤10; чужой id -> AlreadyExists.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | создать листинг | OK |
| 3 | VALID | обновить свой (тот же id) | OK |
| 4 | INV-required | id="" или title="" | InvalidArgument |
| 5 | INV-oversize | title >256 / description >8192 / location >256 | InvalidArgument |
| 6 | INV-format | price_cents <= 0 | InvalidArgument |
| 7 | INV-format | image_urls > 10 | InvalidArgument |
| 8 | INV-oversize | url > 2048 | InvalidArgument |
| 9 | CONFLICT | id принадлежит другому | AlreadyExists |

## 3. DeleteGood

Вход: id. Идемпотентен.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | удалить свой листинг | OK |
| 3 | INV-required | id="" | InvalidArgument |
| 4 | IDEMP | удалить несуществующий | OK (no-op) |

## 4. GetGood (PUBLIC)

Вход: id. Правила: id обязателен; ErrNotFound -> NotFound.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | VALID | существующий листинг (аноним) | OK |
| 2 | INV-required | id="" | InvalidArgument |
| 3 | NOTFOUND | неизвестный id | NotFound |

## 5. ListGoods (PUBLIC)

Вход: query, category_id, condition, cursor, limit. Правила: UNSPECIFIED condition — без фильтра.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | VALID | базовый список (аноним) | OK, страница |
| 2 | VALID | пустой результат | OK, 0 |
| 3 | VALID | query + category + condition | OK, фильтр применён |
| 4 | PAGE-clamp | limit границы | OK, обрезано |

## 6. SaveGood

Вход: good_id. Идемпотентен.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | сохранить в избранное | OK |
| 3 | INV-required | good_id="" | InvalidArgument |
| 4 | IDEMP | повторное сохранение | OK (no-op) |

## 7. UnsaveGood

Вход: good_id. Идемпотентен.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | убрать из избранного | OK |
| 3 | INV-required | good_id="" | InvalidArgument |
| 4 | IDEMP | убрать без сохранения | OK (no-op) |

## 8. ListSavedGoodIds

Вход: cursor, limit.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | список id | OK |
| 3 | VALID | пусто | OK, 0 |
| 4 | PAGE-clamp | limit границы | OK, обрезано |
