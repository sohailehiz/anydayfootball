// Anyday Football — scheduled account auto-provisioner (Supabase Edge Function).
//
// Triggered every 4 days by pg_cron (see ../../auto_provision.sql). Finds every regular
// (more than 3 games played, per the players_missing_account view) who doesn't have a
// player_profiles row yet, creates a real login for them via the Auth Admin API (synthetic
// email + random password), and stashes the password in pending_signups so you can relay it.
//
// This runs entirely inside Supabase's infrastructure — the service_role key it uses never
// touches the browser or the static site. Only pg_cron (from inside your own project) is meant
// to be able to call it; see the CRON_SECRET check below.
//
// --- Deploy (run from your own machine — the Supabase CLI needs real network access) ---
//   1. Install the CLI if you don't have it:  npm install -g supabase
//   2. supabase login
//   3. supabase link --project-ref nszzhghwhevxcybzprlk
//   4. supabase functions deploy auto-provision-players --no-verify-jwt
//      (--no-verify-jwt because this is only ever called by your own cron job, not end users —
//      access is controlled by the CRON_SECRET check below instead)
//   5. Make up a long random string and set it as a secret:
//        supabase secrets set CRON_SECRET=<a long random string you make up>
//      Use that exact same string in the Authorization header in auto_provision.sql's
//      cron.schedule(...) call, then re-run that SQL so the schedule picks it up.
//
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY don't need to be set manually — Supabase injects
// those into every Edge Function's environment automatically.

import { createClient } from 'jsr:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const CRON_SECRET = Deno.env.get('CRON_SECRET');

function slugify(name: string): string {
  return name.toLowerCase().trim().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '');
}

function randomPassword(len = 10): string {
  // Avoids visually-confusing characters (0/O, 1/l/I) since these get read off a screen and
  // relayed to people over WhatsApp.
  const chars = 'ABCDEFGHJKMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
  const bytes = new Uint8Array(len);
  crypto.getRandomValues(bytes);
  let out = '';
  for (let i = 0; i < len; i++) out += chars[bytes[i] % chars.length];
  return out;
}

Deno.serve(async (req: Request) => {
  // Only our own cron job should ever successfully call this — CRON_SECRET must be set as a
  // function secret and must match what auto_provision.sql sends.
  const auth = req.headers.get('Authorization') || '';
  if (!CRON_SECRET || auth !== `Bearer ${CRON_SECRET}`) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' }
    });
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false }
  });

  const { data: missing, error } = await supabase
    .from('players_missing_account')
    .select('name, games_played');

  if (error) {
    return new Response(
      JSON.stringify({ error: `Failed to read players_missing_account: ${error.message}` }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }

  if (!missing || missing.length === 0) {
    return new Response(
      JSON.stringify({ message: 'No regulars missing an account.', created: 0, failed: 0 }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );
  }

  // Process everyone concurrently rather than one at a time — with dozens of players, sequential
  // awaits (create user -> insert profile -> save password, per person) can take well past
  // pg_net's default 5s timeout. Running them in parallel keeps total time close to whatever the
  // single slowest player takes, not the sum of all of them.
  const outcomes = await Promise.all(missing.map(async (row) => {
    const name = row.name as string;
    const email = `${slugify(name)}@anydayfootball.internal`;
    const password = randomPassword();

    const { data: user, error: createErr } = await supabase.auth.admin.createUser({
      email,
      password,
      email_confirm: true
    });
    if (createErr) {
      return { name, ok: false, detail: `failed: ${createErr.message}` };
    }

    const { error: profileErr } = await supabase.from('player_profiles').insert({
      id: user.user.id,
      name
    });
    if (profileErr) {
      return { name, ok: false, detail: `partial: auth user created, profile insert failed: ${profileErr.message}` };
    }

    await supabase
      .from('pending_signups')
      .upsert({ name, temp_password: password, notified: false }, { onConflict: 'name' });

    return { name, ok: true, detail: 'created' };
  }));

  const results: Record<string, string> = {};
  let created = 0, failed = 0;
  for (const o of outcomes) {
    results[o.name] = o.detail;
    if (o.ok) created++; else failed++;
  }

  return new Response(JSON.stringify({ created, failed, results }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' }
  });
});
