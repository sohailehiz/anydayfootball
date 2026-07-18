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

## Notes

- Data storage automatically adapts: inside a Claude artifact it uses Claude's shared storage API; when hosted standalone (e.g. GitHub Pages) it falls back to the browser's `localStorage`. Note that `localStorage` is per-browser/per-device — for a real shared community across everyone's phones, you'll eventually want a proper backend (Firebase, Supabase, or your own API) instead.
- The WhatsApp registration flow is simulated in-app for demo purposes. A production version needs the WhatsApp Business API (or a provider like Twilio) wired to a backend to actually register numbers from real WhatsApp messages.
