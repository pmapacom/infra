# auth — интеграционный план (реальный путь + веер удаления)

Фаза 3. База — `TEST/plan/auth.md` (коды ошибок по impl). Здесь только то, что
проверяется на реальном пути через gateway с живыми redis/postgres и соседями.

## Подъём в контуре

- Контейнеры: auth + postgres + redis (deny-list, брут-форс гард), gateway (:8088).
- Соседи по сети: user (ленивый провижининг handle при Register — best-effort),
  user/travel/post/message/media (приёмники `PurgeUser` при DeleteAccount).
- Транспорт: `app/tool/auth_smoke.dart` уже покрывает Register -> DPoP -> ListSessions;
  расширять им же.

## Сценарии

### A1. RPATH — gateway auth_request поверх WhoAmI
1. Register через gateway -> OK, получили access+refresh, DPoP-ключ привязан.
2. Owner-scoped вызов (напр. user.GetMyProfile) с валидным токеном -> gateway зовёт
   auth.WhoAmI, инъектит X-User-Id -> OK.
3. Тот же вызов с испорченным DPoP-доказательством -> **401 на gateway** (сервис user
   не вызван). Проверяет cnf.jkt-биндинг на живом транспорте.
4. Вызов без Authorization -> 401 до сервиса.

### A2. FLOW — ротация и отзыв видны через gateway (реальный Redis deny-list)
1. Refresh -> новая пара; старый refresh повторно (reuse) -> Unauthenticated,
   сессия в deny-list Redis.
2. Любой owner-scoped вызов со старым access той же сессии -> 401 (fail-closed по
   реальному Redis, не по фейку).
3. ChangePassword -> все прочие сессии отозваны -> их токены -> 401 через gateway.

### A3. RATE — брут-форс гард на реальном Redis
1. 10 Login с неверным паролем на один email за окно -> ResourceExhausted
   (счётчик loginScopeEmail в живом Redis, не в памяти теста).
2. Верный Login после срабатывания гарда до истечения окна -> ResourceExhausted.

### A4. XSVC — провижининг handle в user (best-effort)
1. Register с handle -> OK; user.GetProfile(handle) -> профиль существует (auth -> user).
2. Остановить user-контейнер, Register с handle -> **OK всё равно** (провижининг
   best-effort, его падение НЕ валит регистрацию) — CHAOS на некритичной зависимости.

### A5. FANOUT — DeleteAccount как сквозной веер (см. _fanout.md)
1. Насидить данные юзера U во всех пяти сервисах.
2. DeleteAccount(U) -> auth зовёт s2s PurgeUser в user/travel/post/message/media
   с X-User-Id=U -> OK.
3. Проверить срез U стёрт в каждом (детали и ассерты — `_fanout.md`).
4. Повторный любой вызов токеном U -> 401 (сессии отозваны, аккаунт удалён).

### A6. XSVC — ResetPassword через письмо (см. notification.md S1)
1. RequestPasswordReset -> auth зовёт notification.SendEmail (template=password_reset)
   -> Sender вызван, link=base+token подставлен.
2. ResetPassword валидным токеном -> OK, все сессии отозваны.
