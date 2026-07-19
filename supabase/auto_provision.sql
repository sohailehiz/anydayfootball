-- Anyday Football — auto-provisioning infrastructure
-- Run this once in the Supabase SQL Editor, after schema.sql.
--
-- This sets up the database side of "automatically create a login for any player who doesn't
-- have one yet, on a schedule, without a button on the site." The actual account-creation logic
-- (which needs the service_role key) lives in a separate Edge Function — see the note at the
-- bottom. This script just gives that function what it needs: a way to find who's missing an
-- account, somewhere private to stash each new temporary password, and the schedule itself.

-- ============================================================
-- 1. Who's missing an account?
-- Any name that shows up in match data but has no matching player_profiles row — restricted to
-- regulars (more than 3 games played), so one-off guests don't get accounts auto-created.
-- Uses count(distinct match_id), not count(*): a player who brought guests has multiple
-- match_players rows under their own name in the same match (one per guest slot), so counting
-- raw rows would inflate their games-played number. Counting distinct matches matches the same
-- de-dupe logic used everywhere else in the site (see playerStats()/playerCounts() in the HTML).
-- ============================================================
create or replace view players_missing_account as
select mp.name, count(distinct mp.match_id) as games_played
from match_players mp
left join player_profiles pp on pp.name = mp.name
where pp.name is null
group by mp.name
having count(distinct mp.match_id) > 3
order by mp.name;

-- ============================================================
-- 2. Where newly auto-created passwords get stashed.
-- RLS is enabled with *zero* policies on purpose: that makes this table completely invisible to
-- the browser (publishable key) and to any logged-in player. Only the service_role key — used by
-- the scheduled Edge Function, never shipped to any browser — can read or write it, since
-- service_role bypasses RLS entirely. You'll check this table yourself in the Supabase dashboard
-- (Table Editor) to see temp passwords you still need to hand out, then mark them notified.
-- ============================================================
create table if not exists pending_signups (
  id bigserial primary key,
  name text not null unique,
  temp_password text not null,
  created_at timestamptz not null default now(),
  notified boolean not null default false
);
alter table pending_signups enable row level security;

-- ============================================================
-- 3. Make sure the scheduler + outbound-HTTP extensions are on. These ship enabled by default on
-- Supabase projects, but it's safe to re-assert.
-- ============================================================
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

-- ============================================================
-- 4. The actual schedule: calls the Edge Function every 4 days.
-- The function itself is at supabase/functions/auto-provision-players/index.ts — deploy that
-- first (see the instructions at the top of that file). Then replace <CRON_SECRET> below with
-- the exact same random string you set via `supabase secrets set CRON_SECRET=...` when deploying
-- it — this is what proves to the function that the call really came from your own cron job,
-- since the function is deployed with --no-verify-jwt. It is NOT your service_role key; the
-- function reads that separately, from its own auto-injected environment.
-- ============================================================
select cron.schedule(
  'auto-provision-players-every-4-days',
  '0 3 */4 * *',   -- 03:00 UTC, every 4th day
  $$
  select net.http_post(
    url := 'https://nszzhghwhevxcybzprlk.functions.supabase.co/auto-provision-players',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer <CRON_SECRET>'
    ),
    body := '{}'::jsonb
  );
  $$
);

-- ============================================================
-- Useful queries while setting this up / checking on it later
-- ============================================================
-- See who's still missing an account right now:
--   select * from players_missing_account;
-- See temp passwords waiting to be handed out:
--   select * from pending_signups where notified = false;
-- See what's scheduled:
--   select * from cron.job;
-- See run history / catch failures:
--   select * from cron.job_run_details order by start_time desc limit 20;
-- Pause or remove the schedule later:
--   select cron.unschedule('auto-provision-players-every-4-days');

-- ============================================================
-- Next piece (not in this file): the Edge Function itself, which on each run:
--   1. Reads players_missing_account.
--   2. For each name, generates a random password, creates the auth user via
--      supabase.auth.admin.createUser({ email: `${slug}@anydayfootball.internal`, password, ... }),
--      inserts the matching player_profiles row, and records the password in pending_signups.
-- I can write that function next — say the word and I'll generate it plus the exact deploy steps.
-- ============================================================
