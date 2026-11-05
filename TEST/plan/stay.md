# stay — план API-тестов (13 RPC)

Коды ошибок и лимиты подтверждены по реализации
(stay/internal/service/{stays,bookings,vocab}.go), не угаданы.

## Подъём сервиса

- Тир данных: postgres (из env/db/stay)
- Креды тестовой БД: из stay/internal/service/{stays,bookings}_test.go (подтвердить при написании теста)
- Команда: cd stay && go test ./internal/service/ -run 'TestAPI' -count=1 -v
- Идентичность: ListStays и GetStay — ПУБЛИЧНЫЕ (gateway снимает identity-заголовок,
  optionalCaller -> ""), без X-User-Id работают как анонимный зритель. Остальные 11 RPC
  owner-scoped: svckit.CallerID -> нет -> Unauthenticated.

## Подтверждённые по impl особенности контракта

- Лимиты: maxTitleBytes=200, maxDescBytes=4000, maxImages=12, maxListBytes=40
  (длина списков vocab). Превышение -> InvalidArgument.
- Закрытые словари (vocab.go): mode(rent,buy), property_type, place_type, amenities,
  accessibility, security, house_rules, check_in, booking, cancellation, payments,
  host_kind, completion, finish, foreign_purchase, ownership, price_basis, sort.
  На ФИЛЬТРЕ неизвестное значение просто игнорируется (clean), на ЗАПИСИ -> InvalidArgument (allKnown).
- ListStays: проверяет mode, price_basis, sort -> неизвестное -> InvalidArgument.
  Битый cursor -> offset 0 (НЕ ошибка). Пагинация offset-based.
- GetStay: id обязателен -> InvalidArgument; ErrNotFound -> NotFound.
- PutStay: stay обязателен; validated(): id и title обязательны; title>200 или
  description>4000 -> InvalidArgument; mode ∈ {rent,buy}; price>0; images≤12;
  скалярные и списочные словари; available_from/to — ISO; to раньше from -> InvalidArgument.
  Чужой id (ErrWrongOwner) -> AlreadyExists. Server-поля (owner, verified, rating) из запроса НЕ берутся.
- DeleteStay / CancelBooking / SaveStay / UnsaveStay: id/stay_id обязателен;
  операции идемпотентны (нет цели -> OK, не NotFound).
- CreateBooking: from_date/to_date обязательны и ISO -> иначе InvalidArgument;
  stay не найден -> NotFound; своё листинг -> InvalidArgument; bookingProblem
  (продажа не аренда, nights<1, даты в прошлом, < minNights, вне окна доступности,
  adults<1, превышена вместимость, pets/infants не разрешены) -> InvalidArgument;
  даты заняты (ErrDatesTaken) -> AlreadyExists. Цена считается сервером из условий листинга.
- ListStayBookings: хостерская сторона; владение зашито в JOIN, чужой листинг -> пусто (не ошибка).
- RespondToBooking: id обязателен; не живая заявка / чужой листинг -> NotFound
  (accept -> confirmed, иначе declined).

## Легенда категорий

AUTH, VALID, INV-required, INV-oversize, INV-format, NOTFOUND, PERM, IDEMP, CONFLICT,
PAGE-clamp (определения — в TEST/README.md).

---

## 1. ListStays (PUBLIC)

Вход: фильтры, mode, price_basis, sort, cursor, limit. Правила: словари; битый cursor -> 0.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | VALID | базовый список | OK, страница |
| 2 | VALID | пустой результат | OK, 0 |
| 3 | INV-format | unknown mode | InvalidArgument |
| 4 | INV-format | unknown price_basis | InvalidArgument |
| 5 | INV-format | unknown sort | InvalidArgument |
| 6 | PAGE-clamp | битый cursor | OK, с начала |

## 2. GetStay (PUBLIC)

Вход: id. Правила: id обязателен; ErrNotFound -> NotFound.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | VALID | существующий листинг | OK |
| 2 | INV-required | id="" | InvalidArgument |
| 3 | NOTFOUND | неизвестный id | NotFound |

