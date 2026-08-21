# Chicken Dinner V5 — multiplayer backend foundation

V5 takes the prototype toward a real shared game.

## Added
- Supabase Auth-ready data model
- Real users/profiles
- Gameweeks with a hard lock timestamp
- Fixtures and predictions
- Home / Draw / Away scoring
- One Booster per gameweek enforced in PostgreSQL
- Correct Booster pick = 2 points
- Private leagues and members
- Global leaderboard view
- Server-side scoring function
- Supabase Edge Function scaffold for scoring finished fixtures
- Gameweek 1 seed data

Supabase supports Auth, Postgres, Realtime and Edge Functions for this architecture. Auth integrates with Row Level Security, and Edge Functions are the appropriate place for trusted server-side scoring/result ingestion. See the official docs: https://supabase.com/docs/guides/auth and https://supabase.com/docs/guides/functions/quickstart-dashboard

## Setup
1. Create a Supabase project.
2. Run `supabase/schema.sql` in SQL Editor.
3. Copy `config.example.js` to `config.js` and add the project URL + publishable key.
4. Deploy the `supabase/functions/score-fixtures` Edge Function.
5. Feed finished Premier League results into `fixtures` from a trusted server/API, then invoke the scoring function.
6. Never expose a service-role/secret key in the browser.

## Important
The existing `index.html` is still the polished prototype UI. The next frontend integration should replace its localStorage persistence with Supabase queries while keeping the local fallback for demos.
