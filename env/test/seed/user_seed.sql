-- PMapa user-service test-contour seed.
--
-- Idempotent (safe to re-run): inserts ~40 demo profiles + a follow graph among
-- them, then enriches any REAL (auto-provisioned, non-seed) user with a
-- name/handle/bio/avatar plus followers/following — so Profile, Connections and
-- Discover render populated, realistic data instead of the app's SampleData.
--
-- Demo profiles use deterministic UUIDs prefixed `a0000000-0000-4000-8000-`, so
-- re-runs no-op and real users are told apart by NOT sharing that prefix.
-- Avatars use pravatar.cc (real images) so screens look production-like.

BEGIN;

-- 1) 40 demo profiles ---------------------------------------------------------
WITH pool AS (
  SELECT
    ARRAY['Elena','Marco','Aiko','Liam','Sofia','Noah','Yuki','Diego','Nina','Omar',
          'Clara','Ravi','Mia','Hugo','Ines','Kenji','Lea','Pablo','Anya','Theo',
          'Zara','Finn','Maya','Luca','Freya','Ivan','Rosa','Emil','Tara','Bruno',
          'Lena','Milo','Sara','Otto','Vera','Karl','Nadia','Felix','Iris','Dario']::text[] AS firsts,
    ARRAY['Rostova','Silva','Tanaka','Walsh','Moretti','Berg','Sato','Torres','Kaur','Hassan',
          'Novak','Patel','Chen','Muller','Costa','Ito','Dubois','Ramos','Volkov','Klein',
          'Haddad','Olsen','Reyes','Bianchi','Larsen','Petrov','Mendez','Fischer','Singh','Rossi',
          'Weber','Marin','Cohen','Braun','Horvat','Vogel','Aziz','Baumann','Flynn','Greco']::text[] AS lasts,
    ARRAY['Exploring the world, one city at a time.',
          'Coffee, maps and long train rides.',
          'Photographer chasing golden hour.',
          'Product designer. Sometimes a chef.',
          'Trail runner and weekend cartographer.',
          'Collecting stamps and street food.',
          'Building things and visiting places.',
          'Slow travel, strong espresso.',
          'Museum hopper. City wanderer.',
          'Always planning the next trip.']::text[] AS bios
)
INSERT INTO profiles (user_id, handle, display_name, bio, avatar_url, is_private, created_at, updated_at)
SELECT
  ('a0000000-0000-4000-8000-' || lpad(g::text, 12, '0'))::uuid,
  lower(p.firsts[g]),
  p.firsts[g] || ' ' || p.lasts[g],
  p.bios[1 + (g % array_length(p.bios, 1))],
  'https://i.pravatar.cc/300?img=' || (1 + (g % 70)),
  false,
  now() - (g || ' days')::interval,
  now() - (g || ' days')::interval
FROM generate_series(1, 40) AS g, pool AS p
ON CONFLICT (user_id) DO NOTHING;

-- 2) Follow graph among demo profiles (each follows 6 others → ~6 followers) --
INSERT INTO follows (follower_id, followee_id, created_at)
SELECT
  ('a0000000-0000-4000-8000-' || lpad(g::text, 12, '0'))::uuid,
  ('a0000000-0000-4000-8000-' || lpad((((g + k - 1) % 40) + 1)::text, 12, '0'))::uuid,
  now() - ((g * 7 + k) || ' hours')::interval
FROM generate_series(1, 40) AS g, (VALUES (1), (2), (3), (5), (8), (13)) AS o(k)
ON CONFLICT DO NOTHING;

-- 3) Enrich REAL (non-seed) users so their own Profile looks populated --------
WITH reals AS (
  SELECT user_id, row_number() OVER (ORDER BY created_at) AS rn
  FROM profiles
  WHERE user_id::text NOT LIKE 'a0000000-0000-4000-8000-%'
)
UPDATE profiles p SET
  display_name = CASE WHEN p.display_name = ''
                 THEN (ARRAY['Dmitrij Cek','Alex Rivera','Sam Traveler'])[1 + ((r.rn - 1) % 3)]
                 ELSE p.display_name END,
  handle       = CASE WHEN p.handle = '' THEN 'traveler_' || r.rn ELSE p.handle END,
  bio          = CASE WHEN p.bio = '' THEN 'Plan it. Map it. Share it.' ELSE p.bio END,
  avatar_url   = CASE WHEN p.avatar_url = ''
                 THEN 'https://i.pravatar.cc/300?img=' || (1 + ((r.rn * 7) % 70))
                 ELSE p.avatar_url END,
  updated_at   = now()
FROM reals r
WHERE p.user_id = r.user_id;

-- 4) Give each real user 18 following + 15 followers from the demo pool -------
INSERT INTO follows (follower_id, followee_id, created_at)
SELECT r.user_id, s.user_id, now() - (s.rn || ' hours')::interval
FROM (SELECT user_id FROM profiles
      WHERE user_id::text NOT LIKE 'a0000000-0000-4000-8000-%') r
CROSS JOIN (
  SELECT user_id, row_number() OVER (ORDER BY created_at DESC) AS rn
  FROM profiles WHERE user_id::text LIKE 'a0000000-0000-4000-8000-%'
) s
WHERE s.rn <= 18
ON CONFLICT DO NOTHING;

INSERT INTO follows (follower_id, followee_id, created_at)
SELECT s.user_id, r.user_id, now() - (s.rn || ' hours')::interval
FROM (SELECT user_id FROM profiles
      WHERE user_id::text NOT LIKE 'a0000000-0000-4000-8000-%') r
CROSS JOIN (
  SELECT user_id, row_number() OVER (ORDER BY created_at) AS rn
  FROM profiles WHERE user_id::text LIKE 'a0000000-0000-4000-8000-%'
) s
WHERE s.rn <= 15
ON CONFLICT DO NOTHING;

COMMIT;
