# post — интеграционный план (authorize по сети + fail-closed)

Фаза 3. База — `TEST/plan/post.md`. Самый ценный интеграционный сервис: `authorize()`
и `ListFeed` в фазе 2 ходят в ФЕЙК user'а. Здесь — реальный user по сети, включая
его падение. Именно эти error-path просели в юнит-покрытии.

## Подъём в контуре

- Контейнеры: post + postgres, user (CanView/Followees по сети), gateway, auth,
  media (картинки постов через ServeImage).
- Транспорт: Connect-клиент через :8088 как в `app/tool/e2e_forms.dart`.

## Сценарии

### P1. XSVC — authorize через реальный user.CanView
1. A (приватные правила через user.Block или CanView=false) и B.
2. B запрашивает post.GetPost чужого контента -> post зовёт user.CanView ПО СЕТИ.
   Запрещено -> **PermissionDenied**; разрешено -> OK; свой контент (author==caller)
   -> OK без обращения к user.

### P2. CHAOS — user недоступен -> fail-closed Unavailable (ключевой непокрытый путь)
1. B смотрит чужой пост A -> OK (user жив).
2. `docker compose stop user`.
3. B снова смотрит чужой пост A -> **Unavailable** (fail-closed: контент скрыт, НЕ
   Internal и НЕ PermissionDenied).
4. B смотрит СВОЙ пост -> OK (authorize не зовёт user для author==caller).
5. ListFeed(B) при недоступном user (Followees) -> **Unavailable**.
6. `docker compose start user` -> поведение восстановлено.

### P3. XSVC — ListFeed по реальному графу user
1. B фолловит A и C (через user). A, C публикуют посты.
2. post.ListFeed(B) -> посты A и C; после Unfollow(C) -> только A. Граф берётся у user.

### P4. FLOW — engagement lifecycle через gateway + stats
1. PutPost(P) -> LikePost(P) -> счётчик 1 -> повтор Like -> по-прежнему 1 (IDEMP-state).
2. AddComment -> ListComments содержит его.
3. (если подключён stats) like инкрементит метрику -> stats.Get отражает (см. stats.md).
4. DeletePost(P) -> GetPost -> NotFound; ListComments -> NotFound.

### P5. XSVC — image_url постов через media
1. media.UploadImage -> url `/media/{id}`.
2. PutPost с этим image_url -> GetPost возвращает его.
3. GET `/media/{id}` через gateway (public) -> 200, байты, nosniff.

### P6. FANOUT — PurgeUser (см. _fanout.md)
PurgeUser(A) -> posts/comments/reviews/likes/saves A нет; посты B целы (их счётчики
могут быть завышены — лечит stats reconcile, ожидаемо).
