# Сквозное покрытие (deep coverage) — сценарии поверх per-RPC матриц

Per-RPC планы (message/user/auth/post/stay/store/travel/...) дают breadth:
один вызов, одна проверка. Этот файл — depth: переходы состояний, инварианты,
изоляция и гонки, которые single-RPC кейсы структурно не ловят.
Все сценарии опираются на поведение, подтверждённое по impl в per-RPC планах.

## Легенда

FLOW — многошаговый сценарий с проверкой состояния между шагами.
ISO  — изоляция владельца (caller B против ресурсов caller A).
PAGE-inv — инварианты пагинации (стабильность курсора, без дублей/дыр).
IDEMP-state — идемпотентность С проверкой неизменности состояния.
BOUND — точная граница лимита (N байт OK, N+1 InvalidArgument).
MBYTE — байтовый лимит на multibyte-строке (кириллица/эмодзи у границы).
FAILCLOSED — поведение при недоступной внешней зависимости.
RACE — конкурентные запросы (если тестовый тир допускает).

---

## 1. FLOW — переходы состояний

### 1.1 post: engagement lifecycle
1. PutPost (свой, публичный) -> OK, id=P.
2. LikePost(P) -> OK; GetMyStats / GetPost: likes=1.
3. AddComment(P) -> OK, id=C; ListComments(P): есть C.
4. LikePost(P) повторно -> OK, likes по-прежнему 1 (IDEMP-state).
5. DeletePost(P) -> OK.
6. GetPost(P) -> NotFound; ListComments(P) -> NotFound (AuthorOf); лайк-ребро недостижимо.

### 1.2 stay: booking lifecycle + конфликт дат
1. PutStay (свой, rent, доступные даты) -> OK, id=S.
2. CreateBooking(S, [d1,d2]) гостем G -> OK, booking=B (pending).
3. CreateBooking(S, [d1,d2]) другим гостем на те же даты -> AlreadyExists (ErrDatesTaken).
4. RespondToBooking(B, accept=true) владельцем -> OK, confirmed.
5. RespondToBooking(B, ...) повторно -> NotFound (заявка не живая).
6. CancelBooking(B) гостем -> OK; те же даты снова свободны: CreateBooking(S,[d1,d2]) -> OK.

### 1.3 user: приватный follow + видимость
1. UpdateMyProfile(A, private) -> OK.
2. Follow(A) от B -> OK, но это request (не подтверждён); ListFollowers(A): B нет.
3. ListFollowRequests(A): есть B.
4. ApproveFollow(B) -> OK; ListFollowers(A): B есть; ListFeed(B) видит посты A.
5. BlockUser(B) от A -> OK; B пропал из подписчиков; ListFeed(B) больше не видит A.

### 1.4 travel: sharing + права коллаборатора
1. PutTrip(id=T) владельцем O -> OK.
2. PutTrip(T) от U без прав -> PermissionDenied.
3. ShareTrip(T) от O -> OK, share_code=SC.
4. JoinTrip(SC) от U -> OK, trip виден.
5. PutTrip(T) от U -> OK (коллаборатор получил право записи).
6. RemoveTripMember(T, U) от O -> OK; PutTrip(T) от U снова -> PermissionDenied.

---

## 2. ISO — изоляция владельца

Для каждого owner-scoped RPC по два caller'а A и B (разные X-User-Id):

| Сервис | Ресурс A | Действие B | Ожидание |
|--------|----------|-----------|----------|
| post | пост A (id=P) | PutPost(id=P) | AlreadyExists (ErrWrongOwner) |
| post | комментарий A | DeleteComment(id) | PermissionDenied |
| stay | листинг A (id=S) | PutStay(id=S) | AlreadyExists |
| stay | booking A | CancelBooking(id) | OK no-op (чужого не отменяет; проверить, что A-booking жив) |
| store | товар A (id=G) | PutGood(id=G) | AlreadyExists |
| travel | trip A (id=T) | PutTrip(id=T) | PermissionDenied |
| user | — | ApproveFollow(чужой request) | NotFound |

Проверка: после действия B ресурс A не изменён (повторным Get/List владельцем A).

---

## 3. PAGE-inv — инварианты пагинации

