# geo — план API-тестов (5 RPC, публичный read-only словарь)

Коды ошибок, лимиты пагинации и поведение словаря подтверждены по реализации
(geo/internal/service/geo.go, geo/internal/service/errors.go) и контракту
(proto/.../geov1connect/geo.connect.go), не угаданы.

## Границы контракта (важно)

- **GeoService** (v1) — 5 RPC: ListCountries, GetCountry, ListCities, GetCity,
  ListRegions. Все — неаутентифицированный reference-lookup.
- **Exposure: PUBLIC.** Gateway роутит БЕЗ auth_request (здесь нет пользовательских
  данных). Значит caller НЕ проверяется: **категории AUTH нет**, запрос без X-User-Id
  — валиден. Это отличает geo от owner-scoped сервисов.
- Данные **immutable, in-memory, read-only**: нет БД, нет write-пути, нет per-user
  состояния. Поэтому **нет IDEMP, PERM, CONFLICT, INV-oversize/format** — только
  VALID, INV-required (для двух lookup-RPC), NOTFOUND и PAGE-clamp.
- Два статических датасета: countries (ISO 3166-1 alpha-2, 246 записей) и cities
  (GeoNames cities500, ~236k записей с population >= 500).

## Подъём сервиса

- Тир данных: нет БД — словарь грузится в память из geo/internal/dict на старте.
- Креды/фикстуры: из geo/internal/service/geo_test.go (подтвердить при написании
  теста; вероятно тестовый dict с усечённым набором записей).
- Команда: cd geo && go test ./internal/service/ -run 'TestAPI' -count=1 -v

## Подтверждённые по impl особенности контракта

- Пагинация **offset-based** (не cursor). window(offset, limit):
  - offset < 0 -> 0 (отрицательный трактуется как 0);
  - limit <= 0 -> defaultLimit = 60;
  - limit > maxLimit = 250 -> 250.
  Ответы List* отдают обрезанную страницу + полный `total` (число совпадений до
  пагинации), поэтому offset за пределами total -> пустая страница, но total полный.
- **ListCountries**: фильтры query (поиск по стране) и region; offset/limit.
  Пустой запрос -> весь список (обрезан до limit), total=246 (на полном датасете).
- **GetCountry**: iso2 (trim) обязателен -> InvalidArgument (errIso2Required);
  неизвестный код -> NotFound (errCountryNotFound). Поиск через Countries.ByISO.
- **ListCities**: фильтры query, country_iso2, min_population; offset/limit.
  toCity джойнит страну (name/flag/image) и подменяет image из cityPhotos при
  совпадении ключа "iso2:ascii-name-lowercased".
- **GetCity**: name (trim) обязателен -> InvalidArgument (errNameRequired);
  не найдено -> NotFound (errCityNotFound). Возвращает **самый населённый**
  из совпавших (Cities.Find); country_iso2 — опциональный дизамбигуатор.
- **ListRegions**: без входа; отдаёт макро-регионы словаря с country_count.

## Легенда категорий

VALID, INV-required, NOTFOUND, PAGE-clamp (определения — в TEST/README.md).
AUTH/PERM/IDEMP/CONFLICT/INV-oversize/INV-format здесь неприменимы (см. выше).

---

## 1. ListCountries

Вход: query, region, offset, limit. Обязательных полей нет; фильтры опциональны.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | VALID | без фильтров, limit по умолчанию | OK, <=60 стран, total=полное число (246 на полном датасете) |
| 2 | VALID | query="fra" | OK, France в выдаче, total=число совпадений |
| 3 | VALID | region="Europe" (валидный регион из ListRegions) | OK, только страны региона, total совпадает |
| 4 | VALID | query + region, пересечение пустое | OK, countries=[], total=0 |
| 5 | PAGE-clamp | limit=0 | OK, default 60 |
| 6 | PAGE-clamp | limit=1000 | OK, clamp до 250 |
| 7 | PAGE-clamp | offset<0 | OK, offset трактуется как 0 |
| 8 | PAGE-clamp | offset за пределами total | OK, countries=[], total по-прежнему полный |

## 2. GetCountry

Вход: iso2. Правила: iso2 (trim) обязателен; поиск по ByISO.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | VALID | iso2="FR" | OK, страна France с flag/region/centroid |
| 2 | INV-required | iso2="" или только пробелы | InvalidArgument (iso2 is required) |
| 3 | NOTFOUND | iso2="ZZ" (нет в ISO 3166-1) | NotFound (country not found) |

## 3. ListCities

Вход: query, country_iso2, min_population, offset, limit. Обязательных полей нет.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | VALID | без фильтров | OK, <=60 городов, total=полное число совпадений |
| 2 | VALID | query="tokyo" | OK, Tokyo в выдаче, country_name/flag заполнены джойном |
| 3 | VALID | country_iso2="JP" | OK, только города Японии |
| 4 | VALID | min_population=1000000 | OK, только города с population >= 1e6 |
| 5 | PAGE-clamp | limit=0 / limit=1000 / offset<0 | OK, default 60 / clamp 250 / offset 0 |

## 4. GetCity

Вход: name, country_iso2?. Правила: name (trim) обязателен; возвращает самый населённый.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | VALID | name="Tokyo" | OK, самый населённый матч, image из cityPhotos при совпадении ключа |
| 2 | VALID | name="Paris" + country_iso2="FR" | OK, дизамбигуация по стране |
| 3 | INV-required | name="" или только пробелы | InvalidArgument (name is required) |
| 4 | NOTFOUND | name="Xyzzy-nonexistent" | NotFound (city not found) |

## 5. ListRegions

Вход: —. Правила: без входа; отдаёт макро-регионы с country_count.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | VALID | пустой запрос | OK, список регионов, у каждого name и country_count>0 |
| 2 | VALID | сумма country_count по регионам = числу стран с регионом | OK, инвариант согласованности словаря |
