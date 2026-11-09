# user — интеграционный план (граф подписок виден post'у по сети)

Фаза 3. База — `TEST/plan/user.md`. Ключ интеграции: user — источник follow-графа и
gate приватности для post. В фазе 2 post эти вызовы фейкает; здесь они реальные.

## Подъём в контуре

- Контейнеры: user + postgres, gateway, auth (identity), post (потребитель графа).
- Транспорт: `app/tool/e2e_abuse.dart` уже бьёт по self-follow/block/cross-user;
  расширять им.

## Сценарии

### U1. XSVC — follow-граф питает post.ListFeed
1. Два юзера A и B (разные токены через gateway).
2. A публикует пост (post.PutPost).
3. B делает Follow(A) в user.
4. post.ListFeed(B) -> видит пост A. Проверяет, что post берёт `Followees` у user ПО
   СЕТИ (не фейк), и что немедленный Follow (is_private dormant) реально работает.

### U2. XSVC — Block меняет видимость в post (fail-closed проверяется отдельно в CHAOS)
1. A публикует пост; B его видит (post.GetPost через authorize -> user.CanView=true).
2. A делает BlockUser(B).
3. post.GetPost(пост A) от B -> **PermissionDenied** (user.CanView=false по сети).
4. user.GetProfile(A) от B -> PermissionDenied (не NotFound — fail-closed на блоке).

### U3. RPATH — admin-поверхность за gateway
1. ReportContent от B на пост A -> OK.
2. ListReports не-админом -> PermissionDenied; админом (USER_ADMIN_IDS в env контура)
   -> OK, репорт виден.
3. ResolveReport админом -> OK; неизвестный id -> NotFound.

### U4. FANOUT — PurgeUser снимает рёбра в обе стороны (см. _fanout.md)
1. A<->B: follow, block, report.
2. PurgeUser(A) -> follows/blocks/requests с участием A в ОБЕ стороны удалены,
   reports поданные A удалены; данные B целы.

### U5. RACE — конкурентный Follow/Unfollow на реальной БД
1. N параллельных Follow(A) от B -> ровно одно ребро графа (без дубля), счётчик консистентен.
