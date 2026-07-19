-- Anyday Football — migrate match_ratings to the 4-stat self-rating system.
-- Run this once in the Supabase SQL Editor, after schema.sql has already been run.
--
-- Replaces the old single generic "rating" column with four separate stats (stamina, passing,
-- speed, dribbling), each 1-10, entered by a player about their own performance in a specific
-- match. Also adds an "edited" flag so a rating can be corrected exactly once and then locks —
-- enforced here at the database level via RLS, not just hidden in the UI, so it can't be
-- bypassed by calling the API directly.

alter table match_ratings drop column if exists rating;

alter table match_ratings add column if not exists stamina int check (stamina between 1 and 10);
alter table match_ratings add column if not exists passing int check (passing between 1 and 10);
alter table match_ratings add column if not exists speed int check (speed between 1 and 10);
alter table match_ratings add column if not exists dribbling int check (dribbling between 1 and 10);
alter table match_ratings add column if not exists edited boolean not null default false;
alter table match_ratings add column if not exists updated_at timestamptz;

-- Make sure a freshly-inserted row actually has all four stats filled in (they were previously
-- optional as far as the table was concerned, since the single "rating" column covered it).
alter table match_ratings alter column stamina set not null;
alter table match_ratings alter column passing set not null;
alter table match_ratings alter column speed set not null;
alter table match_ratings alter column dribbling set not null;

-- Replace the update policy: a player can only update their own rating, and only while it hasn't
-- been edited yet. The client's update call must set edited = true as part of the same
-- statement that makes the correction — after that, this policy's "edited = false" check fails
-- on any further attempt, so the row is locked regardless of what the client sends.
drop policy if exists "self update match_ratings" on match_ratings;
create policy "self update match_ratings" on match_ratings
  for update
  using (auth.uid() = player_id and edited = false)
  with check (auth.uid() = player_id);
