#!/usr/bin/env bash
# Seed the local dev stack with REAL data across every domain (except the shop)
# so the app's screens — Profile, Connections, Discover, Timeline, Trip details,
# Visited, Posts + feed, Inbox + Chat, Notifications — render real backend data
# instead of the app's SampleData.
#
# Prereq: the root stack is up (`docker compose up -d`) AND you have registered
#         and logged in at least once in the app (so a real user exists). The
#         per-user content is attached to every real (non-demo) user found.
# Usage:  env/test/seed/seed.sh
#
# Idempotent: every insert uses fixed ids + ON CONFLICT DO NOTHING, so it is safe
# to re-run (e.g. after registering a new account).
set -euo pipefail
cd "$(dirname "$0")/../../.."   # repo root
SEED_DIR="env/test/seed"

# Run a .sql file inside a service's postgres container.
#   run_sql <compose-service> <db-user> <db-name> <sql-file> [extra psql args…]
run_sql() {
  local svc=$1 dbuser=$2 dbname=$3 file=$4; shift 4
  docker compose exec -T "$svc" \
    psql -U "$dbuser" -d "$dbname" -v ON_ERROR_STOP=1 "$@" < "$file"
}

echo "1/2  user profiles + follow graph…"
run_sql user-postgres user user "$SEED_DIR/user_seed.sql"

# Discover the real (non-demo) users to attach content to.
# (while-read, not mapfile — portable to the bash 3.2 that ships with macOS.)
REALS=()
while IFS= read -r _id; do
  [ -n "$_id" ] && REALS+=("$_id")
done < <(docker compose exec -T user-postgres \
  psql -U user -d user -tA -c \
  "SELECT user_id FROM profiles
   WHERE user_id::text NOT LIKE 'a0000000-0000-4000-8000-%'
   ORDER BY created_at")

if [ "${#REALS[@]}" -eq 0 ]; then
  echo
  echo "⚠  No real users yet — the demo profiles/discover graph are seeded, but"
  echo "   there is no account to attach trips/posts/chats/notifications to."
  echo "   Register + log in once in the app, then re-run this script."
  exit 0
fi

echo "2/2  content for ${#REALS[@]} real user(s): ${REALS[*]}"
for RU in "${REALS[@]}"; do
  echo "   • $RU"
  run_sql travel-postgres       travel       travel       "$SEED_DIR/travel_seed.sql"       -v ruser="$RU"
  run_sql post-postgres         post         post         "$SEED_DIR/post_seed.sql"         -v ruser="$RU"
  run_sql message-postgres      message      message      "$SEED_DIR/message_seed.sql"      -v ruser="$RU"
  run_sql notification-postgres notification notification "$SEED_DIR/notification_seed.sql" -v ruser="$RU"
done

echo "--- counts ---"
docker compose exec -T user-postgres         psql -U user         -d user         -c "SELECT (SELECT count(*) FROM profiles) profiles, (SELECT count(*) FROM follows) follows;"
docker compose exec -T travel-postgres       psql -U travel       -d travel       -c "SELECT (SELECT count(*) FROM trips) trips, (SELECT count(*) FROM visited) visited;"
docker compose exec -T post-postgres         psql -U post         -d post         -c "SELECT (SELECT count(*) FROM posts) posts, (SELECT count(*) FROM comments) comments;"
docker compose exec -T message-postgres      psql -U message      -d message      -c "SELECT (SELECT count(*) FROM conversations) conversations, (SELECT count(*) FROM messages) messages;"
docker compose exec -T notification-postgres psql -U notification -d notification -c "SELECT count(*) AS notifications FROM notifications;"

echo "✓ Seed complete. Shop/store data is intentionally NOT seeded."
