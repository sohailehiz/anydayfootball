# Anyday Football

A FIFA Ultimate Team-style player card platform for casual football groups (five-a-side, Sunday league, WhatsApp squads) — built as a single self-contained web app.

## Features

- **Registration** via a simulated WhatsApp flow (captures phone number) or standard web form
- **Admin approval queue** for new profiles, plus a **Group Roster** whitelist that auto-approves known phone numbers on registration
- **Profile builder**: name, avatar upload (defaults to a cartoon player), favorite player, up to 3 favorite clubs, favorite nation
- **Flippable FIFA-style card**: front shows live-computed overall rating, star rating, and tier (bronze → silver → gold → legendary); back reveals favorite player, nation, and clubs
- **Match logging**: self-review speed/stamina after each game, which rolls into a weighted season average and bumps overall
- **Community grid** of every approved player's card, ranked by overall — plus a permanent mascot card for "Anyday Bot"
- **Season stats**: match history, season averages, and a generated season report card

## Running it

This is a single HTML file with no build step and no server required.

- **Locally**: just open `index.html` in a browser
- **On GitHub Pages**: enable Pages on this repo (Settings → Pages → Deploy from branch → `main` → `/root`), and it'll be live at `https://<your-username>.github.io/<repo-name>/`

## Setting up shared data (Supabase)

By default, when hosted on GitHub Pages this app stores data in the browser's `localStorage` — meaning each person's data lives only on their own device, and nobody sees a shared community. To make it a real shared app across everyone's phones, connect it to a free Supabase project:

1. **Create a project** at [supabase.com](https://supabase.com) (free tier is plenty for this).
2. **Create the table.** In the Supabase dashboard, go to SQL Editor and run:
   ```sql
   create table kv_store (
     key text primary key,
     value text not null,
     updated_at timestamptz default now()
   );
   alter table kv_store enable row level security;
   create policy "public read" on kv_store for select using (true);
   create policy "public write" on kv_store for insert with check (true);
   create policy "public update" on kv_store for update using (true);
   create policy "public delete" on kv_store for delete using (true);
   ```
3. **Get your credentials.** In Settings → API, copy the **Project URL** and the **anon public** key.
4. **Edit `index.html`.** Near the top of the `<script>` block, replace:
   ```js
   const SUPABASE_URL = 'YOUR_SUPABASE_URL';
   const SUPABASE_ANON_KEY = 'YOUR_SUPABASE_ANON_KEY';
   ```
   with your actual values.
5. **Commit and push.** GitHub Pages will pick up the change automatically.

The footer at the bottom of the app tells you which storage mode is active, so you can confirm it switched from "Local demo mode" to "Connected to Supabase" once configured.

**Security note:** the policies above make the table fully open to anyone holding the anon key (which is visible in your public page's source, since this is a static site with no backend). That's fine for a casual friend-group app, but it means anyone could technically read or edit any player's data directly via the API. If that matters for your use case, the next step would be adding real authentication (e.g. Supabase Auth) and row-level policies scoped to each user instead of `using (true)`.

## Notes

- Data storage automatically adapts: inside a Claude artifact it uses Claude's shared storage API; when hosted standalone (e.g. GitHub Pages) it falls back to the browser's `localStorage`. Note that `localStorage` is per-browser/per-device — for a real shared community across everyone's phones, you'll eventually want a proper backend (Firebase, Supabase, or your own API) instead.
- The WhatsApp registration flow is simulated in-app for demo purposes. A production version needs the WhatsApp Business API (or a provider like Twilio) wired to a backend to actually register numbers from real WhatsApp messages.
