-- PMapa message-service seed. Gives the real user real conversations (direct +
-- a group) with demo peers, message history, a reaction and read cursors, so
-- the Inbox / Chat screens render server data instead of SampleData.
--
-- Parameter:  :ruser — the real user's auth UUID.
-- Idempotent: fixed ids + ON CONFLICT DO NOTHING.
--
-- direct_key must match the service's canonical pair key
-- (store.DirectKey = sorted "a|b"), so the app dedups to the same conversation.
-- Demo peers: a0000000-0000-4000-8000-0000000000NN (1=Elena 2=Marco 3=Aiko 5=Sofia).

BEGIN;

-- Helper: peer UUID text for index n → 'a0000000-…-00000000000n'.
-- (inlined below as `'a0000000-0000-4000-8000-' || lpad(n::text,12,'0')`)

-- ── Direct conversations (ruser ↔ each peer) ─────────────────────────────────
INSERT INTO conversations (id, kind, title, created_by, direct_key, created_at, updated_at)
SELECT
  format('seed-dm-%s-%s', :'ruser', d.peer),
  'direct', '', :'ruser'::uuid,
  -- store.DirectKey = sorted "a|b" by Go byte comparison → force C collation.
  CASE WHEN (:'ruser' COLLATE "C") < (pu.uid COLLATE "C")
       THEN :'ruser' || '|' || pu.uid
       ELSE pu.uid || '|' || :'ruser' END,
  now() - (d.ord || ' days')::interval,
  now() - (d.mins || ' minutes')::interval
FROM (VALUES (1, 3, 2), (2, 2, 60), (3, 5, 180), (5, 4, 1440)) AS d(peer, ord, mins),
     LATERAL (SELECT 'a0000000-0000-4000-8000-' || lpad(d.peer::text, 12, '0') AS uid) pu
ON CONFLICT (id) DO NOTHING;

-- ── Group conversation "Kyoto Crew" (ruser + peers 1,2,3) ────────────────────
INSERT INTO conversations (id, kind, title, created_by, created_at, updated_at)
VALUES (format('seed-grp-%s-kyoto', :'ruser'), 'group', 'Kyoto Crew',
        :'ruser'::uuid, now() - interval '3 days', now() - interval '10 minutes')
ON CONFLICT (id) DO NOTHING;

-- ── Memberships ──────────────────────────────────────────────────────────────
-- Real user in every seeded conversation.
INSERT INTO members (conversation_id, user_id, joined_at)
SELECT c.id, :'ruser'::uuid, c.created_at
FROM conversations c
WHERE c.id LIKE 'seed-dm-' || :'ruser' || '-%'
   OR c.id = format('seed-grp-%s-kyoto', :'ruser')
ON CONFLICT DO NOTHING;

-- The peer in each direct chat.
INSERT INTO members (conversation_id, user_id, joined_at)
SELECT format('seed-dm-%s-%s', :'ruser', peer),
       ('a0000000-0000-4000-8000-' || lpad(peer::text, 12, '0'))::uuid,
       now() - interval '3 days'
FROM (VALUES (1),(2),(3),(5)) AS d(peer)
ON CONFLICT DO NOTHING;

-- Peers 1,2,3 in the group.
INSERT INTO members (conversation_id, user_id, joined_at)
SELECT format('seed-grp-%s-kyoto', :'ruser'),
       ('a0000000-0000-4000-8000-' || lpad(peer::text, 12, '0'))::uuid,
       now() - interval '3 days'
FROM (VALUES (1),(2),(3)) AS d(peer)
ON CONFLICT DO NOTHING;

-- ── Messages: direct chat with Elena (peer 1) ────────────────────────────────
INSERT INTO messages (id, conversation_id, author_id, body, created_at, updated_at)
SELECT format('seed-msg-%s-dm1-%s', :'ruser', m.n),
       format('seed-dm-%s-1', :'ruser'),
       CASE WHEN m.mine THEN :'ruser'::uuid
            ELSE ('a0000000-0000-4000-8000-' || lpad(1::text, 12, '0'))::uuid END,
       m.body, now() - (m.mins || ' minutes')::interval, now() - (m.mins || ' minutes')::interval
FROM (VALUES
  (1, false,'Hey! Are you still heading to Kyoto next week?', 40),
  (2, true, 'Yes! Booked the ryokan yesterday 🎉', 38),
  (3, false,'Amazing. I found a tiny ramen spot near Gion you have to try.', 30),
  (4, true, 'Adding it to the route right now.', 25),
  (5, false,'See you in Kyoto next week! 🌸', 2)
) AS m(n, mine, body, mins)
ON CONFLICT (id) DO NOTHING;

-- ── Messages: direct chat with Marco (peer 2) ────────────────────────────────
INSERT INTO messages (id, conversation_id, author_id, body, created_at, updated_at)
SELECT format('seed-msg-%s-dm2-%s', :'ruser', m.n),
       format('seed-dm-%s-2', :'ruser'),
       CASE WHEN m.mine THEN :'ruser'::uuid
            ELSE ('a0000000-0000-4000-8000-' || lpad(2::text, 12, '0'))::uuid END,
       m.body, now() - (m.mins || ' minutes')::interval, now() - (m.mins || ' minutes')::interval
FROM (VALUES
  (1, false,'Sent you the Lisbon route 🙌', 120),
  (2, true, 'Legend, thank you! Looks perfect.', 118),
  (3, false,'Let me know if you want the food spots too.', 90)
) AS m(n, mine, body, mins)
ON CONFLICT (id) DO NOTHING;

-- ── Messages: group "Kyoto Crew" ─────────────────────────────────────────────
INSERT INTO messages (id, conversation_id, author_id, body, created_at, updated_at)
SELECT format('seed-msg-%s-grp-%s', :'ruser', m.n),
       format('seed-grp-%s-kyoto', :'ruser'),
       CASE WHEN m.author = 0 THEN :'ruser'::uuid
            ELSE ('a0000000-0000-4000-8000-' || lpad(m.author::text, 12, '0'))::uuid END,
       m.body, now() - (m.mins || ' minutes')::interval, now() - (m.mins || ' minutes')::interval
FROM (VALUES
  (1, 1,'Flights are booked! Landing in Osaka on the 12th.', 200),
  (2, 2,'Nice — I land an hour later, let''s share a taxi.', 190),
  (3, 0,'Perfect. I''ll pin the meeting point at the station.', 180),
  (4, 3,'Adding the tea ceremony to our route 🍵', 60),
  (5, 2,'Booked the ryokan! 🎌', 10)
) AS m(n, author, body, mins)
ON CONFLICT (id) DO NOTHING;

-- ── A reaction (👍 from ruser on Elena's latest) ─────────────────────────────
INSERT INTO reactions (message_id, user_id, emoji, created_at)
VALUES (format('seed-msg-%s-dm1-5', :'ruser'), :'ruser'::uuid, '👍', now() - interval '1 minute')
ON CONFLICT DO NOTHING;

-- ── Read cursors: mark the real user caught up on the group; leave the two
--    DMs slightly behind so an unread badge shows. ─────────────────────────────
INSERT INTO read_cursors (conversation_id, user_id, read_at)
VALUES
  (format('seed-grp-%s-kyoto', :'ruser'), :'ruser'::uuid, now()),
  (format('seed-dm-%s-1', :'ruser'),      :'ruser'::uuid, now() - interval '20 minutes'),
  (format('seed-dm-%s-2', :'ruser'),      :'ruser'::uuid, now())
ON CONFLICT (conversation_id, user_id) DO NOTHING;

COMMIT;
