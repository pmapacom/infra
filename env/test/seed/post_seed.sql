-- PMapa post-service seed. Populates the feed + own posts + engagement so the
-- Posts screen, the followees feed, likes/saves/comments render real data.
--
-- Parameter:  :ruser  — the real user's auth UUID.
-- Idempotent: fixed ids + ON CONFLICT DO NOTHING.
--
-- Demo authors are the deterministic user-seed peers
-- (a0000000-0000-4000-8000-0000000000NN). The real user follows ~18 of them
-- (user_seed.sql), so their posts fill the "Following" feed.

BEGIN;

-- ── Feed pool: posts authored by demo peers (global, run once) ───────────────
INSERT INTO posts (id, author_id, type, body, place, image_url, created_at, updated_at)
SELECT
  format('seed-post-demo-%s', p.n),
  ('a0000000-0000-4000-8000-' || lpad(p.peer::text, 12, '0'))::uuid,
  p.type, p.body, p.place, p.img,
  now() - (p.n || ' hours')::interval, now() - (p.n || ' hours')::interval
FROM (VALUES
  (1, 2,'post','Sunset over Kyoto 🌇 Absolutely unreal from Kiyomizu-dera.','Kyoto, Japan','https://images.unsplash.com/photo-1493976040374-85c8e12f0c0e?w=600'),
  (2, 5,'recommendation','Tiny ramen spot near Gion — go early, queues fast.','Kyoto, Japan','https://images.unsplash.com/photo-1557872943-16a5ac26437e?w=600'),
  (3, 1,'route','Lisbon in 3 days: Alfama → Belém → Sintra day-trip.','Lisbon, Portugal','https://images.unsplash.com/photo-1585208798174-6cedd86e019a?w=600'),
  (4, 8,'post','Morning trail above Interlaken. Worth every step.','Interlaken, Switzerland','https://images.unsplash.com/photo-1531366936337-7c912a4589a7?w=600'),
  (5, 3,'recommendation','Best espresso in Rome is a hole in the wall near Pantheon.','Rome, Italy','https://images.unsplash.com/photo-1552832230-c0197dd311b5?w=600'),
  (6, 6,'post','Street food crawl in Bangkok 🍜','Bangkok, Thailand','https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=600'),
  (7, 4,'route','Iceland ring road, 7 days — the stops that were actually worth it.','Iceland','https://images.unsplash.com/photo-1504829857797-ddff29c27927?w=600'),
  (8, 9,'post','Cherry blossoms finally peaked in Tokyo 🌸','Tokyo, Japan','https://images.unsplash.com/photo-1540959733332-eab4deabeeaf?w=600'),
  (9, 7,'recommendation','Skip the tourist gondola — walk the back canals in Venice.','Venice, Italy','https://images.unsplash.com/photo-1514890547357-a9ee288728e0?w=600'),
  (10,10,'post','Northern lights, finally! Tromsø delivered.','Tromsø, Norway','https://images.unsplash.com/photo-1483347756197-71ef80e95f73?w=600'),
  (11, 2,'post','A slow morning in Lisbon ☕','Lisbon, Portugal','https://images.unsplash.com/photo-1585208798174-6cedd86e019a?w=600'),
  (12, 5,'route','Kyoto temple loop by bike — map inside.','Kyoto, Japan','https://images.unsplash.com/photo-1493976040374-85c8e12f0c0e?w=600')
) AS p(n, peer, type, body, place, img)
ON CONFLICT (id) DO NOTHING;

-- ── The real user's own posts (Posts screen → "My posts") ────────────────────
INSERT INTO posts (id, author_id, type, body, place, image_url, created_at, updated_at)
SELECT
  format('seed-post-own-%s-%s', :'ruser', p.n),
  :'ruser'::uuid, p.type, p.body, p.place, p.img,
  now() - (p.n || ' days')::interval, now() - (p.n || ' days')::interval
FROM (VALUES
  (1,'post','Back from Rome and already planning the next one. 🇮🇹','Rome, Italy','https://images.unsplash.com/photo-1552832230-c0197dd311b5?w=600'),
  (2,'route','My European Summer route: Paris → Lyon → Rome.','France → Italy','https://images.unsplash.com/photo-1502602898657-3e91760cbb34?w=600'),
  (3,'recommendation','The little café near Montmartre with the best pain au chocolat.','Paris, France','https://images.unsplash.com/photo-1509042239860-f550ce710b93?w=600'),
  (4,'post','Counting down to Japan in spring 🌸','Tokyo, Japan','https://images.unsplash.com/photo-1540959733332-eab4deabeeaf?w=600')
) AS p(n, type, body, place, img)
ON CONFLICT (id) DO NOTHING;

-- ── Likes on the real user's posts, from demo peers (like counts > 0) ────────
INSERT INTO likes (post_id, user_id, created_at)
SELECT format('seed-post-own-%s-%s', :'ruser', p.n),
       ('a0000000-0000-4000-8000-' || lpad(k::text, 12, '0'))::uuid,
       now() - (k || ' hours')::interval
FROM generate_series(1, 4) AS p(n),
     generate_series(1, 9) AS k       -- peers 1..9 like each own post
ON CONFLICT DO NOTHING;

-- ── The real user likes a few feed posts ─────────────────────────────────────
INSERT INTO likes (post_id, user_id, created_at)
SELECT format('seed-post-demo-%s', n), :'ruser'::uuid, now() - (n || ' hours')::interval
FROM (VALUES (1),(3),(8)) AS s(n)
ON CONFLICT DO NOTHING;

-- ── Saved posts (Posts screen → saved) ───────────────────────────────────────
INSERT INTO saves (post_id, user_id, created_at)
SELECT format('seed-post-demo-%s', n), :'ruser'::uuid, now() - (n || ' hours')::interval
FROM (VALUES (2),(5),(7),(9)) AS s(n)
ON CONFLICT DO NOTHING;

-- ── Comments on the real user's posts, from demo peers ───────────────────────
INSERT INTO comments (id, post_id, author_id, body, created_at)
SELECT format('seed-cmt-%s-%s', c.post_n, c.peer),
       format('seed-post-own-%s-%s', :'ruser', c.post_n),
       ('a0000000-0000-4000-8000-' || lpad(c.peer::text, 12, '0'))::uuid,
       c.body, now() - (c.mins || ' minutes')::interval
FROM (VALUES
  (1, 2,'So jealous — Rome is the best!', 30),
  (1, 5,'Which neighbourhood did you stay in?', 20),
  (2, 3,'Saving this route for August 🙌', 55),
  (3, 8,'Need the name of that café!', 12),
  (4, 9,'You are going to love the blossoms 🌸', 5)
) AS c(post_n, peer, body, mins)
ON CONFLICT (id) DO NOTHING;

COMMIT;
