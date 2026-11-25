# CRYSTAL INVESTMENTS — delivery report (25 November 2026, continued work)

## Source package changes

- Added `supabase/migrations/202611250001_complete_financial_review_and_payout_workflows.sql`.
- Added read-only verification script `supabase/verification/VERIFY_FINANCIAL_WORKFLOWS_20261125.sql`.
- Added Vault-backed pg_cron schedule template and read-only verification for the daily earnings Edge Function.
- Added AAL2-protected manual deposit/withdrawal review RPC with server-side permission checks and audit records.
- Deposit approval atomically posts one KES ledger credit and creates eight equal active allocations, with an idempotency/conflict check against existing ledger and allocation records.
- Activated the eight agreed investment divisions for the unpublished test site; existing risk text is retained and the old `REVIEW_REQUIRED` seed marker/instruction is removed.
- Withdrawal approval now reserves the amount but does not debit the ledger. A separate manual payout confirmation requires a provider reference and independent verification note, then posts the debit and adjusts unallocated cash, principal and/or recorded interest.
- Added audited cancellation of approved unpaid withdrawals.
- Added unique payout-reference protection and separate review, payout and cancellation evidence fields.
- Updated investor withdrawal eligibility and balance summaries to use ledger-backed account value plus unredeemed interest less active reservations.
- Corrected the daily accrual worker's undeclared allocation variable reference.
- Kept automatic equal allocation enabled as a required internal workflow; external deposit/withdrawal automation remains gated until payment adapters are deployed and verified. Manual verification remains always on.
- Updated admin UI to use the new RPCs, expose confirm-payout/cancel actions and remove paused/unavailable workflow notices.
- Removed user-visible setup/migration/Supabase status copy from the active UI; public site publication gate remains in place.
- Added a Cloudflare Durable Object Auth rate-limit Worker, same-origin Auth proxy, Vercel origin-token enforcement and four executable Worker tests.
- Updated setup, deployment, readiness and release documentation.

## Verification performed

- `npm run check:project-rules`: **45/45 passed**.
- TypeScript/TSX syntax transpilation: **102 files, 0 syntax errors**.
- Cloudflare Worker tests: **5/5 passed**, including password-rate windows, refresh-token exemption and private origin-token forwarding.
- SQL delimiter/transaction structural checks: both incremental migrations have balanced `$$` delimiters and one `BEGIN`/`COMMIT` pair.
- Source ZIP contents and secret handling checked; no real credentials were added. `.env*` remains ignored except `.env.example`; Cloudflare `wrangler.toml` and `.wrangler/` are also ignored.
- Browser client continues to use only the publishable/anon key.

## Not verified in this environment

- PostgreSQL parser/execution and staging-clone migration tests: not run; no PostgreSQL server/client is available.
- `npm install --offline`: blocked because packages are not cached. Full semantic TypeScript check and Next.js production build therefore remain unverified.
- Live database migration, Edge Function deployment, provider sandbox tests and daily scheduler installation: not performed; the Vault/pg_cron setup template is included.
- No live Supabase records, settings, ledger rows, deposits, withdrawals or allocations were changed.

## Payment integration boundary

The core manual workflows are now present in source. Automatic M-Pesa deposit approval and automatic withdrawal payout still require provider adapters, verified callbacks/webhooks, idempotent provider-event handling, sandbox tests and deployment. The next stage is payment-provider integration after the database migrations pass on a staging clone.

## Historical record handling

The existing manually approved KES 7 trillion deposit and approved KES 7 withdrawal remain unchanged. This release does not automatically credit, debit, reverse or mark either as paid.

## Deployment status

This is an updated frontend/backend source test bundle, not a live deployment or a claim of production certification. Apply the two incremental migrations to a staging clone in order, run both verification scripts, and complete the application build and end-to-end tests before live use.
