# Веерные s2s-контракты — интеграционный план (сквозь несколько сервисов)

Фаза 3. База — `TEST/plan/api-infra.md` и `TEST/plan/notification.md` (S1/S2). Здесь
то, что проверяется ТОЛЬКО когда в контуре подняты все участники веера одновременно:
реальный s2s-веер PurgeUser из auth, SendEmail и Notify по сети.

## Подъём в контуре

- Для PurgeUser: auth + user + travel + post + message + media + их БД.
- Для SendEmail/Notify: notification + отправители (auth, message, post) + тестовые
  Sender/Pusher с перехватом (подтвердить по env/test/contour).

## F1. FANOUT — DeleteAccount -> PurgeUser по пяти сервисам

Сквозной каскад. auth при удалении аккаунта зовёт каждый сервис s2s, проставляя
X-User-Id удаляемого юзера; каждый стирает ТОЛЬКО свой срез.

### Подготовка
Насидить данные юзера A (и контрольного B) во всех пяти: профиль+follows+blocks (user),
trip+visited+share (travel), посты+комментарии+лайки (post), беседы+сообщения (message),
загруженные media.

### Шаги и ассерты
1. auth.DeleteAccount(A) (pw-аккаунт -> верный пароль; social-only -> без проверки) -> OK.
2. По каждому сервису проверить срез A (детали — таблица ниже), срез B нетронут.
3. Повторный PurgeUser в каждом сервисе напрямую -> OK (idemp no-op).
4. PurgeUser для несуществующего юзера -> OK.
5. Любой вызов токеном A через gateway -> 401 (аккаунт удалён, сессии отозваны).

| Сервис | Проверить ПОСЛЕ purge A | Особенность |
|--------|--------------------------|-------------|
| user | профиль A нет; follows/blocks/requests A в обе стороны нет; reports A нет; B цел | одна tx |
| travel | trips/visited/shares A нет; членство A в чужих поездках снято; поездки B целы | одна tx |
| post | posts/comments/reviews/likes/saves A нет; посты B целы | счётчики B могут быть завышены — ожидаемо |
| message | reactions/read_cursors/members A нет; сообщения A тумбстоун (deleted, пустое тело); беседы B читаемы | строки сообщений остаются |
| media | строки media A нет; для S3 Delete блоба на каждый s3ID (best-effort) | ошибка блоба НЕ валит RPC |

### CHAOS-вариант (error-path каскада)
Остановить БД одного из пяти перед шагом 1 -> этот сервис вернёт Internal
(`svckit.InternalErr`), auth фиксирует сбой веера; остальные срезы ведут себя по
контракту. Проверяет непокрытый internalErr-путь на реальной БД.

## F2. FANOUT — Notify (pmapa.api.notify) по реальному пути

1. Источник (message.SendMessage / post.Like) -> notification.Notify s2s с type+user_ids.
2. EnabledRecipients фильтрует замьюченных (реальные prefs в БД notification).
3. Insert на разрешённых; push.Pusher вызван с заголовком per-type.
4. Пустой список получателей (все замьютили) -> OK no-op, Insert не вызван.
5. Insert err (остановить БД notification) -> Internal у Notify; источник обрабатывает
   по своему best-effort контракту.

## F3. FANOUT — SendEmail (pmapa.api.email) по реальному пути

1. auth.RequestPasswordReset -> notification.SendEmail(template=password_reset, to, vars).
2. to невалиден / template пуст -> InvalidArgument; отсутствует обязательная var ->
   InvalidArgument.
3. password_reset + resetURLBase -> link=base+token в теле; Sender.Send вызван.
4. Sender.Send err -> Internal.

## Легенда

FANOUT, CHAOS, RPATH (см. integration/README.md). Коды — из api-infra.md и
notification.md (подтверждены по impl).
