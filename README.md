# Relaydrop

A registration-free, temporary, two-person messaging and file-sharing MVP.

## Stack

React 19, TypeScript, Vite, Supabase Anonymous Auth, PostgreSQL with RLS, Supabase Storage, Supabase Realtime, and Vercel.

## Quick start

1. Create a Supabase project and enable anonymous sign-ins.
2. Run `supabase/migrations/001_init.sql` in the SQL Editor.
3. Copy `.env.example` to `.env` and supply your project URL and publishable/anon key.
4. Run `npm install` and `npm run dev`.
5. Open two separate browser profiles to test invitations and chat.

**Read `DEPLOYMENT.md` before deploying.** It includes infrastructure setup, scheduled cleanup, security notes, and testing.

## Features

- Six-character random public codes (not passwords)
- Session-only anonymous authentication, with no email or registration
- Invitation acceptance before chat access
- Real-time messages (Supabase changes when configured, polling fallback)
- Private 10 MB file uploads and downloads
- TXT, JSON, CSV, HTML, and ZIP exports
- Light/dark themes, mobile/desktop layouts
- Expiration enforcement and scheduled cleanup function

## Important limitations

This is an **unverified MVP**, not a security-audited production system. Before public launch, add rate limiting/CAPTCHA to code lookup and anonymous sign-in, malware scanning, upload validation, pagination, robust storage cleanup for large folders, and abuse monitoring. Supabase anonymous authentication must be explicitly enabled. Browser session lifecycle varies: sessionStorage may survive browser restore or be copied into duplicated tabs. There is no end-to-end encryption. Attachment upload progress currently reports stages, not byte-level progress.
