-- Anyday Football — add favorite club/players/nations to player_profiles.
-- Run this once in the Supabase SQL Editor, after schema.sql has already been run.
--
-- These are freely editable, unlike match_ratings — no one-edit lock, a player can update their
-- favorites as many times as they want. The existing "self update player_profiles" RLS policy
-- (auth.uid() = id) already covers these new columns with no changes needed.

alter table player_profiles add column if not exists favorite_club text;
alter table player_profiles add column if not exists favorite_players text[];
alter table player_profiles add column if not exists favorite_nations text[];

-- Keep each list capped at 3 even if someone calls the API directly rather than going through
-- the site's form (which already limits input to 3 fields).
alter table player_profiles drop constraint if exists favorite_players_max_3;
alter table player_profiles add constraint favorite_players_max_3
  check (favorite_players is null or cardinality(favorite_players) <= 3);

alter table player_profiles drop constraint if exists favorite_nations_max_3;
alter table player_profiles add constraint favorite_nations_max_3
  check (favorite_nations is null or cardinality(favorite_nations) <= 3);
