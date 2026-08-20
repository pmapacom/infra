-- PMapa notification-service seed. Fills the real user's in-app activity feed
-- (Inbox → Notifications) with real rows so it renders server data, not
-- SampleData.activity.
--
-- Parameter:  :ruser — the real user's auth UUID (recipient).
-- Idempotent: fixed ids + ON CONFLICT DO NOTHING.
--
-- The app renders each row by `type`, resolves the actor's name/avatar from the
-- user service (demo peers a0000000-…), and reads `data.subtitle`/`data.preview`
-- for the second line (see notifications_controller._toActivity).
-- NOTE: `purchase` (marketplace) notifications are intentionally omitted — the
-- shop is out of scope for this seed.

BEGIN;

INSERT INTO notifications (id, user_id, type, actor_id, data, created_at, read)
SELECT
  format('seed-notif-%s-%s', :'ruser', a.n),
  :'ruser'::uuid,
  a.type,
  CASE WHEN a.peer = 0 THEN NULL
       ELSE ('a0000000-0000-4000-8000-' || lpad(a.peer::text, 12, '0'))::uuid END,
  a.data::jsonb,
  now() - (a.mins || ' minutes')::interval,
  a.mins > 240                       -- older than 4h → already read
FROM (VALUES
  (1,'follow',  1,'{}',                                                    2),
  (2,'follow',  4,'{}',                                                   65),
  (3,'like',    3,'{"subtitle":"Sunset over Kyoto 🌇"}',                300),
  (4,'like',    5,'{"subtitle":"Back from Rome and already planning…"}', 130),
  (5,'comment', 2,'{"subtitle":"Which neighbourhood did you stay in?"}',  20),
  (6,'comment', 8,'{"subtitle":"Need the name of that café!"}',           12),
  (7,'message.new', 1,'{"preview":"See you in Kyoto next week!"}',         2),
  (8,'system',  0,'{"title":"Achievement unlocked","subtitle":"10 Countries visited 🏆"}', 600)
) AS a(n, type, peer, data, mins)
ON CONFLICT (id) DO NOTHING;

COMMIT;
