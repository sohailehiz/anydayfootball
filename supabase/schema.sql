-- Anyday Football — Supabase schema
-- Run this once in the Supabase SQL Editor (Dashboard → SQL Editor → New query) before running
-- the seed script. Safe to re-run: everything is CREATE ... IF NOT EXISTS / DROP POLICY IF EXISTS.

-- ============================================================
-- Matches (mirrors data/historical.json + data/matches/*.json)
-- ============================================================
create table if not exists matches (
  id uuid primary key default gen_random_uuid(),
  -- Deterministic key (date|time|loc|grp) so seed.mjs can upsert a match instead of deleting and
  -- reinserting it. That matters because match_ratings.match_id cascades on delete — if a match's
  -- id changed on every reseed, every player's self-ratings for that match would be silently
  -- wiped out each time the site owner reseeds (which happens routinely, e.g. after every new
  -- match or player-name merge). Keeping the same source data always resolves to the same row,
  -- and therefore the same id, across reseeds.
  source_key text not null unique,
  match_date date not null,
  yr text not null,
  wd text,                    -- weekday label as recorded in the source data (Sun/Wed/Fri...)
  grp text,                   -- 'm' (midweek) or 'w' (weekend)
  loc text,
  match_time text,
  total int,                  -- total cost for the match, null if unknown/estimated
  per_head int,               -- per-player cost, null if unknown/estimated
  created_at timestamptz default now()
);

-- Players who showed up (mirrors each match's "p" array)
create table if not exists match_players (
  id bigserial primary key,
  match_id uuid not null references matches(id) on delete cascade,
  name text not null,         -- canonical name, after alias normalization
  raw_name text not null,     -- name exactly as it appeared in the source data, for audit
  is_guest boolean not null default false,
  guest_number int,           -- the "g" field: nth guest brought by this inviter
  guest_name text,            -- the "gn" field: guest's real name, if recorded
  late_fee boolean not null default false,
  fee_amount int
);

-- Players who dropped out / no-showed (mirrors each match's "d" array)
create table if not exists match_dropouts (
  id bigserial primary key,
  match_id uuid not null references matches(id) on delete cascade,
  name text not null,
  raw_name text not null,
  fee_amount int
);

-- ============================================================
-- Player name merges — the auditable record described earlier (mirrors data/player-aliases.json)
-- ============================================================
create table if not exists player_aliases (
  id bigserial primary key,
  alias text not null unique,
  canonical text not null,
  note text,
  merged_on date
);

-- ============================================================
-- Player profiles — one per logged-in player, created the first time someone claims their name.
-- id matches auth.users.id (Supabase Auth). name is the canonical player name from match data.
-- ============================================================
create table if not exists player_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null unique,
  stamina int not null default 50 check (stamina between 1 and 99),
  speed int not null default 50 check (speed between 1 and 99),
  claimed_at timestamptz not null default now(),
  -- Freely editable cosmetic preferences, capped at 3 each — no lock, unlike match_ratings.
  favorite_club text,
  favorite_players text[] check (favorite_players is null or cardinality(favorite_players) <= 3),
  favorite_nations text[] check (favorite_nations is null or cardinality(favorite_nations) <= 3),
  avatar_url text
);

-- Public "avatars" Storage bucket for profile pictures — a player can only write files under a
-- folder named after their own user id (enforced below), but anyone can view any photo since
-- cards are public. See migrate_avatar.sql for the equivalent if upgrading an existing project.
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

drop policy if exists "public read avatars" on storage.objects;
create policy "public read avatars" on storage.objects
  for select using (bucket_id = 'avatars');

drop policy if exists "self insert avatars" on storage.objects;
create policy "self insert avatars" on storage.objects
  for insert with check (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);

drop policy if exists "self update avatars" on storage.objects;
create policy "self update avatars" on storage.objects
  for update using (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);

drop policy if exists "self delete avatars" on storage.objects;
create policy "self delete avatars" on storage.objects
  for delete using (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);

-- Per-match self-ratings (self-rating only, never peer-rated). Four stats per match, each 1-10.
-- "edited" tracks whether the player has already used their one allowed correction — see the RLS
-- policy below, which enforces the one-edit limit at the database level, not just in the UI.
-- (If you already ran an earlier version of this file with a single generic "rating" column,
-- use supabase/migrate_match_ratings.sql instead of re-running this block.)
create table if not exists match_ratings (
  id bigserial primary key,
  match_id uuid not null references matches(id) on delete cascade,
  player_id uuid not null references player_profiles(id) on delete cascade,
  stamina int not null check (stamina between 1 and 10),
  passing int not null check (passing between 1 and 10),
  speed int not null check (speed between 1 and 10),
  dribbling int not null check (dribbling between 1 and 10),
  edited boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  unique (match_id, player_id)
);

-- ============================================================
-- Row Level Security
-- Match/roster data and aliases are public read-only from the browser — all writes happen
-- through the seed script using the service_role key, which bypasses RLS entirely.
-- player_profiles / match_ratings are publicly readable (cards are public) but only the
-- matching logged-in player can write their own row.
-- ============================================================
alter table matches enable row level security;
alter table match_players enable row level security;
alter table match_dropouts enable row level security;
alter table player_aliases enable row level security;
alter table player_profiles enable row level security;
alter table match_ratings enable row level security;

drop policy if exists "public read matches" on matches;
create policy "public read matches" on matches for select using (true);

drop policy if exists "public read match_players" on match_players;
create policy "public read match_players" on match_players for select using (true);

drop policy if exists "public read match_dropouts" on match_dropouts;
create policy "public read match_dropouts" on match_dropouts for select using (true);

drop policy if exists "public read player_aliases" on player_aliases;
create policy "public read player_aliases" on player_aliases for select using (true);

drop policy if exists "public read player_profiles" on player_profiles;
create policy "public read player_profiles" on player_profiles for select using (true);

drop policy if exists "self insert player_profiles" on player_profiles;
create policy "self insert player_profiles" on player_profiles for insert with check (auth.uid() = id);

drop policy if exists "self update player_profiles" on player_profiles;
create policy "self update player_profiles" on player_profiles for update using (auth.uid() = id);

drop policy if exists "public read match_ratings" on match_ratings;
create policy "public read match_ratings" on match_ratings for select using (true);

drop policy if exists "self write match_ratings" on match_ratings;
create policy "self write match_ratings" on match_ratings for insert with check (auth.uid() = player_id);

-- A player can only update their own rating, and only while it hasn't been edited yet. The
-- client's update call must set edited = true as part of the same statement that makes the
-- correction — after that, "edited = false" fails on any further attempt, locking the row
-- regardless of what the client sends (real enforcement, not just a UI restriction).
drop policy if exists "self update match_ratings" on match_ratings;
create policy "self update match_ratings" on match_ratings
  for update
  using (auth.uid() = player_id and edited = false)
  with check (auth.uid() = player_id);

-- Helpful indexes
create index if not exists idx_match_players_match_id on match_players(match_id);
create index if not exists idx_match_players_name on match_players(name);
create index if not exists idx_match_dropouts_match_id on match_dropouts(match_id);
create index if not exists idx_matches_date on matches(match_date);
