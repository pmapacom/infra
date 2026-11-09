# message — интеграционный план (стрим, rate-limit, уведомления по сети)

Фаза 3. База — `TEST/plan/message.md` (per-RPC уже зелёный, 21/21). Интеграция
добавляет три вещи, которых нет в in-process: живой Subscribe-стрим, rate-limit на
реальном Redis и message -> notification по сети (самые слабые места покрытия:
Subscribe 13.6%, sweep 33.3%, dispatchPush).

## Подъём в контуре

- Контейнеры: message + postgres(:5437) + redis, gateway, auth, notification (приёмник
  Notify), notification -> push.Pusher (device tokens).

## Сценарии

### M1. STREAM — Subscribe доставляет сообщение в реальном времени
1. Юзер A открывает Subscribe-стрим (долгоживущий, через gateway).
2. Юзер B отправляет SendMessage в общую беседу.
3. На стриме A приходит событие в пределах таймаута -> проверка доставки.
4. Закрытие стрима корректно завершает горутину (нет утечки — повторить N раз).
   Это путь message.go:317 Subscribe (13.6% в юнитах).

### M2. STREAM — rate-limit и sweep на живом Redis
1. Burst SendMessage сверх окна одним юзером -> ResourceExhausted.
2. Подождать окно -> `sweep` чистит лимитер -> следующий SendMessage снова OK.
   Путь ratelimit.go:51 sweep (33.3%).

### M3. XSVC — новое сообщение рождает уведомление
1. A и B в беседе; у B зарегистрирован device (notification.RegisterDevice).
2. A SendMessage -> message зовёт notification.Notify ПО СЕТИ.
3. notification.ListNotifications(B) -> событие есть; push.Pusher вызван
   (dispatchPush/pushTitle — непокрытый switch по типам, см. notification.md).

### M4. XSVC — мьют через prefs гасит уведомление
1. B: UpdateNotificationPrefs {message.new:false}.
2. A SendMessage -> Notify отфильтрован EnabledRecipients -> Insert НЕ произошёл,
   ListNotifications(B) без нового события (no-op), сообщение всё равно доставлено.

### M5. RPATH/PERM — права не-админа беседы через gateway
1. Не-админ вызывает SetAdmin/UpdateConversation/RemoveMember -> PermissionDenied.
2. Доступ к чужой беседе -> NotFound (notFound() сворачивает ErrNotMember).

### M6. FANOUT — PurgeUser тумбстонит (см. _fanout.md)
PurgeUser(A) -> reactions/read_cursors/members A нет; сообщения A -> deleted=true,
body='', image_url='' (строки на месте); беседы B читаемы.
