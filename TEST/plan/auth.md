# auth — план API-тестов (13 RPC)

Коды ошибок и лимиты подтверждены по реализации
(auth/internal/service/{auth,loginguard}.go), не угаданы.

## Подъём сервиса

- Тир данных: postgres + redis (из env/db/auth)
- Креды тестовой БД: из auth/internal/service/auth_test.go (подтвердить при написании теста)
- Команда: cd auth && go test ./internal/service/ -run 'TestAPI' -count=1 -v
- Идентичность: публичные RPC (Register/Login/LoginWithOidc/Refresh/Logout/
  RequestPasswordReset/ResetPassword/WhoAmI) НЕ требуют X-User-Id — это и есть точки
  входа аутентификации. Сессионные RPC (ListSessions/RevokeSession/DeleteAccount/
  ChangePassword/SetEmail) требуют X-User-Id (инжектит gateway).

## Подтверждённые по impl особенности контракта

- Register: email по emailRe (^[^@\s]+@[^@\s]+\.[^@\s]+$), не placeholder, пароль >=8 байт.
  Нарушение -> InvalidArgument. Занятый email -> AlreadyExists. Провижининг handle в
  user-сервис — best-effort (его падение НЕ валит регистрацию).
- Login: единый ответ Unauthenticated для неизвестного email, пустого пароля И неверного
  пароля (нет оракула энумерации). Брут-форс гард ДО lookup и argon2:
  >=10 ошибок на аккаунт за 15 мин -> ResourceExhausted (loginScopeEmail). Per-IP тир
  выключен по умолчанию (ipMax=0).
- LoginWithOidc: provider+id_token обязательны -> InvalidArgument; провайдер не настроен
  -> FailedPrecondition; любая ошибка верификации -> Unauthenticated (единый);
  email занят -> AlreadyExists.
- Refresh: невалидный/пустой refresh -> Unauthenticated; обнаружен reuse украденного
  токена -> Unauthenticated + сессия отозвана (DenySession).
- Logout: идемпотентен, ВСЕГДА OK — не раскрывает, существовал ли токен.
- RequestPasswordReset: ВСЕГДА OK (нет энумерации), даже для неизвестного email.
- ResetPassword: новый пароль >=8 -> иначе InvalidArgument; невалидный/истёкший токен
  -> InvalidArgument (ErrNotFound свёрнут в InvalidArgument). Успех отзывает ВСЕ сессии.
- WhoAmI: невалидный access-токен -> Unauthenticated; DPoP cnf.jkt не совпал с доказанным
  ключом -> Unauthenticated; сессия в deny-list ИЛИ ошибка Redis -> Unauthenticated (fail-closed).
- RevokeSession: X-User-Id обязателен; неизвестная/чужая сессия -> NotFound (скоуп по userID).
- DeleteAccount: X-User-Id обязателен; аккаунт с паролем переаутентифицируется —
  неверный пароль -> PermissionDenied, брут-форс гард (loginScopeUser) -> ResourceExhausted;
  social-only аккаунт пропускает проверку. Пурж доменных сервисов — best-effort. Необратимо.
- ChangePassword: X-User-Id обязателен; новый пароль >=8 -> иначе InvalidArgument;
  аккаунт с паролем проверяет текущий (неверный -> PermissionDenied, гард -> ResourceExhausted);
  social-only СТАВИТ первый пароль без проверки. Успех отзывает все сессии и минтит новую пару.
- SetEmail: X-User-Id обязателен; валидный не-placeholder email -> иначе InvalidArgument;
  email занят -> AlreadyExists; email уже установлен -> FailedPrecondition (менять нельзя).

## Легенда категорий

AUTH, VALID, INV-required, INV-oversize, INV-format, NOTFOUND, PERM, IDEMP, CONFLICT,
RATE, PRECOND (определения — в TEST/README.md; PRECOND=FailedPrecondition).

---

## 1. Register

Вход: email, password, handle?, device?. Правила: email+pw>=8; занятый email -> AlreadyExists.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | VALID | email + pw>=8 + handle | OK, UserId + Tokens |
| 2 | VALID | без handle | OK (профиль пустой) |
| 3 | VALID | с device info | OK, сессия привязана |
| 4 | INV-format | битый email | InvalidArgument |
| 5 | INV-format | placeholder email | InvalidArgument |
| 6 | INV-required | пароль <8 | InvalidArgument |
| 7 | CONFLICT | email уже зарегистрирован | AlreadyExists |

## 2. Login

