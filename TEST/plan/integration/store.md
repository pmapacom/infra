# store — интеграционный план (public-read + владение + избранное)

Фаза 3. База — `TEST/plan/store.md`. Интеграция: PUBLIC-маршруты через gateway и
изоляция владельца на реальной БД.

## Подъём в контуре

- Контейнеры: store + postgres, gateway, auth, media (картинки товаров).

## Сценарии

### T1. PUBLIC — GetGood/ListGoods без identity
1. ListGoods и GetGood через gateway БЕЗ токена -> OK, аноним.
2. Owner-RPC (PutGood/DeleteGood/SaveGood/...) без токена -> 401 на gateway.

### T2. ISO — изоляция владельца через gateway
1. A: PutGood(id=G).
2. B: PutGood(id=G) -> AlreadyExists (ErrWrongOwner); товар A не изменён (GetGood).

### T3. FLOW — избранное
1. B: SaveGood(G) -> ListSavedGoodIds(B) содержит G; повтор Save -> OK (одна запись).
2. UnsaveGood(G) -> список пуст; повтор Unsave -> OK (no-op).

### T4. XSVC — картинки товара через media
PutGood с image из media.UploadImage -> GetGood возвращает url -> GET `/media/{id}` -> 200.

### T5. PAGE-inv — cursor-пагинация
Насидить > limit товаров; пройти все страницы по курсору -> объединение = N уникальных id.
