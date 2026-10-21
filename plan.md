# План: карта в Goods (регион + карта товаров)

Статус на 2026-10-14. Исходный `HANDOFF-map.md` найти не удалось (`glob **/HANDOFF*`
пусто), поэтому список восстановлен из чтения кода в этой сессии, а не из ТЗ.
Пункты с пометкой `[?]` — продуктовые решения, их нужно подтвердить.

## Сделано и проверено

- `GoodsRegion.area` переведён с `Offset` + `radiusFraction` на `LatLng` +
  реальные километры; расстояние считается через `app/lib/data/geo/geo_math.dart`.
- `_RadiusMap` (`app/lib/screens/goods_region_widgets.dart`) переписан с
  схематичного `MapBackdrop` на настоящий `FlutterMap`:
  - тайлы OSM (`tile.openstreetmap.org`), `userAgentPackageName: com.pmapa.app`;
  - круг радиуса — `CircleMarker` с `useRadiusInMeter: true`, то есть остаётся
    честным кругом в `radiusKm` на любом зуме;
  - зум считается из радиуса и широты (`_zoomForRadius`, поправка на `cos(lat)`),
    клампится в диапазон 2..16;
  - камера следует за новым центром и за изменением радиуса (`didUpdateWidget`);
  - тап по карте возвращает `LatLng` через `onCenterChanged`.
- `GoodsMap` (`app/lib/screens/goods/goods_map_view.dart`) переведён с
  `MapBackdrop` на настоящий `FlutterMap`:
  - те же тайлы OSM и `userAgentPackageName: com.pmapa.app`, что в
    `location_picker_screen.dart` и `_RadiusMap`;
  - пин на каждое объявление с координатами (`MarkerLayer`), пины
    центрированы на точке, ключ `goods-map-pin-<id>` для тестов и тапа;
  - камера кадрируется по bounding box объявлений (`CameraFit.bounds`,
    отступ 48 px, `maxZoom` = `_singlePinZoom` 13); если фитить нечего —
    один пин или несколько с одинаковой координатой — остаётся
    `initialCenter`/`initialZoom`, а при полном отсутствии координат
    карта показывает мир (`zoom 2`);
  - промежуточная проекция `_projectPins` / `_pinMargin` удалена как
    больше не нужная;
  - бейдж `N nearby` остался оверлеем поверх карты, полоса мини-карточек
    под картой не изменилась.
- Тесты синхронизированы: фикстуры переведены в реальные градусы
  (Shibuya / Gion / Namba), тап по region-карте и по пину `GoodsMap` ищет
  `FlutterMap` и пампит 400 мс (`FlutterMap` арбитрирует одиночный и двойной
  тап, `onTap` срабатывает только после таймаута ~300 мс).
- Проверка: `flutter analyze` чистый (остались только прежние
  `avoid_redundant_argument_values` info в несвязанных тестах),
  `flutter test` — 3526 тестов зелёные.
- **Атрибуция OSM** (вариант A — на каждой карте). В
  `app/lib/widgets/osm_tile_layer.dart` добавлен виджет `OsmAttribution`
  («© OpenStreetMap contributors»): полупрозрачная плашка
  `surface.withValues(alpha: 0.8)`, `labelSmall` 10 px, `Align` внутри
  области карты. Включён последним ребёнком `FlutterMap` (рисуется поверх
  тайлов и маркеров) в трёх местах:
  - `location_picker_screen.dart` — `bottomLeft` (справа снизу кнопка
    «моё местоположение»);
  - `goods/goods_map_view.dart` — `bottomRight` (бейдж `N nearby` слева сверху);
  - `goods_region_widgets.dart` (`_RadiusMap`) — `bottomRight` (бейдж км
    слева снизу).
  Намеренно не `RichAttributionWidget`: он прячет текст за тап по кнопке
  «i», а его ссылки требуют `url_launcher`, которого нет в зависимостях.
  Виджет экспортируется через баррел `widgets/widgets.dart`, поэтому
  дополнительных импортов не потребовалось.
  Проверка: `flutter analyze` чистый, `flutter test` по трём карт-наборам —
  62 теста зелёные.
