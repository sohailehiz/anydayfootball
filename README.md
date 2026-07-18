# Anyday Football

A static site for the Anyday five-a-side group: a match archive/analytics dashboard and a FIFA-style player card gallery, both generated from shared match data. No backend, no build step — just HTML files and JSON, hostable on GitHub Pages.

## Pages

- **`index.html`** — landing page linking to the two tools below.
- **`anyday-match-archive.html`** — the match dashboard. Tabs for Matches, Players, Analytics, and **+ Add Match**.
- **`anyday-football.html`** — read-only gallery of FIFA-style player cards, auto-generated from match data for every player with more than one appearance. Cards flip to show games played, first/last game, and how the rating was calculated.

All three pages share a sticky top nav (Home / Players / Match Archive).

## Data model

- **`data/historical.json`** — the frozen archive (matches extracted from the group's WhatsApp chats). Both pages embed a copy of this as an offline fallback, so they still work if opened directly via `file://` or if the fetch fails.
- **`data/matches/`** — new match files added after the historical archive was frozen. Each file is a timestamped JSON array (`matches-YYYYMMDD-HHMMSS.json`) containing only the matches added in that batch — files are never overwritten, so multiple people can add matches independently without conflicts.
- On load, both pages auto-detect the GitHub repo from the page URL (`{username}.github.io/{repo}`), query the GitHub Contents API for everything in `data/matches/`, and merge those files with `historical.json` into the live dataset. If you're hosting on a custom domain, set the `GITHUB_REPO` constant near the top of each file's `<script>` block.

## Adding a match

1. Open **Match Archive → + Add Match**.
2. Paste the WhatsApp roster message (the "Day and Date / Time / Location / Total / Per Head / numbered player list" format) and click **✨ Parse message** — it fills in the date, location, time, cost, and player list automatically (mark late fees with `<+50>` or `(late)` in the message, no-shows with `<+100>` or `no show`). Or fill the fields in manually.
3. Click **Add match** to stage it, then **⬇ Download match file** to save a `matches-YYYYMMDD-HHMMSS.json` file.
4. Upload that file into the `data/matches/` folder on GitHub (via the GitHub website, or `git add`/`commit`/`push`). Once it's live, the dashboard and player cards will pick it up automatically for everyone.

Matches you add but haven't downloaded/uploaded yet only exist in your browser's memory — reloading the page discards them, so it's safe to experiment.

## Running it

No build step, no server required.

- **Locally**: open `index.html` (or any of the three pages) directly in a browser.
- **On GitHub Pages**: push this folder to a repo, enable Pages (Settings → Pages → Deploy from branch → `main` → `/root`), and it'll be live at `https://<your-username>.github.io/<repo-name>/`.

## Player ratings

Overall rating is attendance-based: `clamp(round(games played / 52 × 100), 1, 99)`. Speed and stamina are currently a flat placeholder (50) — a login system where each player can edit their own card and rate themselves after matches is planned but not yet built.

## Notes

- `data/new-matches.json` is unused/superseded by the `data/matches/` folder and can be deleted.