Для каждого листинга (ListMyPosts, ListUserPosts, ListFeed, ListComments,
ListStays, ListMyStays, ListMyBookings, ListGoods, ListMyGoods, ListMyTrips,
ListVisited, ListFollowers, ListFollowing, SearchProfiles, ...):

1. Насидить N > limit элементов. Пройти все страницы по курсору до пустого курсора.
   Инвариант: объединение страниц = ровно N уникальных id, без дублей и без пропусков,
   порядок между страницами монотонный.
2. Удалить элемент с уже отданной страницы -> следующая страница не сдвигается
   некорректно (нет дубля/дыры за пределами удалённого).
3. stay (offset-пагинация): битый/непарсящийся cursor -> выдача с начала, НЕ ошибка.
4. Пустой результат -> пустой список и пустой курсор, не ошибка.

---

## 4. IDEMP-state — идемпотентность с проверкой состояния

| RPC | Повтор | Инвариант состояния |
|-----|--------|---------------------|
| LikePost / SavePost | дважды | ровно одно ребро, счётчик=1 |
| UnlikePost / UnsavePost | без ребра | счётчик не уходит < 0, OK |
| SaveGood / UnsaveGood | дважды | одна/ноль записей в избранном |
| SaveStay / UnsaveStay | дважды | одна/ноль записей |
| DeletePost/Good/Stay/Trip/Review/Comment | дважды | второй раз OK, цели по-прежнему нет |
| CancelBooking | без заявки | OK, ничего не создаёт |
| Follow/Unfollow | дважды | без дубля ребра графа |
| PutVisited (kind,key) | дважды | upsert, одна запись |

---

## 5. BOUND + MBYTE — границы лимитов

Лимиты байтовые. Для каждого строкового поля с лимитом N:

- строка ровно N байт -> OK;
- строка N+1 байт -> InvalidArgument;
- строка из multibyte-символов (кириллица = 2 байта, эмодзи = 4) длиной,
  где rune-count < N, но byte-count = N+1 -> InvalidArgument (проверяем, что лимит по БАЙТАМ).

Поля (из per-RPC планов):
- post: maxPostBytes=10240, maxCommentBytes=2048, maxReviewBytes=4096,
  maxSubjectBytes=256, maxPlaceBytes=256, maxURLBytes=2048.
- stay: maxTitleBytes=200, maxDescBytes=4000, maxListBytes=40, maxImages=12.
- store: maxTitleBytes=256, maxDescBytes=8192, maxLocationBytes=256,
  maxURLBytes=2048, maxImages=10.
- travel: maxDocumentBytes=262144, maxKindBytes=64, maxKeyBytes=256,
  maxVisitedDocBytes=16384.
- image/url массивы: ровно max -> OK; max+1 -> InvalidArgument.
- trim-поля (id, title, good_id, kind, key): строка только из пробелов ->
  трактуется как пустая -> InvalidArgument.

---

## 6. FAILCLOSED — внешние зависимости недоступны

Подменяется фейком user-сервиса (как в post_test.go):

- post.authorize при user.CanView -> ошибка транспорта: чужой приватный/любой чужой
  контент -> Unavailable (fail-closed, не отдаём), свой контент (author==caller) виден.
- post.ListFeed при недоступных Followees -> Unavailable.
- Проверка, что это именно Unavailable, а не Internal/PermissionDenied.

---

## 7. RACE — гонки (при поддержке тестового тира)

- stay: два параллельных CreateBooking на пересекающиеся даты -> ровно один OK,
  второй AlreadyExists (нет двойного бронирования).
- stay: два PutStay с одинаковым новым id от разных владельцев -> один OK,
  второй AlreadyExists.
- user: конкурентные Follow/Unfollow -> граф консистентен, без дубля ребра.
- post: конкурентные LikePost -> счётчик = числу уникальных лайкнувших.

---

## 8. PurgeUser — сквозной каскад (s2s, self-scoped, идемпотентный)

1. Насидить данные юзера U во всех сервисах (пост, листинг stay, товар, trip, профиль,
   подписки, диалоги message).
2. PurgeUser(U) в каждом сервисе -> OK.
3. Проверить, что данные U удалены/обезличены по контракту каждого сервиса
   (посты/листинги/товары/trips нет; подписки сняты; диалоги по правилам message).
4. PurgeUser(U) повторно -> OK (идемпотентно, no-op).
5. PurgeUser для несуществующего юзера -> OK.