Вход: email, password, device?. Правила: единый Unauthenticated; брут-форс гард.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | VALID | верные учётные данные | OK, UserId + Tokens |
| 2 | INV-format | неверный пароль | Unauthenticated |
| 3 | NOTFOUND | неизвестный email | Unauthenticated (без энумерации) |
| 4 | INV-required | пустой пароль | Unauthenticated |
| 5 | RATE | >=10 ошибок за окно | ResourceExhausted |

## 3. LoginWithOidc

Вход: provider, id_token, device?. Правила: конфиг провайдера; единый Unauthenticated.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | VALID | валидный id_token, новый юзер | OK, IsNewUser=true |
| 2 | VALID | валидный id_token, возвратный | OK, IsNewUser=false |
| 3 | INV-required | provider не задан | InvalidArgument |
| 4 | INV-required | id_token пустой | InvalidArgument |
| 5 | PRECOND | провайдер не настроен | FailedPrecondition |
| 6 | INV-format | битый id_token | Unauthenticated |
| 7 | CONFLICT | email уже зарегистрирован | AlreadyExists |

## 4. Refresh

Вход: refresh_token. Правила: ротация; reuse -> отзыв сессии.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | VALID | валидный refresh | OK, новая пара |
| 2 | INV-format | невалидный токен | Unauthenticated |
| 3 | INV-format | повтор уже ротированного (reuse) | Unauthenticated, сессия отозвана |
| 4 | INV-required | пустой токен | Unauthenticated |

## 5. Logout

Вход: refresh_token. Идемпотентен, всегда OK.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | VALID | валидный токен | OK, сессия отозвана |
| 2 | IDEMP | неизвестный токен | OK (не раскрывает) |
| 3 | IDEMP | повторный logout | OK |

## 6. RequestPasswordReset

Вход: email. Всегда OK (нет энумерации).

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | VALID | известный email | OK, письмо отправлено |
| 2 | VALID | неизвестный email | OK (без энумерации) |
| 3 | VALID | пустой/битый email | OK |

## 7. ResetPassword

Вход: reset_token, new_password. Правила: pw>=8; токен единоразовый.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | VALID | валидный токен + pw>=8 | OK, все сессии отозваны |
| 2 | INV-required | new_password <8 | InvalidArgument |
| 3 | INV-format | невалидный токен | InvalidArgument |
| 4 | INV-format | истёкший токен | InvalidArgument |

## 8. WhoAmI

Вход: access_token. Правила: DPoP-биндинг; deny-list; fail-closed.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | VALID | валидный access-токен | OK, UserId/Email/HasPassword |
| 2 | INV-format | невалидный токен | Unauthenticated |
| 3 | PERM | DPoP cnf.jkt не совпал | Unauthenticated |
| 4 | NOTFOUND | сессия в deny-list (отозвана) | Unauthenticated |

## 9. ListSessions

Вход: — (self по X-User-Id).

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | список сессий | OK, страница |
| 3 | VALID | одна сессия | OK |

## 10. RevokeSession

Вход: session_id. Правила: скоуп по userID; чужая/неизвестная -> NotFound.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | отозвать свою сессию | OK, deny в Redis |
| 3 | NOTFOUND | неизвестный session_id | NotFound |
| 4 | NOTFOUND | сессия другого пользователя | NotFound |

## 11. DeleteAccount

Вход: password?, device?. Правила: переаутентификация pw-аккаунта; гард; необратимо.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | pw-аккаунт + верный пароль | OK, пурж + удаление |
| 3 | VALID | social-only (без пароля) | OK (проверка пропущена) |
| 4 | PERM | неверный пароль | PermissionDenied |
| 5 | RATE | много неверных паролей | ResourceExhausted |

## 12. ChangePassword

Вход: current_password?, new_password, device?. Правила: new>=8; current для pw-аккаунта.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | верный current + new>=8 | OK, новая пара, остальные сессии отозваны |
| 3 | VALID | social-only ставит первый пароль | OK (без проверки current) |
| 4 | INV-required | new_password <8 | InvalidArgument |
| 5 | PERM | неверный current | PermissionDenied |
| 6 | RATE | много неверных current | ResourceExhausted |

## 13. SetEmail

Вход: email. Правила: валидный не-placeholder; занятый -> AlreadyExists; уже установлен -> FailedPrecondition.

| # | Категория | Запрос | Ожидаемый результат |
|---|-----------|--------|---------------------|
| 1 | AUTH | без X-User-Id | Unauthenticated |
| 2 | VALID | установить email, пока не задан | OK, Email (lowercase) |
| 3 | INV-format | битый email | InvalidArgument |
| 4 | INV-format | placeholder email | InvalidArgument |
| 5 | CONFLICT | email уже зарегистрирован | AlreadyExists |
| 6 | PRECOND | email уже установлен | FailedPrecondition |
