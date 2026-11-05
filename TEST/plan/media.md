# media — план API-тестов (2 RPC + публичный байт-эндпоинт + s2s PurgeUser)

Коды ошибок и лимиты подтверждены по реализации
(media/internal/service/media.go) и контракту
(proto/.../mediav1connect/media.connect.go), не угаданы.

## Границы контракта (важно)

- **MediaService** (v1, за gateway, owner-scoped) — 2 RPC: UploadImage, DeleteImage.
  Оба требуют caller: svckit.CallerID -> нет X-User-Id -> Unauthenticated.
- **ServeImage** (`GET /media/{id}`) — публичный байт-эндпоинт, НЕ Connect-RPC и НЕ за
  auth (gateway роутит без auth_request, id — неугадываемый 128-битный токен).
  Это HTTP-поверхность, а не RPC: в coverage.csv как media-RPC не идёт; матрица
  приведена ниже отдельным блоком.
- **PurgeUser** (из purge-proto) в число 2 RPC не входит: s2s-очистка, self-scoped,
  идемпотентна; тестируется общей PurgeUser-гарнитурой.
- Два тира хранения за одним контрактом: inline в Postgres (blob==nil) и S3/CDN
  (blob!=nil, опционально publicBase). API идентичен; матрица RPC от тира не зависит,
  различия тиров проверяются в media_s3_test.go / media_cdn_test.go и в ServeImage.

## Подъём сервиса

- Тир данных: postgres (inline) ИЛИ s3/minio (blob) — из env/db/media
- Креды тестовой БД/бакета: из media/internal/service/{media_test,media_s3_test,media_cdn_test}.go
  (подтвердить при написании теста)
- Команда: cd media && go test ./internal/service/ -run 'TestAPI' -count=1 -v

## Подтверждённые по impl особенности контракта

- maxImageBytes = 5 MiB (5*1024*1024). Больше -> InvalidArgument ("image too large").
- allowedTypes = {image/jpeg, image/png, image/webp, image/gif}.
- UploadImage валидирует В ПОРЯДКЕ: data непустой -> размер <= 5MiB ->
  content_type (lower+trim) в allowedTypes -> СНИФФ (http.DetectContentType) тоже в
  allowedTypes. Сервис доверяет байтам, а не метке: хранит и отдаёт СНИФФЕННЫЙ тип.
  Значит content_type=image/png при реальных JPEG-байтах -> OK, но сохранён как jpeg
  (анти-stored-XSS). Метка не в allowedTypes -> InvalidArgument ДО сниффа.
  Байты не являются валидным изображением (снифф вне allowedTypes) -> InvalidArgument.
- UploadImage возвращает id и url. url = `/media/{id}` для inline-строк; для S3+publicBase
  — CDN-URL (publicBase + keyPrefix + id).
- DeleteImage: id (trim) обязателен -> InvalidArgument; DeleteOwn идемпотентен —
  удаление чужого/несуществующего НЕ возвращает NotFound (тихий no-op -> OK).
- ServeImage: только GET/HEAD (иначе 405); пустой id или id со слэшем -> 404;
  ErrNotFound -> 404; inline -> отдаёт байты с Content-Type, Cache-Control immutable,
  X-Content-Type-Options: nosniff; S3+publicBase -> 302 на CDN; S3 без publicBase и
  blob==nil -> 503; blob.ErrNotFound -> 404, прочая ошибка blob -> 502.

## Легенда категорий

AUTH, VALID, INV-required, INV-oversize, INV-format, NOTFOUND, PERM, IDEMP, CONFLICT,
PAGE-clamp (определения — в TEST/README.md).

---

## 1. UploadImage

Вход: data (bytes), content_type. Правила: caller обязателен; data непустой; <=5MiB;
content_type в allowedTypes; сниффенный тип в allowedTypes (хранится сниффенный).

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | валидный jpeg/png + корректный content_type | OK, id и url непустые |
| 3 | VALID | content_type=image/png, но байты — реальный JPEG | OK, сохранён как image/jpeg (снифф важнее метки) |
| 4 | INV-required | data пустой (len==0) | InvalidArgument |
| 5 | INV-oversize | data > 5 MiB | InvalidArgument |
| 6 | INV-format | content_type вне allowedTypes (напр. application/pdf) | InvalidArgument |
| 7 | INV-format | content_type разрешён, но байты не изображение (снифф вне allowedTypes) | InvalidArgument |

## 2. DeleteImage

Вход: id. Правила: caller обязателен; id (trim) обязателен; DeleteOwn идемпотентен.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | удалить свой загруженный image | OK |
| 3 | INV-required | id="" или только пробелы | InvalidArgument |
| 4 | IDEMP | удалить чужой/несуществующий/повторно | OK (no-op, НЕ NotFound) |

---

## Публичный байт-эндпоинт ServeImage (`GET /media/{id}`, не RPC)

HTTP-поверхность; в coverage.csv не идёт. Проверяется HTTP-клиентом, не Connect.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | VALID | GET существующего inline-id | 200, Content-Type=сниффенный, Cache-Control immutable, X-Content-Type-Options: nosniff, тело=байты |
| 2 | VALID | HEAD существующего id | 200, заголовки есть, тело пустое |
| 3 | INV-format | метод POST/PUT | 405 Method Not Allowed |
| 4 | INV-required | пустой id или id со слэшем | 404 |
| 5 | NOTFOUND | неизвестный id (ErrNotFound) | 404 |
| 6 | VALID | S3-строка + publicBase | 302 Found на CDN-URL, Cache-Control immutable |
| 7 | FAIL | S3-строка, publicBase="" и blob==nil | 503 Service Unavailable |
| 8 | NOTFOUND | S3-строка, blob.ErrNotFound | 404 |
| 9 | FAIL | S3-строка, прочая ошибка blob | 502 Bad Gateway |

## s2s PurgeUser (общая гарнитура)

Self-scoped по верифицированному caller; auth зовёт s2s с X-User-Id удаляемого юзера.
Удаляет строки и (для S3) блобы best-effort; идемпотентна.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | VALID | есть загруженные media | OK, строки удалены, S3-блобы удалены best-effort |
| 2 | IDEMP | повтор / нет данных / несуществующий юзер | OK (no-op) |
