-- Anyday Football — give matches a stable, deterministic key so reseeding stops destroying
-- everyone's self-ratings.
--
-- Why: seed.mjs used to delete every row from `matches` and reinsert them fresh on every run,
-- so each match got a brand-new random id each time. match_ratings.match_id references
-- matches(id) on delete cascade, so that delete cascaded straight through and wiped out every
-- player's saved stamina/passing/speed/dribbling ratings on every single reseed — not just once,
-- every time (new match added, player names merged, etc.). This was caught after a routine
-- reseed silently cleared ratings.
--
-- Fix: add a deterministic `source_key` (derived from date + time + location + group) and have
-- seed.mjs upsert matches on that key instead of wiping the table. Same source data always
-- resolves to the same row, so the id — and everything that references it — survives reseeding.
--
-- Run this once in the Supabase SQL Editor, after schema.sql has already been run. It does NOT
-- restore ratings that were already lost to a past reseed — only prevents future ones from
-- disappearing.

alter table matches add column if not exists source_key text;

-- Backfill existing rows. This only sets a new column — it does not touch `id`, so any
-- match_ratings rows that currently exist (i.e. saved since your last reseed) are untouched.
update matches
set source_key = concat_ws('|', match_date::text, coalesce(match_time, ''), coalesce(loc, ''), coalesce(grp, ''))
where source_key is null;

-- If this fails with a uniqueness violation, two of your existing matches share the exact same
-- date + time + location + group — find them with the query below and give seed.mjs's source
-- data a distinguishing detail (e.g. a slightly different time) before re-running this file:
--   select source_key, count(*) from matches group by source_key having count(*) > 1;
alter table matches alter column source_key set not null;
alter table matches drop constraint if exists matches_source_key_key;
alter table matches add constraint matches_source_key_key unique (source_key);
