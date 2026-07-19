// Anyday Football — one-off (re-runnable) account provisioner.
//
// Finds every player from players_missing_account (regulars — more than 3 games played — who
// don't have a player_profiles row yet, per supabase/auto_provision.sql) and creates a real
// login for each: a synthetic email (name@anydayfootball.internal) and a random password,
// using the Auth Admin API. This is the same logic the scheduled Edge Function will eventually
// run automatically — for now it's a script you run by hand whenever you want to catch up any
// new regulars.
//
// Setup (same as seed.mjs — if you already ran that, this reuses the same supabase/.env):
//   cd supabase
//   npm install          (only needed once)
//   node auto_provision.mjs
//
// Safe to re-run: it only acts on players_missing_account, which excludes anyone who already
// has a player_profiles row, so it never touches an existing account.

import { createClient } from '@supabase/supabase-js';
import 'dotenv/config';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY.');
  console.error('Make sure supabase/.env has both set (same file seed.mjs uses).');
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false }
});

function slugify(name) {
  return name.toLowerCase().trim().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '');
}

function randomPassword(len = 10) {
  // Avoids visually-confusing characters (0/O, 1/l/I) since these get read off a screen and
  // relayed to people over WhatsApp.
  const chars = 'ABCDEFGHJKMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
  let out = '';
  for (let i = 0; i < len; i++) out += chars[Math.floor(Math.random() * chars.length)];
  return out;
}

async function main() {
  const { data: missing, error } = await supabase
    .from('players_missing_account')
    .select('name, games_played');
  if (error) throw new Error(`Failed to read players_missing_account: ${error.message}. Did you run supabase/auto_provision.sql yet?`);

  if (!missing || !missing.length) {
    console.log('No regulars (>3 games) missing an account. Nothing to do.');
    return;
  }

  console.log(`Found ${missing.length} player(s) missing an account:`);
  missing.forEach(m => console.log(`  - ${m.name} (${m.games_played} games)`));
  console.log('');

  let created = 0, failed = 0;

  for (const { name } of missing) {
    const email = `${slugify(name)}@anydayfootball.internal`;
    const password = randomPassword();

    const { data: user, error: createErr } = await supabase.auth.admin.createUser({
      email,
      password,
      email_confirm: true
    });
    if (createErr) {
      console.error(`FAILED — ${name}: could not create auth user (${createErr.message})`);
      failed++;
      continue;
    }

    const { error: profileErr } = await supabase.from('player_profiles').insert({
      id: user.user.id,
      name
    });
    if (profileErr) {
      console.error(`PARTIAL — ${name}: auth user created but player_profiles insert failed (${profileErr.message})`);
      failed++;
      continue;
    }

    const { error: pendingErr } = await supabase
      .from('pending_signups')
      .upsert({ name, temp_password: password, notified: false }, { onConflict: 'name' });
    if (pendingErr) console.error(`Note — ${name}: account created fine, but couldn't save temp password to pending_signups (${pendingErr.message})`);

    console.log(`Created — ${name}: temp password is ${password}`);
    created++;
  }

  console.log(`\nDone. ${created} account(s) created, ${failed} failed.`);
  console.log('Temp passwords are also saved in the pending_signups table if you need to look them up again later.');
}

main().catch(e => { console.error(e); process.exit(1); });
