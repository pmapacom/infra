# Dev data seed

Populates the **local dev stack** with realistic data across every domain
(**except the shop/store**) so the Flutter app renders real backend data instead
of the removed `SampleData` — Profile, Connections, Discover, Timeline, Trip
details, Visited, Posts + feed, Inbox + Chat, Notifications.

## Run

```bash
docker compose up -d           # stack must be healthy
# register + log in once in the app so a real account exists, then:
env/test/seed/seed.sh
```

The script is **idempotent** (fixed ids + `ON CONFLICT DO NOTHING`) — re-run it
any time, e.g. after registering another account.

## How it works

- `user_seed.sql` — ~40 demo profiles with deterministic UUIDs
  `a0000000-0000-4000-8000-0000000000NN`, a follow graph, and enrichment of every
  **real** (non-demo) user + their followers/following.
- `seed.sh` then finds each real user id and attaches per-user content:
  - `travel_seed.sql` — 2 trips + 5 visited countries + 5 visited cities.
  - `post_seed.sql` — a feed pool authored by followed demo peers, the user's own
    posts, plus likes / saves / comments.
  - `message_seed.sql` — 4 direct chats + a "Kyoto Crew" group, message history,
    a reaction and read cursors.
  - `notification_seed.sql` — the in-app activity feed (follow / like / comment /
    message.new / system).

Each service owns its own Postgres, so the real user's UUID (from `user-postgres`)
is passed to the other services via `psql -v ruser=…`. Travel `document`s are the
app's opaque client JSON (`Trip`/`Country`/`City` `toJson`); the message
`direct_key` matches `store.DirectKey` (sorted `a|b`, `COLLATE "C"`).

## Not seeded

The **shop / store** service is intentionally excluded — its screens keep the
app's built-in sample catalog for now.
