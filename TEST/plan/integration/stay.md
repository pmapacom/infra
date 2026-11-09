# stay — интеграционный план (public-read + гонки бронирования)

Фаза 3. База — `TEST/plan/stay.md`. Интеграция: PUBLIC-маршруты через gateway без
токена и реальные гонки на БД (двойное бронирование), которые in-process не ловит.

## Подъём в контуре

- Контейнеры: stay + postgres, gateway, auth (для owner-RPC), media (картинки листингов).

## Сценарии

### S1. PUBLIC — ListStays/GetStay без identity
1. GET-эквивалент ListStays и GetStay через gateway БЕЗ Authorization -> OK, аноним
   (gateway снял identity, optionalCaller=""). Проверяет, что auth_request НЕ навешан
   на публичные маршруты stay.
2. Owner-RPC (PutStay и т.д.) без токена -> 401 на gateway.

### S2. FLOW — booking lifecycle через gateway (две реальные стороны)
1. Хост H: PutStay(S, rent, доступные даты).
2. Гость G: CreateBooking(S,[d1,d2]) -> OK, pending.
3. Другой гость на те же даты -> AlreadyExists (ErrDatesTaken).
4. H: RespondToBooking(accept) -> confirmed; повтор -> NotFound (заявка не живая).
5. G: CancelBooking -> даты снова свободны -> новый CreateBooking(S,[d1,d2]) -> OK.

### S3. RACE — нет двойного бронирования на реальной БД
1. Два параллельных CreateBooking на пересекающиеся даты -> ровно один OK, второй
   AlreadyExists (проверка констрейнта БД, не памяти).
2. Два PutStay с одинаковым новым id от разных владельцев -> один OK, второй AlreadyExists.

### S4. XSVC — картинки листинга через media
PutStay с image из media.UploadImage -> GetStay возвращает url -> GET `/media/{id}`
через gateway -> 200, байты.

### S5. PAGE-inv — offset-пагинация под нагрузкой
Насидить > limit листингов; пройти страницы; битый cursor -> выдача с начала (НЕ ошибка).
