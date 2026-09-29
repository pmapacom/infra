# PMapa — ревью слоя handlers (2026-09-25)

Зафиксировано для продолжения после перезагрузки. Правки **ещё не применены** —
в репозитории только этот документ. Состояние: диффы P1 подготовлены, ждут
применения и прогона `go build ./... && go test ./message/...`.

Охват: `message/internal/service`, `media/internal/service`,
`notification/internal/service`, `geo/internal/service`, `stats/internal/service`,
`user/internal/service/{blocks,social}.go`, `env/gateway/nginx.conf`.

## Общая оценка

Слой крепкий:

- `svckit.CallerID` в начале каждого RPC — нет ни одного handler'а, читающего
  идентичность иначе;
- единый маппер `notFound()` не выдаёт оракул владения (неизвестный / чужой /
  удалённый id → одинаковый `NotFound`);
- `media` сниффит реальный тип (`http.DetectContentType`) и сохраняет **его**, а
  не клиентский ярлык; байты отдаются с `X-Content-Type-Options: nosniff` —
  stored-XSS с API-origin закрыт;
- `pmapa.api.stats` и `pmapa.api.notify` **не** проброшены в gateway (проверено
  в `env/gateway/nginx.conf`: локаций нет, снаружи 404), поэтому отсутствие
  проверки вызывающего в этих сервисах допустимо;
- `notification` routes только 6 end-user RPC, остальное s2s.

Всё найденное ниже — не отсутствующие механизмы, а места, где **существующая**
проверка не применена.

## Находки

### 1. `image_url` не валидируется (P1)

`message/internal/service/message.go:137-150` — проверяется только длина:

~~~go
imageURL := strings.TrimSpace(m.GetImageUrl())
...
if len(imageURL) > maxURLBytes {
    return nil, svckit.InvalidArg("image_url too long")
}
~~~

Значение хранится и раздаётся всем участникам, рендерится их клиентами.
`javascript:`-URI доезжает до Next.js-фронта как `src`; `https://attacker/x.gif`
превращает клиент каждого получателя в маячок прочтения для третьей стороны.
Форма, которую реально выдаёт media, узкая и известная: `"/media/" + id`
(`media/internal/service/media.go:118-121`).

### 2. Гейт блокировок применяется только при создании DM (P1)

`CreateConversation` зовёт `s.gate.CanView` для `kind == "direct"`
(message.go:79-88), `SendMessage` — нет. Блокировка не останавливает того, с кем
диалог уже открыт, а это нормальный случай: заблокировать хотят как раз того,
с кем уже переписывались.

Со стороны user-сервиса механизм есть и работает: `IsBlockedEither` +
`errBlocked` → `PermissionDenied` (`user/internal/service/social.go:26-30`,
`blocks.go:27-28`).

### 3. `DeleteMessage` и `LeaveConversation` обходят маппер ошибок (P1)

`rich.go:100` и `message.go:352` оборачивают ошибку стора в
`svckit.InternalErr`, хотя стор возвращает `ErrNotFound` / `ErrNotMember`
(`message/internal/store/postgres.go:30-34`). Удаление чужого сообщения даёт
500 вместо 404: шумные алерты + расхождение с остальными RPC пакета.

### 4. Rate limiter прикрывает один RPC (P1)

`newLimiter(10, 30)` используется только в `SendMessage`. Без метра:
`SearchMessages` (серверный скан текста по разговору), `React`/`Unreact`,
`EditMessage`, `AddMembers`, `CreateConversation`. Поиск — самый дешёвый способ
заставить БД работать, и он ходит через gateway как всё остальное.

### 5. `validEmoji` принимает 32 байта произвольного текста (P2)

`rich.go:19-21`: только непустое, ≤32 байт, валидный UTF-8. «Реакция» —
пользовательский контент в UI каждого участника; так она может нести короткое
сообщение в обход лимитов и модерации тела.

### 6. `Notify` fail-open по настройкам получателей (P2)

`notification/internal/service/notification.go:112-115`: при ошибке
`EnabledRecipients` fallback = `m.GetUserIds()`, то есть все, включая
отключивших тип. Комментарий обосновывает это тем, что события не должны
теряться, но сбой Postgres тогда отправляет превью приватных сообщений на
устройства, которые от этого отписались. Событие восстановимо, нарушенное
обещание «я отключил уведомления» — нет.

### 7. Само-DM и дубликаты участников не отсекаются (P2)

Для `direct` проверяется `len(others) == 1`, но не `others[0] != caller`;
групповой список не дедуплицируется до проверки `maxMembers`.

### 8. `Subscribe`: таймеры и отсутствие лимита стримов (P2)

`message.go:298` — `case <-time.After(30 * time.Second)` внутри цикла: каждый
сигнал Hub бросает 30-секундный таймер, живущий в куче до срабатывания. На
активном разговоре это тысячи живых таймеров на стрим. Плюс нет лимита
одновременных стримов на пользователя, а gateway даёт каждому read timeout 1 час
(`nginx.conf:131-140`, буферизация off + 1h из `proxy_common`).

## Поддерживаемость

- `notFound()` лежит в `rich.go`, хотя это контракт ошибок всего пакета —
  ему место рядом с типом или в отдельном `errors.go`.
- Лимиты, определяющие контракт сервиса, размазаны по четырём файлам:
  `maxTitleBytes` в `governance.go`, `maxMessageBytes` / `maxURLBytes` /
  `maxMembers` — в других.
