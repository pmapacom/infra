# message — план API-тестов (ЭТАЛОН, реализовано)

Тесты уже написаны: message/internal/service/api_coverage_test.go, набор TestAPI*
зелёный (21/21). Этот файл — эталон глубины и формата для остальных сервисов.

## Подъём сервиса

- Тир данных: postgres:17-alpine, порт 5437
- Креды: message:devpass@localhost:5437/message_test (из message_test.go, newSvcGate)
- Команда: cd message && go test ./internal/service/ -run 'TestAPI' -count=1 -v

## Подтверждённые по impl особенности контракта

- DeleteMessage, LeaveConversation — идемпотентны: неизвестная/чужая цель -> OK (no-op),
  не NotFound (store возвращает nil на pgx.ErrNoRows; messages.go:146-148,
  conversations.go:248-250).
- notFound() сворачивает ErrNotFound/ErrNotMember -> NotFound, ErrForbidden ->
  PermissionDenied (rich.go:26-34) — нет оракула, какая именно проверка упала.
- Лимиты: maxTitleBytes=256, maxEmojiBytes=32, maxMessageBytes, maxURLBytes, maxMembers.

## Полная матрица

Матрица из 21 RPC зафиксирована в коде теста (api_coverage_test.go).
Сводка по категориям — в TEST/metrics/coverage.csv (строки message,*).

Ключевые углубления (кандидаты к добору): права не-админа на
SetAdmin / UpdateConversation / RemoveMember -> PermissionDenied; rate-limit на
SendMessage -> ResourceExhausted; клампинг пагинации
ListMessages / ListMyConversations (Default 50, Max 100/200).
