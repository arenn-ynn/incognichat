# Relaydrop deployment guide

Follow in order. This guide assumes a Mac with Terminal and a browser.

## 1. Prepare the files

Extract `relaydrop.zip` and open Terminal in the extracted `relaydrop` folder. Install Node.js 20.19+ if necessary. Run:

```bash
npm install
```

## 2. Create Supabase project

1. Visit https://supabase.com/dashboard and sign in.
2. Select **New project**, choose an organization, name and region, set a strong database password, and create the project.
3. Under **Authentication → Providers → Anonymous Sign-Ins** (the dashboard label can vary), enable anonymous sign-ins. If CAPTCHA is offered, enable it before public launch.
4. Open **SQL Editor → New query**, paste the entire contents of `supabase/migrations/001_init.sql`, and click **Run**. This creates tables, RPC functions, RLS policies, and the private Storage bucket.
5. Under **Database → Replication / Publications**, enable the `supabase_realtime` publication for `public.conversations` and `public.messages` if not enabled. Alternatively run:

```sql
alter publication supabase_realtime add table public.conversations;
alter publication supabase_realtime add table public.messages;
```

If either table is already in the publication, do not add it again. The frontend also polls as a fallback.

## 3. Configure local environment

1. Supabase **Project Settings → API** (or **Connect → API Keys**) shows your Project URL and publishable key. The `anon` legacy key also works.
2. Copy the template:

```bash
cp .env.example .env
```

3. Edit `.env` and replace the example values:

```dotenv
VITE_SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
VITE_SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_OR_ANON_KEY
```

The URL and publishable key are safe for browser use **when RLS is correctly configured**. Never put a `service_role` or secret key into a `VITE_` variable, GitHub, or the frontend.

## 4. Test locally

```bash
npm run dev
```

Open the displayed localhost URL. Open the same URL in a separate browser profile/private window to create a second identity. Copy A's code into B, send an invitation, accept on A, and exchange messages and files. Refresh both tabs, verify messages, and export a conversation. To run a build check:

```bash
npm run build
```

## 5. Publish on GitHub

1. Create a repository at https://github.com/new. Do not add an initial README when creating it.
2. In Terminal, from the project folder:

```bash
git init
git add .
git commit -m "Initial Relaydrop MVP"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPOSITORY.git
git push -u origin main
```

Replace `YOUR_USERNAME` and `YOUR_REPOSITORY`. You may need to authenticate Git with GitHub CLI or a credential manager. `.env` is ignored by Git.

## 6. Deploy frontend on Vercel

1. Visit https://vercel.com/new and sign in.
2. Select **Import Git Repository**, authorize GitHub, and choose your repository.
3. Framework: **Vite**. Build command: `npm run build`. Output directory: `dist`.
4. Under **Environment Variables**, add `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` with the values from your `.env` file.
5. Select **Deploy**. Vercel will install dependencies and build the app. The included `vercel.json` handles SPA routing.
6. New pushes to `main` will trigger redeployment. Other branches can create preview deployments.
7. For a domain, use Vercel **Project → Settings → Domains** and follow the DNS instructions.

## 7. Schedule server-side cleanup (required)

The SQL migration defines a cleanup function but **does not automatically schedule it**. To remove expired attachments, deploy the provided Edge Function. It requires Supabase CLI (see https://supabase.com/docs/guides/local-development/cli/getting-started).

```bash
npx supabase login
npx supabase link --project-ref YOUR_PROJECT_REF
npx supabase secrets set CLEANUP_SECRET=YOUR_LONG_RANDOM_SECRET
npx supabase functions deploy cleanup --no-verify-jwt
```

Generate a long random secret locally with `openssl rand -hex 32`; do not commit it. Supabase automatically provides the function's `SUPABASE_URL` and service-role key in its runtime. The function endpoint is `https://YOUR_PROJECT_REF.supabase.co/functions/v1/cleanup`.

Schedule an **hourly POST request** to this endpoint through Supabase **Integrations → Cron / Database → Cron**, using `pg_cron` and `pg_net` with a secret stored in Supabase Vault. Consult the current Supabase Cron dashboard instructions for the exact UI because the labels change. The request must include header `x-cleanup-secret` matching `CLEANUP_SECRET`. Do **not** expose this secret in browser code. For example, after enabling `pg_net` and Vault, a privileged SQL administrator can schedule:

```sql
select cron.schedule('relaydrop-cleanup', '0 * * * *', $$
  select net.http_post(
    url := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/cleanup',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cleanup-secret', (select decrypted_secret from vault.decrypted_secrets where name='relaydrop_cleanup_secret' limit 1)
    ),
    body := '{}'::jsonb
  );
$$);
```

First add `relaydrop_cleanup_secret` to Supabase Vault using the same secret. Replace the project reference. If the Cron feature is unavailable on your plan, use an external scheduler that securely stores the header secret. **Do not publish until cleanup has been configured and tested.** The included cleanup function handles at most 500 expired conversations per run and 1,000 objects per user folder; larger-scale use needs pagination and stronger retry handling.

## 8. Troubleshooting

- **Anonymous sign-ins disabled:** enable them in Supabase Auth.
- **RPC not found:** rerun the SQL migration; check function names in the SQL Editor.
- **Permission denied:** confirm RLS policies and the authenticated session; never disable RLS to work around it.
- **No realtime updates:** verify the publication and use two profiles. Polling runs every 5–12 seconds.
- **File uploads fail:** check the private `attachments` bucket and its storage policies; file limit is 10 MB.
- **Blank page on Vercel:** inspect build logs, environment variables, and browser console.
- **New identity on browser reopen:** expected. A refresh within a session preserves the identity.
- **Expired data remains:** verify the cleanup Edge Function and Cron job logs.

## 9. Before public release

The app is an MVP and has not been independently audited. Add server-side rate limits on conversation requests and messages, bot protection for anonymous sign-ins, verified MIME-type handling, malware scanning, upload quotas, reliable storage pagination, monitoring, and a privacy policy. Six-character public codes are not secrets. There is no end-to-end encryption. Check Supabase and Vercel current free-tier limits and pricing before launch.