- **Заглушка тайлов в widget-тестах.** В `app/lib/widgets/osm_tile_layer.dart`
  есть точка подмены `debugOsmTileProviderOverride` (`null` → штатный
  `NetworkTileProvider`), а в `app/test/helpers.dart`:
  - `kTransparentTilePng` — однопиксельный прозрачный PNG из base64,
    декодируется один раз, поэтому все тайлы делят одну запись кеша
    `MemoryImage`;
  - `FakeTileProvider extends TileProvider` — отдаёт этот тайл на любые
    `TileCoordinates`, в сеть не ходит;
  - `useFakeTiles()` — ставит override в `setUpAll` и снимает в `tearDownAll`.
  Подключено в наборах, которые пампят карту: `goods_region_screen_test.dart`,
  `location_picker_screen_test.dart`, `goods/good_widgets_test.dart`,
  `goods/goods_screen_test.dart` (последний открывает `GoodsRegionScreen`
  через region bar). Других тестов с `FlutterMap` в `app/test` нет
  (проверено поиском по `FlutterMap|GoodsMap|LocationPickerScreen|
  GoodsRegionScreen`). `ClientException` из лога ушёл, прогон не зависит от
  сети.

- **Аудит остальных экранов с `MapBackdrop`** — ошибки проекции нет, править
  нечего. `MapBackdrop` принимает `pins`/`activePin` как `Offset` в долях
  0..1 от размера виджета (см. док-комментарии в
  `app/lib/widgets/map_backdrop.dart`), и все четыре места использования в
  `lib` передают именно декоративные доли, а не градусы:
  - `country_details_widgets.dart:89` — `[(0.35,0.4), (0.62,0.55),
    (0.5,0.7)]`, фолбэк для страны без флага/ISO;
  - `review_trip_screen.dart:147` — `[(0.5,0.28), (0.4,0.6), (0.28,0.85)]`;
  - `trip_details_screen.dart:62` — `[(0.25,0.6), (0.55,0.48), (0.8,0.72)]`;
  - `route_plan_widgets.dart:15` — `const MapBackdrop()` без аргументов
    (пустой маршрут), реальные координаты идут мимо него в `PMapaMap`
    через `MapCity(lat:, lng:)`.
  Оценка «10 файлов» в прежней версии плана была завышена: `MapBackdrop`
  упоминается в 8 файлах, из них 4 в `lib` — сам виджет, и 3 в тестах
  (`country_details_screen_test.dart`, `route_plan_screen_test.dart`,
  `map_backdrop_test.dart`), которые проверяют только факт его наличия.

## Осталось доделать

1. **`[?]` Политика тайлов.** Запросы идут напрямую на
   `tile.openstreetmap.org` без кеша: это против Tile Usage Policy OSM при
   реальном трафике. Нужно продуктовое решение до релиза — один из вариантов:
   - кеширующий `TileProvider` на диске (пакет вроде
     `flutter_map_cache` / `flutter_map_tile_caching`, в зависимостях
     сейчас нет);
   - свой прокси/CDN перед OSM и замена `kOsmTileUrlTemplate` на его адрес;
   - платный тайл-провайдер с ключом.
   Точка входа одна — `kOsmTileUrlTemplate` и `osmTileLayer()` в
   `app/lib/widgets/osm_tile_layer.dart`, так что замена локальная.

## Пропавшая спецификация — закрыто

`HANDOFF-map.md` в репозитории никогда не существовало. Проверено по всей
истории всех ветвей — обе команды вернули пустой вывод:

- `git log --all --diff-filter=D --name-only --oneline -- '*HANDOFF*'`
- `git log --all --name-only --oneline -- '*HANDOFF*'`

Ни удалённой версии, ни какого-либо коммита, затрагивающего файл с таким
именем, нет. Значит, список задач выше — единственный источник требований по
карте; искать «потерянное ТЗ» больше не нужно.

## Финальная проверка

`cd app && flutter test` — 3526 тестов, все зелёные (105 с). `flutter analyze`
чистый, кроме прежних `avoid_redundant_argument_values` info в несвязанных
тестах. Добавленный `OsmAttribution` ничего не сломал ни на одном из экранов.