## 3. ListMyStays

Вход: cursor, limit.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | свои листинги | OK |
| 3 | VALID | пусто | OK, 0 |
| 4 | PAGE-clamp | limit границы | OK, обрезано |

## 4. PutStay

Вход: stay{id, mode, title, price, ...}. Правила: лимиты, словари, даты; чужой id -> AlreadyExists.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | создать листинг | OK |
| 3 | VALID | обновить свой (тот же id) | OK |
| 4 | INV-required | stay=nil / id="" / title="" | InvalidArgument |
| 5 | INV-oversize | title >200 / description >4000 | InvalidArgument |
| 6 | INV-format | mode не rent/buy | InvalidArgument |
| 7 | INV-format | price <= 0 | InvalidArgument |
| 8 | INV-format | images > 12 | InvalidArgument |
| 9 | INV-format | unknown property_type / amenity | InvalidArgument |
| 10 | INV-format | available_to раньше available_from | InvalidArgument |
| 11 | CONFLICT | id принадлежит другому | AlreadyExists |

## 5. DeleteStay

Вход: id. Идемпотентен.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | удалить свой листинг | OK |
| 3 | INV-required | id="" | InvalidArgument |
| 4 | IDEMP | удалить несуществующий | OK (no-op) |

## 6. SaveStay

Вход: stay_id. Идемпотентен.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | сохранить в избранное | OK |
| 3 | INV-required | stay_id="" | InvalidArgument |
| 4 | IDEMP | повторное сохранение | OK (no-op) |

## 7. UnsaveStay

Вход: stay_id. Идемпотентен.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | убрать из избранного | OK |
| 3 | INV-required | stay_id="" | InvalidArgument |
| 4 | IDEMP | убрать без сохранения | OK (no-op) |

## 8. ListSavedStayIds

Вход: cursor, limit.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | список id | OK |
| 3 | VALID | пусто | OK, 0 |
| 4 | PAGE-clamp | limit границы | OK, обрезано |

## 9. CreateBooking

Вход: stay_id, from_date, to_date, adults, children, infants, pets.
Правила: ISO-даты; stay NotFound; не своё; bookingProblem; даты заняты -> AlreadyExists.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | валидная аренда | OK, расчёт по условиям |
| 3 | INV-format | from_date/to_date не ISO | InvalidArgument |
| 4 | NOTFOUND | неизвестный stay | NotFound |
| 5 | INV-format | бронь своего листинга | InvalidArgument |
| 6 | INV-format | листинг на продажу (не rent) | InvalidArgument |
| 7 | INV-format | даты в прошлом / nights<1 | InvalidArgument |
| 8 | INV-format | меньше min_nights / adults<1 | InvalidArgument |
| 9 | CONFLICT | даты заняты | AlreadyExists |

## 10. ListMyBookings

Вход: cursor, limit.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | свои бронирования | OK |
| 3 | VALID | пусто | OK, 0 |
| 4 | PAGE-clamp | limit границы | OK, обрезано |

## 11. CancelBooking

Вход: id. Идемпотентен.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | отменить своё | OK |
| 3 | INV-required | id="" | InvalidArgument |
| 4 | IDEMP | отменить несуществующее | OK (no-op) |

## 12. ListStayBookings (хост)

Вход: stay_id?, cursor, limit. Правила: владение в JOIN; чужой листинг -> пусто.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | заявки на мои листинги | OK |
| 3 | VALID | чужой листинг | OK, 0 (не видно) |
| 4 | PAGE-clamp | limit границы | OK, обрезано |

## 13. RespondToBooking (хост)

Вход: id, accept. Правила: id обязателен; не живая заявка / чужой листинг -> NotFound.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | accept=true | OK, confirmed |
| 3 | VALID | accept=false | OK, declined |
| 4 | INV-required | id="" | InvalidArgument |
| 5 | NOTFOUND | не живая / чужая заявка | NotFound |
