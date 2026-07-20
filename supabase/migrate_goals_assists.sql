-- Anyday Football — goals/assists tracking.
-- Run this once in the Supabase SQL Editor, after schema.sql has already been run.
--
-- Adds goals/assists counters to match_players. Not populated by anything yet — the WhatsApp
-- roster parser recognizes an optional "g<N>"/"a<N>" shorthand per player (see
-- extractGoalsAssists() in anyday-match-archive.html) and seed.mjs will carry those values
-- through once a roster message actually uses it. Until then every player's totals are 0.

alter table match_players add column if not exists goals int not null default 0 check (goals >= 0);
alter table match_players add column if not exists assists int not null default 0 check (assists >= 0);
