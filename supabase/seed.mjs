// Anyday Football — one-time (re-runnable) data loader.
//
// Reads data/historical.json + every file in data/matches/ + data/player-aliases.json,
// normalizes names through the alias map, and loads everything into Supabase.
//
// This uses the service_role key, which bypasses Row Level Security — that's intentional and
// safe *as long as you only ever run this from your own machine*. Never put the service_role
// key in any of the .html files or commit it to git; it belongs only in your local .env.
//
// Setup:
//   cd supabase
//   npm install
//   cp .env.example .env        (then fill in SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY)
//   node seed.mjs
//
// Safe to re-run: it wipes the matches/players/dropouts tables and reloads them fresh from the
// JSON files each time, so it always ends up matching what's on disk. player_aliases is upserted
// (not wiped) so it doesn't clash with anything. player_profiles / match_ratings are never
// touched by this script — those are created by real players logging in, not by seeding.

import { createClient } from '@supabase/supabase-js';
import { readFileSync, readdirSync, existsSync } from 'fs';
import { fileURLToPath } from 'url';
import path from 'path';
import 'dotenv/config';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DATA_DIR = path.join(__dirname, '..', 'data');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY.');
  console.error('Copy supabase/.env.example to supabase/.env and fill both in, then re-run.');
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false }
});

function loadJson(p, fallback) {
  try { return JSON.parse(readFileSync(p, 'utf8')); }
  catch (e) { console.warn(`Could not read ${p}: ${e.message}`); return fallback; }
}

function buildAliasMap(list) {
  const map = new Map();
  (list || []).forEach(a => { if (a && a.alias && a.canonical) map.set(a.alias, a.canonical); });
  return map;
}

async function main() {
  const aliases = loadJson(path.join(DATA_DIR, 'player-aliases.json'), []);
  const aliasMap = buildAliasMap(aliases);
  const normalize = n => aliasMap.get(n) || n;

  const historical = loadJson(path.join(DATA_DIR, 'historical.json'), []);

  const matchesDir = path.join(DATA_DIR, 'matches');
  let newMatches = [];
  if (existsSync(matchesDir)) {
    const files = readdirSync(matchesDir).filter(f => f.toLowerCase().endsWith('.json'));
    for (const f of files) {
      const chunk = loadJson(path.join(matchesDir, f), []);
      newMatches = newMatches.concat(chunk);
      console.log(`Loaded ${chunk.length} match(es) from data/matches/${f}`);
    }
  }

  const allMatches = historical.concat(newMatches);
  console.log(`\nTotal matches to load: ${allMatches.length} (${historical.length} historical + ${newMatches.length} from data/matches/)`);

  // ---- 1. Upsert player_aliases ----
  if (aliases.length) {
    const rows = aliases.map(a => ({
      alias: a.alias,
      canonical: a.canonical,
      note: a.note || null,
      merged_on: a.merged || null
    }));
    const { error } = await supabase.from('player_aliases').upsert(rows, { onConflict: 'alias' });
    if (error) throw new Error(`player_aliases upsert failed: ${error.message}`);
    console.log(`Upserted ${rows.length} player_aliases row(s).`);
  }

  // ---- 2. Wipe existing match data (cascades to match_players / match_dropouts) ----
  const { error: delErr } = await supabase.from('matches').delete().neq('id', '00000000-0000-0000-0000-000000000000');
  if (delErr) throw new Error(`Failed to clear matches table: ${delErr.message}`);
  console.log('Cleared existing matches (and cascaded match_players/match_dropouts).');

  // ---- 3. Insert matches, then their players/dropouts ----
  let loadedMatches = 0, loadedPlayers = 0, loadedDropouts = 0;

  for (const m of allMatches) {
    const { data: inserted, error: mErr } = await supabase
      .from('matches')
      .insert({
        match_date: m.date,
        yr: m.yr,
        wd: m.wd || null,
        grp: m.grp || null,
        loc: m.loc || null,
        match_time: m.time || null,
        total: m.total ?? null,
        per_head: m.perHead ?? null
      })
      .select('id')
      .single();
    if (mErr) { console.error(`Failed to insert match ${m.date}: ${mErr.message}`); continue; }
    loadedMatches++;
    const matchId = inserted.id;

    const playerRows = (m.p || []).map(p => ({
      match_id: matchId,
      name: normalize(p.n),
      raw_name: p.n,
      is_guest: !!p.g,
      guest_number: p.g ?? null,
      guest_name: p.gn || null,
      late_fee: !!p.l,
      fee_amount: p.f ?? null
    }));
    if (playerRows.length) {
      const { error: pErr } = await supabase.from('match_players').insert(playerRows);
      if (pErr) console.error(`Failed to insert players for match ${m.date}: ${pErr.message}`);
      else loadedPlayers += playerRows.length;
    }

    const dropoutRows = (m.d || []).map(d => ({
      match_id: matchId,
      name: normalize(d.n),
      raw_name: d.n,
      fee_amount: d.f ?? null
    }));
    if (dropoutRows.length) {
      const { error: dErr } = await supabase.from('match_dropouts').insert(dropoutRows);
      if (dErr) console.error(`Failed to insert dropouts for match ${m.date}: ${dErr.message}`);
      else loadedDropouts += dropoutRows.length;
    }
  }

  console.log(`\nDone. Loaded ${loadedMatches} matches, ${loadedPlayers} player rows, ${loadedDropouts} dropout rows.`);
}

main().catch(e => { console.error(e); process.exit(1); });
