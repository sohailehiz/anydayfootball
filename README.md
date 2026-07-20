# Anyday Football

A site for the Anyday five-a-side group: a match archive/analytics dashboard and a FIFA-style player card gallery, both generated from shared match data. Four static HTML pages (no build step, hostable on GitHub Pages) backed by a Supabase project for accounts, self-ratings, and favorites.

## Pages

- **`index.html`** — landing page linking to the tools below.
- **`anyday-match-archive.html`** — the match dashboard. Tabs for Matches, Players, Analytics, and **+ Add Match**.
- **`anyday-football.html`** — FIFA-style player cards, auto-generated from match data for every player with more than one appearance. Logged-in players land on their own card by default (`?all=1` shows the full gallery). Cards flip to show games played, skill score, favorite club, and top 3 players/nations.
- **`login.html`** — sign in, or create a password the first time you log in as a known player name.

All pages share a sticky top nav (Home / My Card or Players / Match Archive / Login or Log out).

## Data model

Match data lives in two places that are kept in sync:

- **JSON files (source of truth)** — `data/historical.json` (frozen archive) plus `data/matches/*.json` (one timestamped file per batch added since). Both HTML pages embed a copy of `historical.json` as an offline fallback so they still work over `file://` or if Supabase is unreachable.
- **Supabase (`matches`, `match_players`, `match_dropouts`)** — what the pages actually read from on a normal load. Populated from the JSON files by `supabase/seed.mjs`, which upserts each match onto a deterministic key (date+time+location+group) rather than wiping the table, so a match keeps the same database id across reseeds — that matters because `match_ratings` references it, and an earlier version of this script regenerated ids on every run, silently deleting everyone's self-ratings each time. See "Supabase backend" below if you're on an older project.

Login/rating/preference data lives only in Supabase, never in the JSON files:

- **`player_profiles`** — one row per player who's logged in (`id` = their Supabase Auth user id, `name` = canonical match-data name), plus their `favorite_club`, `favorite_players` (up to 3), `favorite_nations` (up to 3).
- **`match_ratings`** — a player's self-rated stamina/passing/speed/dribbling (1–10 each) for a specific match. Self-rating only; one correction allowed after the initial save, then the row locks (enforced by a Postgres RLS policy, not just the UI).
- **`player_aliases`** — the name-merge audit trail (see below).

Both `anyday-football.html` and `anyday-match-archive.html` try Supabase first and fall back to the embedded/fetched JSON if Supabase can't be reached.

## Adding a match

1. Open **Match Archive → + Add Match**.
2. Paste the WhatsApp roster message and click **✨ Parse message** — it fills in date, location, time, cost, and player list (mark late fees with `<+50>` or `(late)`, no-shows with `<+100>` or `no show`). Or fill the fields in manually.
3. Click **Add match** to stage it, then **⬇ Download match file** to save a `matches-YYYYMMDD-HHMMSS.json` file.
4. Commit that file into `data/matches/` and push.
5. Run the seed script (see below) so the new match actually shows up on the live pages — adding the JSON file alone only updates the offline fallback path, not the Supabase-backed data the pages load by default.

Matches you add but haven't downloaded yet only exist in your browser's memory — reloading the page discards them, so it's safe to experiment.

## Merging duplicate players (e.g. "Kush" vs "Kushal")

Do this whenever the same person shows up under two spellings.

1. Add an entry to `data/player-aliases.json`:
   ```json
   { "alias": "Kush", "canonical": "Kushal", "note": "same person, inconsistent spelling", "merged": "2026-07-19" }
   ```
2. Run the seed script (`cd supabase && node seed.mjs`). It upserts the alias into the `player_aliases` table and re-normalizes every `match_players`/`match_dropouts` row through the alias map as it reloads, so all past and future matches under either spelling attribute to the canonical name.
3. Reload the site and confirm the merged player now shows as a single card with the combined game count.

That's the whole process **as long as at most one of the two names has ever logged in.** `seed.mjs` only rewrites match data — it never touches `player_profiles` or `match_ratings`. If both names already have their own login accounts, reseeding will merge their match history under one name while their logins/ratings stay split (the alias account's card lookup breaks, its ratings end up orphaned). In that case, sort out which account should survive — reassign `match_ratings.player_id` and the favorites onto the canonical `player_profiles` row, delete the duplicate `auth.users` entry — before reseeding. Check who currently has an account before merging any pair.

## Running it

No build step, no server required for the front end.

- **Locally**: open `index.html` (or any page) directly in a browser.
- **On GitHub Pages**: push this folder to a repo, enable Pages (Settings → Pages → Deploy from branch → `main` → `/root`), and it'll be live at `https://<your-username>.github.io/<repo-name>/`.

## Supabase backend

Everything server-side lives under `supabase/`. One-time setup for a fresh Supabase project:

