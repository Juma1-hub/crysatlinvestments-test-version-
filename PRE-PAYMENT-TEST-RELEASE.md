# CRYSTAL INVESTMENTS — pre-payment integration test release

This bundle contains the Next.js frontend, Supabase database migrations, verification SQL, Supabase Edge Function source, and security/deployment documentation.

## Project rules preserved

- CRYSTAL INVESTMENTS remains separate from SUPA AI.
- Supabase is the authoritative backend; financial and account data must not be stored in browser storage.
- KES is the only currency for new accounts and transactions. Existing historic foreign-currency records are preserved.
- Manual review remains available alongside automatic processing. Manual review is always enabled in the processing settings; automatic processing is gated by verified provider capability.
- The eight agreed divisions remain the only investment destinations, with the agreed 12.5% equal allocation rule.
- Annual interest rates accrue daily on the agreed 360/365 basis; a new rate takes effect at its server-recorded effective timestamp.
- Referral commission is 20% of verified interest earnings only.
- Admin actions require database-side authorization, RLS/RPC enforcement, audit logging and AAL2 for sensitive actions.
- No financial record is deleted, overwritten, reset or silently adjusted.
- Secret keys remain server-side and `.env*` files are excluded from Git except `.env.example`.

## Included

- `app/`, `components/`, `lib/`, `public/`: Next.js frontend and browser Supabase client.
- `supabase/migrations/`: historical migration source plus the incremental live security/processing migration.
- `supabase/verification/`: read-only post-migration checks.
- `supabase/diagnostics/`: read-only financial reconciliation queries and guide.
- `supabase/functions/`: M-Pesa STK initiation, callback verification, and daily accrual Edge Function source.
- `SECURITY-AND-SETUP.md`, `LIVE-DATABASE-DEPLOYMENT.md`, `SUPABASE-SETUP.md`: setup and security instructions.

## Local frontend verification

1. Install Node.js 22 or later.
2. Run `npm install`.
3. Copy `.env.example` to `.env.local` and set only the browser-safe Supabase URL and publishable/anon key.
4. Run `npm run check:project-rules`.
5. Run `npx tsc --noEmit` and `npm run build`.
6. Keep `CRYSTAL_SITE_PUBLISHED=false` until you explicitly approve publication.

## Supabase verification and deployment

This project already has an existing live Supabase database. Do not run the fresh-install SQL against it. First take a backup, inspect actual migration history/schema, run the read-only diagnostics, test the incremental migration against a clone, and review every function/RLS/grant. Only then should an explicitly approved migration be applied. Run the verification SQL afterward.

The incremental migration file is `supabase/migrations/202611240001_live_security_and_processing_controls.sql`.

## Payment integration boundary

The M-Pesa Edge Function source is included, but live Daraja credentials, callback URL, deployment and sandbox tests are external setup steps. The callback records verified provider evidence; it does not itself approve a deposit or post a ledger credit. No bank payout adapter is included. Automatic processing must remain off until each real provider adapter is deployed and verified. Manual review must remain available.

## Financial safety boundary

The earlier live diagnostics found an approved KES 7 trillion deposit without a matching ledger credit and an approved KES 7 withdrawal without a matching ledger debit. Their existing request rows must be preserved. This release does not create a compensating credit/debit or rewrite either record. The user's confirmation that the deposit was manually approved is retained as context, but a ledger posting still requires a separately authorized, idempotent, audited reconciliation action.

The current migration intentionally revokes legacy financial approval/allocation functions rather than exposing unsafe legacy behavior. The deposit approval, withdrawal payout, eight-division allocation and live daily accrual paths are therefore not certified as operational against the live database in this release. Do not represent this package as a completed live-money system until the clone-tested migration and those end-to-end workflows pass.
