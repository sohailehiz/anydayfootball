// Anyday Football — reset a player's login password.
//
// For when someone's forgotten/lost their password (or their temp password from
// auto-provisioning never made it into pending_signups). Looks up the player by name, generates
// a fresh random password, sets it directly on their existing auth account via the Admin API,
// and records it in pending_signups so it's there to look up.
//
// Usage (same setup as seed.mjs / auto_provision.mjs — reuses supabase/.env):
//   cd supabase
//   node reset_password.mjs "Sohail"
//
// Only works for a player who already has an account (a player_profiles row). If they don't
// have one yet, they should use the "create a password" flow on login.html instead.

import { createClient } from '@supabase/supabase-js';
import 'dotenv/config';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY.');
  console.error('Make sure supabase/.env has both set (same file seed.mjs uses).');
  process.exit(1);
}

const name = process.argv[2];
if (!name) {
  console.error('Usage: node reset_password.mjs "Player Name"');
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false }
});

function randomPassword(len = 10) {
  const chars = 'ABCDEFGHJKMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
  let out = '';
  for (let i = 0; i < len; i++) out += chars[Math.floor(Math.random() * chars.length)];
  return out;
}

async function main() {
  const { data: profile, error: profileErr } = await supabase
    .from('player_profiles')
    .select('id, name')
    .eq('name', name)
    .maybeSingle();

  if (profileErr) throw new Error(`Failed to look up player_profiles: ${profileErr.message}`);
  if (!profile) {
    console.error(`No account found for "${name}". They haven't logged in / been provisioned yet — use the "create a password" flow on login.html instead.`);
    process.exit(1);
  }

  const password = randomPassword();
  const { error: updateErr } = await supabase.auth.admin.updateUserById(profile.id, { password });
  if (updateErr) throw new Error(`Failed to update password: ${updateErr.message}`);

  const { error: pendingErr } = await supabase
    .from('pending_signups')
    .upsert({ name: profile.name, temp_password: password, notified: false }, { onConflict: 'name' });
  if (pendingErr) console.warn(`Password was reset, but couldn't save it to pending_signups: ${pendingErr.message}`);

  console.log(`Password reset for ${profile.name}: ${password}`);
}

main().catch(e => { console.error(e); process.exit(1); });