1. In the SQL Editor, run `schema.sql` — creates `matches`, `match_players`, `match_dropouts`, `player_aliases`, `player_profiles`, `match_ratings`, plus Row Level Security policies.
2. In Authentication → Sign In / Providers → Email, turn **off** "Confirm email". Player logins use synthetic addresses (`name@anydayfootball.internal`) that can never receive a real confirmation email, so self-signup won't work until this is off.
3. `cd supabase && npm install`, then `cp .env.example .env` and fill in `SUPABASE_URL` and the `service_role` secret key from Settings → API. Never commit `.env` (already in `.gitignore`).
4. `node seed.mjs` to load `data/historical.json` + `data/matches/*.json` into Supabase.
5. In each HTML page's `<script>` block, set `SUPABASE_URL` and the `anon`/`publishable` key (safe for client-side use — the secret key from step 3 must never go in an HTML file).

If you already have a running project and are just picking up new schema changes, run the relevant `migrate_*.sql` file instead of re-running all of `schema.sql` — `CREATE TABLE IF NOT EXISTS` is a no-op against tables that already exist, so a straight re-run won't apply new columns/policies and can error partway through:

- **`migrate_match_ratings.sql`** — adds the four-stat rating columns and the one-edit-lock policy.
- **`migrate_profile_favorites.sql`** — adds `favorite_club`/`favorite_players`/`favorite_nations` to `player_profiles`.
- **`migrate_stable_match_ids.sql`** — adds `source_key` to `matches` and a uniqueness constraint on it, so `seed.mjs` can upsert matches instead of wiping the table. Run this once if your project predates this fix (does not restore ratings already lost to a past reseed — only prevents future ones).
- **`migrate_avatar.sql`** — adds `avatar_url` to `player_profiles` and sets up a public `avatars` Storage bucket with policies so a player can only upload/replace/delete their own photo.
- **`migrate_goals_assists.sql`** — adds `goals`/`assists` counters to `match_players`. See "Goals and assists" below.

Other scripts in `supabase/`:

- **`auto_provision.sql`** — creates the `players_missing_account` view (regulars with >3 games and no login yet), the `pending_signups` table (holds temp passwords, service-role only), and a `pg_cron` job that calls the deployed Edge Function every 4 days to auto-create accounts for new regulars.
- **`functions/auto-provision-players/`** — the Edge Function itself; deployed via the Supabase Dashboard's "Via Editor" flow with "Verify JWT" turned off (it authenticates via a `CRON_SECRET` header instead).
- **`auto_provision.mjs`** — same logic as the Edge Function, runnable by hand instead of waiting on the schedule.
- **`reset_password.mjs`** — resets a player's password directly (`node reset_password.mjs "Name"`), for when a temp password from auto-provisioning goes missing.

## Player ratings

Overall rating = 30% attendance + 70% skill, clamped to 1–99:

- **Attendance score** = `this year's games played ÷ this year's total games recorded`, scaled to 0–99. Resets every calendar year rather than accumulating forever.
- **Skill score** = average of self-rated stamina/passing/speed/dribbling across every match a player has rated, scaled from 1–10 to 0–99. Defaults to a flat 30 until a player rates at least one match — not 0, so an unrated regular isn't penalized as if they have no skill at all.
- **Goals/assists** join the skill score as a 5th equally-weighted stat once the group actually starts tracking them (see "Goals and assists" below) — scored relative to whoever has the most combined goals+assists that year. Deliberately left out of the blend entirely (not defaulted to 30) until real data exists, so introducing this feature doesn't quietly lower everyone's rating before anyone's had a chance to use it.

Ratings are self-only (no peer rating), and only offered for matches from 2026-07-19 onward — there's no retroactive demand to rate the whole archive. A rating can be corrected once after the initial save; after that the row locks at the database level (RLS), not just in the UI.

## Player favorites

Logged-in players can set a favorite club and up to 3 favorite players/nations from the panel next to their card on the "My Card" view. Unlike ratings, these are freely re-editable — no lock, no limit on how many times they can be updated. Shown on the back of the player's card.

## Profile photo

From the same panel, a player can upload a profile photo (JPG/PNG/WebP, up to 3MB) that replaces the generated initials avatar on the front of their card everywhere it appears — their own card and the public gallery. Photos are stored in a public Supabase Storage bucket (`avatars`), one file per player at a fixed path keyed by their own user id, so re-uploading always replaces rather than accumulates files. A player can only write to their own path — enforced by Storage RLS policies, not just the UI.

## Goals and assists

The roster parser on the Add Match tab recognizes an optional `g<N>`/`a<N>` shorthand per player — e.g. `Sohail g2 a1` means 2 goals and 1 assist. Not currently used in the group's WhatsApp messages, so every player's total is 0 today, but it's fully wired up: parsed from pasted messages, editable by hand in the players field, carried through `seed.mjs` into `match_players.goals`/`match_players.assists`, totalled per player on the back of their card and in the Players tab, ranked in "Top 10 goal scorers" / "Top 10 assists" on the Analytics tab, and folded into the overall rating formula (see "Player ratings" above) once real data exists. Starts working the moment a roster message actually includes the tags — no further changes needed. Only applies to players who played; dropouts can't score.

## Notes

- `supabase/.env` and `supabase/node_modules/` are git-ignored — never commit the service_role secret key.
- `data/new-matches.json` is unused/superseded by the `data/matches/` folder and can be deleted if still present.
