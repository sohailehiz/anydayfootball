-- Anyday Football — profile picture support.
-- Run this once in the Supabase SQL Editor, after schema.sql has already been run.
--
-- Adds an avatar_url column to player_profiles, plus a public "avatars" Storage bucket with
-- policies so a player can only upload/replace/delete their own photo (stored under a folder
-- named after their own auth user id), while anyone can view any photo (cards are public).

alter table player_profiles add column if not exists avatar_url text;

-- Storage bucket. Public so card images load directly via URL with no auth needed, same as the
-- rest of the site's public-read data.
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

-- Anyone can view any avatar (cards are public).
drop policy if exists "public read avatars" on storage.objects;
create policy "public read avatars" on storage.objects
  for select using (bucket_id = 'avatars');

-- A player can only write files inside a folder named after their own user id, e.g.
-- "<user-id>/avatar.jpg" — the client code enforces this path, and this policy enforces it
-- again at the database level so it can't be bypassed by calling the Storage API directly.
drop policy if exists "self insert avatars" on storage.objects;
create policy "self insert avatars" on storage.objects
  for insert with check (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);

drop policy if exists "self update avatars" on storage.objects;
create policy "self update avatars" on storage.objects
  for update using (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);

drop policy if exists "self delete avatars" on storage.objects;
create policy "self delete avatars" on storage.objects
  for delete using (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);
