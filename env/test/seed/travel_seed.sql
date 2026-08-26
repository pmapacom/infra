-- PMapa travel-service seed. Attaches TRIPS + VISITED (countries & cities) to a
-- real, logged-in user so the Timeline / Trip details / Visited screens show
-- real data instead of the app's SampleData.
--
-- Parameter:  :ruser  — the real user's auth UUID (passed by seed.sh with -v).
-- Idempotent: fixed ids + ON CONFLICT DO NOTHING, safe to re-run.
--
-- trips.document / visited.document are OPAQUE client JSON — the service never
-- interprets them, so the shapes below must match the app's Trip/Country/City
-- `toJson()` exactly (models/trip.dart, models/country.dart, models/city.dart).

BEGIN;

-- ── Trips (Trip.toJson) ──────────────────────────────────────────────────────
INSERT INTO trips (user_id, id, document, deleted, created_at, updated_at) VALUES
(
  :'ruser'::uuid, 'seed-trip-euro',
  json_build_object(
    'id','seed-trip-euro',
    'title','European Summer',
    'dateRange','Jun 12 – Jun 26, 2025',
    'location','Paris · Lyon · Rome',
    'country','France',
    'imageUrl','https://images.unsplash.com/photo-1502602898657-3e91760cbb34?w=800',
    'photoUrls', json_build_array(
      'https://images.unsplash.com/photo-1502602898657-3e91760cbb34?w=800',
      'https://images.unsplash.com/photo-1552832230-c0197dd311b5?w=800'),
    'isUpcoming', false,
    'photoCount', 2,
    'placeCount', 3,
    'stops', json_build_array(
      json_build_object('title','Paris','dateRange','Jun 12 – Jun 16','duration','4 DAYS',
        'description','Louvre, Montmartre and long café mornings.','arrival','Jun 12','departure','Jun 16',
        'transport', json_build_object('label','Flight','icon','flight'),
        'imageUrl','https://images.unsplash.com/photo-1502602898657-3e91760cbb34?w=400','isCurrent', false),
      json_build_object('title','Lyon','dateRange','Jun 16 – Jun 20','duration','4 DAYS',
        'description','Old town, food halls and the rivers.','arrival','Jun 16','departure','Jun 20',
        'transport', json_build_object('label','Train','icon','train'),
        'imageUrl','https://images.unsplash.com/photo-1524484485831-a92ffc0de03f?w=400','isCurrent', false),
      json_build_object('title','Rome','dateRange','Jun 20 – Jun 26','duration','6 DAYS',
        'description','Colosseum, Trastevere and too much gelato.','arrival','Jun 20','departure','Jun 26',
        'transport', json_build_object('label','Train','icon','train'),
        'imageUrl','https://images.unsplash.com/photo-1552832230-c0197dd311b5?w=400','isCurrent', false))
  )::text,
  false, now() - interval '90 days', now() - interval '64 days'
),
(
  :'ruser'::uuid, 'seed-trip-japan',
  json_build_object(
    'id','seed-trip-japan',
    'title','Japan in Spring',
    'dateRange','Apr 6 – Apr 18, 2026',
    'location','Tokyo · Kyoto · Osaka',
    'country','Japan',
    'imageUrl','https://images.unsplash.com/photo-1493976040374-85c8e12f0c0e?w=800',
    'photoUrls', json_build_array(),
    'isUpcoming', true,
    'photoCount', 0,
    'placeCount', 3,
    'stops', json_build_array(
      json_build_object('title','Tokyo','dateRange','Apr 6 – Apr 10','duration','4 DAYS',
        'description','Shibuya, Shinjuku and the first cherry blossoms.','arrival','Apr 6','departure','Apr 10',
        'transport', json_build_object('label','Flight','icon','flight'),
        'imageUrl','https://images.unsplash.com/photo-1540959733332-eab4deabeeaf?w=400','isCurrent', true),
      json_build_object('title','Kyoto','dateRange','Apr 10 – Apr 15','duration','5 DAYS',
        'description','Temples, Gion and a tea ceremony.','arrival','Apr 10','departure','Apr 15',
        'transport', json_build_object('label','Train','icon','train'),
        'imageUrl','https://images.unsplash.com/photo-1493976040374-85c8e12f0c0e?w=400','isCurrent', false),
      json_build_object('title','Osaka','dateRange','Apr 15 – Apr 18','duration','3 DAYS',
        'description','Dotonbori and street food.','arrival','Apr 15','departure','Apr 18',
        'transport', json_build_object('label','Train','icon','train'),
        'imageUrl','https://images.unsplash.com/photo-1590559899731-a382839e5549?w=400','isCurrent', false))
  )::text,
  false, now() - interval '10 days', now() - interval '2 days'
)
ON CONFLICT (user_id, id) DO NOTHING;

-- ── Visited countries (Country.toJson; key = country name) ───────────────────
INSERT INTO visited (user_id, kind, key, document, deleted, created_at, updated_at)
SELECT :'ruser'::uuid, 'visited_country', v.name,
  json_build_object('name', v.name, 'flag', v.flag, 'region', v.region,
    'subtitle','', 'imageUrl', v.img, 'cities', v.cities, 'days', v.days)::text,
  false, now() - (v.ord || ' days')::interval, now() - (v.ord || ' days')::interval
FROM (VALUES
  ('Japan','🇯🇵','Asia','https://images.unsplash.com/photo-1493976040374-85c8e12f0c0e?w=200', 8, 21, 1),
  ('France','🇫🇷','Europe','https://images.unsplash.com/photo-1502602898657-3e91760cbb34?w=200', 12, 42, 2),
  ('Italy','🇮🇹','Europe','https://images.unsplash.com/photo-1516483638261-f4dbaf036963?w=200', 6, 18, 3),
  ('United Kingdom','🇬🇧','Europe','https://images.unsplash.com/photo-1513635269975-59663e0ac1ad?w=200', 5, 14, 4),
  ('United States','🇺🇸','Americas','https://images.unsplash.com/photo-1496588152823-86ff7695e68f?w=200', 32, 120, 5)
) AS v(name, flag, region, img, cities, days, ord)
ON CONFLICT (user_id, kind, key) DO NOTHING;

-- ── Visited cities (City.toJson; key = "Name, Country") ──────────────────────
INSERT INTO visited (user_id, kind, key, document, deleted, created_at, updated_at)
SELECT :'ruser'::uuid, 'visited_city', v.name || ', ' || v.country,
  json_build_object('name', v.name, 'country', v.country, 'region', v.region,
    'role','', 'year', v.year, 'imageUrl', v.img)::text,
  false, now() - (v.ord || ' days')::interval, now() - (v.ord || ' days')::interval
FROM (VALUES
  ('Tokyo','Japan','Asia','2025','https://images.unsplash.com/photo-1540959733332-eab4deabeeaf?w=200', 1),
  ('Kyoto','Japan','Asia','2025','https://images.unsplash.com/photo-1493976040374-85c8e12f0c0e?w=200', 2),
  ('Paris','France','Europe','2025','https://images.unsplash.com/photo-1502602898657-3e91760cbb34?w=200', 3),
  ('Rome','Italy','Europe','2025','https://images.unsplash.com/photo-1552832230-c0197dd311b5?w=200', 4),
  ('London','United Kingdom','Europe','2024','https://images.unsplash.com/photo-1513635269975-59663e0ac1ad?w=200', 5)
) AS v(name, country, region, year, img, ord)
ON CONFLICT (user_id, kind, key) DO NOTHING;

COMMIT;
