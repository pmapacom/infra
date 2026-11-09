# notification — интеграционный план (приёмник событий + push/email)

Фаза 3. База — `TEST/plan/notification.md`. Интеграция: notification живьём получает
`Notify` от message/post по сети и реально диспетчеризует push — это непокрытые в
юнитах dispatchPush (70%) и pushTitle (50%).

## Подъём в контуре

- Контейнеры: notification + postgres, gateway, auth; отправители событий (message,
  post). push.Pusher и mail.Sender в контуре — тестовые (LogSender / фейковый pusher
  с перехватом вызовов), подтвердить по env/test/contour.

## Сценарии

### N1. RPATH — owner-поверхность за gateway
RegisterDevice/UnregisterDevice/ListNotifications/MarkNotificationsRead/
Get-/UpdateNotificationPrefs без токена -> 401; с токеном -> OK (self по X-User-Id).

### N2. XSVC/STREAM — реальная диспетчеризация push по типам
1. B: RegisterDevice(token).
2. Событие каждого типа через источник (message.new из message, like/comment/follow
   из post) -> notification.Notify по сети -> `dispatchPush` строит заголовок
   `pushTitle` per-type -> push.Pusher получил вызов с правильным заголовком.
   Прогнать ВЕСЬ switch по типам (это и есть непокрытые ветки).
3. unread_count растёт; MarkNotificationsRead -> 0.

### N3. XSVC — мьют гасит и in-app, и push
UpdateNotificationPrefs {type:false} -> событие type -> Insert НЕ произошёл,
push НЕ вызван (EnabledRecipients отфильтровал), событие у источника всё равно успешно.

### N4. XSVC — SendEmail из auth (password reset enrichment)
auth.RequestPasswordReset -> notification.SendEmail(template=password_reset) по сети
-> Sender.Send вызван, link=resetURLBase+token подставлен.

### N5. CHAOS — push недоступен не валит событие
Pusher возвращает ошибку -> Notify всё равно OK (push best-effort, ошибки глотаются),
in-app feed записан.
