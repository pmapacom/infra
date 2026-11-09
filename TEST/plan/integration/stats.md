# stats — интеграционный план (internal-only writes + reads за gateway)

Фаза 3. База — `TEST/plan/stats.md`. Интеграция проверяет границу экспозиции: writes
(Set/Inc) gateway НЕ роутит (иначе клиент подделает метрики), а соседи инкрементят
счётчики s2s; reads доступны за auth для дашбордов.

## Подъём в контуре

- Контейнеры: stats + redis, gateway, источники метрик (post, message и др.).

## Сценарии

### Q1. RPATH — gateway не отдаёт writes наружу
1. Прямой POST клиентом на stats.Set / stats.Inc через :8088 -> маршрут отсутствует
   (404/не проксируется): записи метрик только s2s внутри кластера.
2. Reads (Get/BatchGet/List) через gateway без токена -> 401 (за auth_request);
   с токеном -> OK.

### Q2. XSVC — соседи инкрементят счётчики, read отражает
1. post.LikePost -> post зовёт stats.Inc(метрика) s2s.
2. stats.Get(той же метрики) через внутренний путь -> value отражает инкремент
   (атомарный INCRBY на живом Redis).
3. message.SendMessage -> соответствующий счётчик вырос.

### Q3. VALID — семантика на реальном Redis
1. Inc без delta -> +1; Inc(delta=-2) -> уменьшение; Set -> last-write-wins.
2. Get отсутствующей метрики -> value=0, found=false (не ошибка).
3. BatchGet с отсутствующими ключами -> они вне map. List(prefix) -> только семейство.

### Q4. INV-oversize — границы имён
name > 256 байт -> InvalidArgument; BatchGet > 500 имён -> InvalidArgument;
List prefix > 256 -> InvalidArgument.
