# stats — план API-тестов (5 RPC, internal-only метрик-стор на Redis)

Коды ошибок, лимиты и семантика подтверждены по реализации
(stats/internal/service/stats.go) и контракту
(proto/.../statsconnect/stats.connect.go), не угаданы.

## Границы контракта (важно)

- **StatsService** (pmapa.api.stats, UNVERSIONED by design) — 5 RPC:
  Set, Inc, Get, BatchGet, List.
- **Exposure: writes INTERNAL-ONLY.** Set/Inc зовут только доверенные пиры кластера;
  gateway их НЕ роутит (иначе клиент подделает метрики). Reads (Get/BatchGet/List)
  дополнительно за gateway behind auth_request для дашбордов.
- **Caller в хендлере НЕ проверяется** (нет svckit.CallerID ни в одном методе):
  auth — забота gateway, а не сервиса. Поэтому на уровне API-матрицы **категории
  AUTH нет** (как в geo); запрос без X-User-Id для самого хендлера валиден.
- Backing store — **Redis** (store.Redis). Счётчики — атомарный INCRBY (Inc);
  Set — gauge/абсолют, last-write-wins. Имена метрик точечные, dot-separated.
- **NOTFOUND — не ошибка**: Get на отсутствующей метрике отдаёт value=0, found=false
  (записанный 0 отличим от отсутствия). BatchGet пропускает отсутствующие ключи из
  map. Поэтому NOTFOUND как error-категории нет — это VALID-поведение.

## Подъём сервиса

- Тир данных: **miniredis in-process** — внешняя инфра не нужна
  (подтверждено stats/internal/service/stats_test.go: miniredis.RunT + store.New).
- Фикстура: `mr := miniredis.RunT(t); db, _ := store.New("redis://"+mr.Addr()); New(db)`.
- Команда: cd stats && go test ./internal/service/ -run 'TestAPI' -count=1 -v
- Хелпер кода ошибки: `connect.CodeOf(err)` (как в существующем stats_test.go).

## Подтверждённые по impl особенности контракта

- **metricName**: TrimSpace -> пусто -> InvalidArgument ("name required");
  len(name) > maxNameBytes=256 (байты) -> InvalidArgument ("name too long").
- **Set**: валидирует имя; db.Set; пустой ответ; ошибка стора -> Internal.
  Перезапись — last-write-wins (gauge).
- **Inc**: валидирует имя; delta==0 трактуется как 1 ("count one event");
  отрицательная delta уменьшает; возвращает новое значение; ошибка -> Internal.
- **Get**: валидирует имя; возвращает value+found; отсутствие -> value=0, found=false
  (не ошибка); ошибка стора -> Internal.
- **BatchGet**: names обязателен (пусто -> InvalidArgument "names required");
  len > maxBatch=500 -> InvalidArgument ("too many names"); КАЖДОЕ имя проходит
  metricName (пустое/длинное в списке -> InvalidArgument); отсутствующие ключи
  отсутствуют в map; ошибка стора -> Internal.
- **List**: prefix (trim); len(prefix) > 256 -> InvalidArgument ("prefix too long");
  limit <= 0 -> defaultList=100; limit > maxList=1000 -> 1000; ошибка стора -> Internal.

## Легенда категорий

VALID, INV-required, INV-oversize, PAGE-clamp (определения — в TEST/README.md).
AUTH/NOTFOUND/PERM/IDEMP/CONFLICT/INV-format здесь неприменимы (см. выше):
auth — на gateway, NOTFOUND — валидный found=false, стор идемпотентен тривиально.

---

## 1. Set

Вход: name, value. Правила: name обязателен (trim) и <=256 байт; last-write-wins.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | VALID | Set("users.total", 42), затем Get | OK, Get -> value=42, found=true |
| 2 | VALID | повторный Set("users.total", 7) | OK, Get -> value=7 (перезапись, last-write-wins) |
| 3 | INV-required | name="  " (только пробелы) | InvalidArgument (name required) |
| 4 | INV-oversize | name из 257+ байт | InvalidArgument (name too long) |

## 2. Inc

Вход: name, delta. Правила: name обязателен; delta==0 -> 1; отрицательная уменьшает.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | VALID | Inc("messages.sent") без delta | OK, value=1 (дефолтная delta=1) |
| 2 | VALID | Inc(..., delta=4) поверх 1 | OK, value=5 (атомарный INCRBY) |
| 3 | VALID | Inc(..., delta=-2) поверх 5 | OK, value=3 (отрицательная уменьшает) |
| 4 | INV-required | name="  " | InvalidArgument (name required) |
| 5 | INV-oversize | name из 300 байт | InvalidArgument (name too long) |

## 3. Get

Вход: name. Правила: name обязателен; отсутствие -> found=false (не ошибка).

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | VALID | Get существующей метрики | OK, value=записанное, found=true |
| 2 | VALID | Get отсутствующей метрики | OK, value=0, found=false (0 отличим от отсутствия) |
| 3 | INV-required | name="  " | InvalidArgument (name required) |
| 4 | INV-oversize | name из 257+ байт | InvalidArgument (name too long) |

## 4. BatchGet

Вход: names[]. Правила: непустой; <=500; каждое имя валидно; отсутствующие — вне map.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | VALID | names=["a","b","missing"], заданы a,b | OK, map{a,b}, "missing" отсутствует в map |
| 2 | INV-required | names=[] (пусто) | InvalidArgument (names required) |
| 3 | INV-oversize | 501 имя | InvalidArgument (too many names) |
| 4 | INV-required | одно имя в списке пустое/длинное | InvalidArgument (per-name validation) |

## 5. List

Вход: prefix, limit. Правила: prefix <=256; limit clamp [1..1000], default 100.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | VALID | prefix="posts." при posts.*/users.* | OK, только семейство posts.* |
| 2 | VALID | пустой prefix | OK, перечислены все метрики |
| 3 | INV-oversize | prefix из 257+ байт | InvalidArgument (prefix too long) |
| 4 | PAGE-clamp | limit=0 | OK, применён defaultList=100 |
| 5 | PAGE-clamp | limit=5000 | OK, clamp до maxList=1000 |
