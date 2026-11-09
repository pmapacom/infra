# media — интеграционный план (upload RPC + public serve + S3-тир)

Фаза 3. База — `TEST/plan/media.md`. Интеграция: публичный байт-эндпоинт `GET /media/{id}`
через gateway (без auth), реальный S3/minio-тир и потребление картинок соседями
(user avatar, post, store, stay).

## Подъём в контуре

- Контейнеры: media + postgres (inline) + minio/s3 (blob-тир), gateway, auth.
  publicBase для CDN-пути — из env/test/contour (подтвердить).

## Сценарии

### D1. FLOW — upload -> serve через реальный путь
1. UploadImage (owner, валидный PNG) через gateway -> id + url `/media/{id}`.
2. GET `/media/{id}` через gateway БЕЗ токена -> 200, Content-Type=сниффенный,
   Cache-Control immutable, X-Content-Type-Options: nosniff, тело=байты.
3. HEAD -> 200, заголовки есть, тело пусто. POST на этот путь -> 405.

### D2. VALID — анти-stored-XSS на живом сниффе
content_type=image/png при реальных JPEG-байтах -> OK, но serve отдаёт image/jpeg
(хранится сниффенный тип). content_type вне allowedTypes -> InvalidArgument до сниффа.

### D3. RPATH — owner-граница
UploadImage/DeleteImage без токена -> 401 на gateway. DeleteImage чужого/несуществующего
-> OK (idemp no-op). После DeleteImage своего -> GET `/media/{id}` -> 404.

### D4. S3-тир — CDN-редирект
UploadImage на S3-тире с publicBase -> url=CDN; GET через gateway -> 302 на CDN-URL,
Cache-Control immutable. publicBase="" и blob==nil -> 503. blob.ErrNotFound -> 404.

### D5. XSVC — картинка как avatar/пост/товар
Загруженный id проставить в user.UpdateMyProfile(avatar_url), post.PutPost(image_url),
store.PutGood(image_urls) -> соответствующий Get возвращает ссылку, serve отдаёт байты.
(Соответствует зелёному `app/tool/e2e_media.dart`.)

### D6. FANOUT — PurgeUser удаляет строки и блобы (см. _fanout.md)
PurgeUser(A) -> строки media A нет; для S3 Delete блоба вызван на каждый s3ID
(best-effort, ошибка блоба НЕ валит RPC); media B целы.
