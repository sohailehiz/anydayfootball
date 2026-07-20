-- Anyday Football — drop dead columns.
-- Run this once in the Supabase SQL Editor, after schema.sql has already been run.
--
-- player_profiles.stamina / player_profiles.speed were leftover from an early design where a
-- player had one flat stat pair on their profile, before the real per-match rating system
-- (match_ratings: stamina/passing/speed/dribbling per match, self-rated) was built. Nothing in
-- the codebase has ever read or written these two columns — every insert into player_profiles
-- only sets id and name, relying on these columns' defaults. Safe to drop.

alter table player_profiles drop column if exists stamina;
alter table player_profiles drop column if exists speed;
