# travel — интеграционный план (совместные поездки между юзерами)

Фаза 3. База — `TEST/plan/travel.md`. Интеграция: коллаборация через share-код между
ДВУМЯ реальными юзерами по пути gateway — одношаговые матрицы фазы 2 это не ловят.

## Подъём в контуре

- Контейнеры: travel + postgres, gateway, auth.

## Сценарии

### V1. FLOW — sharing + права коллаборатора (два юзера)
1. Владелец O: PutTrip(T) -> OK.
2. Юзер U без прав: PutTrip(T) -> PermissionDenied.
3. O: ShareTrip(T) -> share_code=SC.
4. U: JoinTrip(SC) -> OK, trip виден в ListMyTrips(U).
5. U: PutTrip(T) -> OK (коллаборатор получил запись).
6. O: RemoveTripMember(T,U) -> OK; U: PutTrip(T) снова -> PermissionDenied.

### V2. FLOW — отзыв и повторный join
1. O: ShareTrip -> SC; UnshareTrip(T) -> код отозван.
2. U: JoinTrip(SC) -> NotFound (shareErr). Повтор join после нового ShareTrip -> OK.

### V3. ISO — visited и trips изолированы по владельцу
1. U: PutVisited(kind,key) -> видно только U; O не видит visited U.
2. U: PutTrip(своя) -> ListMyTrips(O) её не содержит.

### V4. FANOUT — PurgeUser снимает членство и стирает trips (см. _fanout.md)
PurgeUser(O) -> trips/visited/shares O нет, членство O в чужих поездках снято;
поездки U и их не-O участники целы.