- `geo/internal/service/geo.go:24-47` — 22 Unsplash-URL зашиты в пакет
  handler'ов. Это данные в файле кода; место — в словаре, который читает
  остальной пакет. Уже висит как `AUDIT.md §country-photos-debt`.

## Что НЕ проверено (проверить после перезагрузки)

- Порты в `docker-compose.yml`: не подтверждено, что `notification` и `stats`
  **не опубликованы**. Оба не проверяют вызывающего, инвариант несущий (для
  находки 6 и для write-пути stats: `Set`/`Inc` без auth → подделка метрик).
  В файле 8 блоков `ports:` — надо сверить, какие сервисы их имеют.
- `notification/internal/templates` и SMTP-отправитель: может ли переменная
  шаблона вставить перевод строки в `Subject` (header injection). `SendEmail`
  валидирует адрес через `mail.ParseAddress`, но не содержимое `vars`.
- Тесты и сборка не запускались.

## Приоритеты

| | Находки |
|---|---|
| **P0** | нет |
| **P1** | 1 (валидация `image_url`), 2 (гейт блокировок на send), 3 (маппинг ошибок), 4 (лимит на `SearchMessages`) |
| **P2** | 5, 6, 7, 8 + пункты по поддерживаемости |

## Подготовленные диффы (P1)

### 1 + 2 — `message/internal/service/message.go`

В импорты добавляется `net/url` (и `errors`, если ещё не импортирован).

~~~diff
--- a/message/internal/service/message.go
+++ b/message/internal/service/message.go
@@
+// validImageURL accepts only what the media service issues (`/media/{id}`) or
+// an absolute https URL. Anything else — javascript:, data:, a third-party
+// tracker — is refused: this value is rendered by every other member's client.
+func validImageURL(u string) bool {
+	if strings.HasPrefix(u, "/media/") {
+		id := strings.TrimPrefix(u, "/media/")
+		return id != "" && !strings.ContainsAny(id, "/?#")
+	}
+	parsed, err := url.Parse(u)
+	return err == nil && parsed.Scheme == "https" && parsed.Host != ""
+}
@@
 	if len(imageURL) > maxURLBytes {
 		return nil, svckit.InvalidArg("image_url too long")
 	}
+	if imageURL != "" && !validImageURL(imageURL) {
+		return nil, svckit.InvalidArg("image_url must be a /media/ id or an https URL")
+	}
+	// The block gate is re-checked on every send, not just at creation: a DM
+	// opened before the block would otherwise keep delivering.
+	if s.gate != nil {
+		peers, perr := s.db.OtherMemberIDs(ctx, conv, caller)
+		if perr == nil && len(peers) == 1 {
+			ok, gerr := s.gate.CanView(ctx, caller, peers[0])
+			if gerr != nil {
+				return nil, svckit.InternalErr(gerr)
+			}
+			if !ok {
+				return nil, connect.NewError(connect.CodePermissionDenied,
+					errors.New("can't message this user"))
+			}
+		}
+	}
 	msg, err := s.db.Send(ctx, caller, conv, id, body, imageURL, replyTo)
~~~

**Оговорка, решать при применении:** `OtherMemberIDs`
(`message/internal/store/conversations.go:292-298`) фильтрует `NOT muted` — это
набор получателей уведомлений, а не участников. Значит замьютивший собеседник в
DM проверку проскочит. Наглухо — добавить в стор хелпер, возвращающий второго
участника direct-чата независимо от mute, и звать его здесь.

### 3 — маппинг ошибок

~~~diff
--- a/message/internal/service/rich.go
+++ b/message/internal/service/rich.go
@@
 	if err := s.db.DeleteMessage(ctx, caller, id); err != nil {
-		return nil, svckit.InternalErr(err)
+		return nil, notFound(err)
 	}
~~~

~~~diff
--- a/message/internal/service/message.go
+++ b/message/internal/service/message.go
@@
 	if err := s.db.Leave(ctx, caller, conv); err != nil {
-		return nil, svckit.InternalErr(err)
+		return nil, notFound(err)
 	}
~~~

### 4 — метр на `SearchMessages`

~~~diff
--- a/message/internal/service/message.go
+++ b/message/internal/service/message.go
@@ func (s *Message) SearchMessages(
 	caller, err := svckit.CallerID(req)
 	if err != nil {
 		return nil, err
 	}
+	// Search scans message text server-side — meter it like the write path.
+	if !s.limit.allow(caller) {
+		return nil, connect.NewError(connect.CodeResourceExhausted,
+			errors.New("too many requests — slow down"))
+	}
~~~

Общее ведро с `SendMessage` — простейшее корректное решение. Если нужны
независимые — второе поле `*limiter` с более жёстким rate (поиск дороже отправки
на вызов).

## Чек-лист продолжения

1. Применить 4 диффа P1 (решить вопрос mute из оговорки к п.2).
2. Дописать тест: заблокированный **не может** писать в уже существующий DM —
   создать direct, заблокировать, `SendMessage` → `PermissionDenied`.
   Файл `message/internal/service/message_test.go` уже содержит
   `fakeNotifier` (строки ~631-648) и `TestSendFiresMessageNewEvent` — новый
   тест строится по тому же образцу.
3. Прогнать:

~~~bash
cd ~/IdeaProjects/pmapa
go build ./... && go vet ./...
go test ./message/...
~~~

4. Проверить непроверенное: `ports:` в `docker-compose.yml` для `notification`
   и `stats`; header injection в `notification/internal/templates`.
5. Затем P2 — по одному, начиная с 6 (fail-open) и 8 (таймеры).