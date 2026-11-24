# CRYSTAL INVESTMENTS — Supabase-backed web application

This repository contains the active Next.js 15 / React 19 application, Supabase migrations, security controls, verification SQL, PWA assets and operational documentation. Older root-level prototype components are retained for traceability only; deploy the Next.js `app/` application, not those prototype files.

## Important

The live database has unresolved historical reconciliation issues. This revision keeps deposit approval, withdrawal payout, investment allocation and automatic processing fail-closed until the live ledger is reconciled and the reviewed incremental migration is deployed. KES deposit and withdrawal request submission includes server-side validation and idempotency; request submission does not post a ledger credit/debit or complete a payout. Do not use fresh-install SQL against an existing live database.

## Main application

- `app/` — public website, registration, login, investor and admin routes.
- `components/` — investor portal and admin modules.
- `lib/supabase.ts` — browser Supabase client using only the publishable/anon key.
- `supabase/migrations/` — ordered migration history and the new live security baseline.
- `supabase/verification/` — read-only post-deployment verification.
- `public/` — PWA manifest assets, service worker and offline page.

## Setup

1. Install dependencies with `npm install`.
2. Configure `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` in the deployment environment.
3. Do not place a Supabase service-role key or payment-provider secret in any `NEXT_PUBLIC_` variable.
4. Configure Supabase Auth redirect URLs for the production domain.
5. Keep `CRYSTAL_SITE_PUBLISHED=false` until public launch is explicitly approved; the middleware returns 404 for public routes while unpublished. Set it to `true` only at launch.
6. Follow `LIVE-DATABASE-DEPLOYMENT.md` before applying any migration to the existing live database.
7. Run `npm run build` before deploying the frontend.

## Current safeguards

- KES is the only currency offered for new accounts and transactions.
- Historical foreign-currency financial rows are not converted or deleted.
- Referral commission is limited to 20% of verified interest earnings.
- Manual and automatic processing settings are separate; automatic mode remains disabled until a verified provider capability is registered.
- Distribution payout completion requires verified payment confirmation and an idempotent ledger/audit post.
- KYC documents use a private Supabase Storage bucket; reviewers receive short-lived signed links.
- Team and branch records use MFA-protected RPCs and soft deactivation.
- Unresolved deposit/withdrawal ledger discrepancies keep sensitive financial mutations disabled.

See `PROJECT-RULES-CHECKLIST.md` for the project decision checklist and outstanding blockers.
