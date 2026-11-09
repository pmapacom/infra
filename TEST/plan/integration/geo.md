# geo — интеграционный план (public reference через gateway)

Фаза 3. База — `TEST/plan/geo.md`. geo — read-only словарь в памяти, без БД и без
соседей. Интеграция сводится к одному: gateway роутит geo БЕЗ auth_request, и полный
датасет загружен в контейнере.

## Подъём в контуре

- Контейнеры: geo (словарь из geo/internal/dict грузится на старте), gateway. БД нет.

## Сценарии

### G1. PUBLIC — все 5 RPC без identity через gateway
ListCountries / GetCountry / ListCities / GetCity / ListRegions через :8088 БЕЗ
Authorization -> OK. Проверяет, что на geo-маршрутах auth_request НЕ навешан
(иначе публичный справочник сломался бы). Любой owner-токен тоже принимается, но не
обязателен.

### G2. VALID — полный датасет в контейнере (не усечённый тестовый)
1. ListCountries без фильтров -> total=246 (полный ISO 3166-1 в контейнере).
2. GetCountry("FR") -> France с flag/region/centroid.
3. GetCountry("ZZ") -> NotFound; GetCountry("") -> InvalidArgument.
4. ListCities(query="tokyo") -> Tokyo, country_name/flag заполнены джойном;
   GetCity("Tokyo") -> самый населённый матч, image из cityPhotos при совпадении ключа.

### G3. PAGE-clamp — пагинация на реальном объёме
offset/limit границы (limit=0 -> 60; limit=1000 -> 250; offset<0 -> 0;
offset за пределами total -> пустая страница, total полный) на полном cities-датасете.

### G4. INV — согласованность словаря
ListRegions: сумма country_count по регионам = числу стран с регионом (полный датасет).
