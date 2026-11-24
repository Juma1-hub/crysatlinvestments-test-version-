# CRYSTAL INVESTMENTS — backend readiness checkpoint (24 November 2026)

## Source of truth

This checkpoint is based on the 23 November 2026 archive `crysatlinvestments-test-version--main.zip` (184 entries) and the read-only live Supabase diagnostics collected in the 23–24 November project conversation. This project is separate from SUPA AI.

## Current architecture

- Active frontend: Next.js 15 / React 19 under `app/` and `components/`.
- Backend: Supabase Auth, Postgres tables, RLS and `SECURITY DEFINER` RPCs.
- Browser client uses only the Supabase publishable/anon key. No service-role key is used in browser code.
- Active investor/admin records are loaded from Supabase. No browser `localStorage` or `sessionStorage` is used in active `app/`, `components/` or `lib/` source.
- Supabase Edge Function source is included for M-Pesa STK initiation, M-Pesa callback query/verification, and protected daily accrual. KYC uploads use a private Supabase Storage bucket with owner-only and KYC-reviewer read policies.

## Agreed rules implemented in this revision

- New account and transaction currency is KES only. Historical USD/GBP financial rows remain in their original currency and are not converted or deleted.
- Registration defaults country to Kenya and validates Kenyan phone formats beginning `+254`, `07` or `01`.
- Investor overview displays a KES zero balance when no KES balance row exists; it does not display a fabricated zero when the balance RPC fails.
- Daily income is read from recorded daily accrual rows. The new accrual RPC calculates completed Kenya-local days and splits days at exact interest-rate effective timestamps using the selected 360/365 basis.
- Interest rate changes take effect at the exact server save timestamp. The RPC ignores client-supplied backdated/future timestamps. Previously recorded accruals are not rewritten.
- The eight agreed investment divisions are inserted as Draft opportunities if absent; no division is activated by the migration. The public division list is read through a Supabase RPC and does not expose draft investment status.
- Investor KYC upload and reviewer workflows use a private storage bucket, authenticated owner policies, signed URLs for reviewers and audited AAL2 review actions.
- Branch records are managed through permission-checked RPCs; deactivation is soft and retains the row.
- Daily accrual processing writes idempotent verified `interest` earnings, which trigger a single 20% referral commission when the investor has a referrer. Referral commission payout remains manual and requires a verified provider reference plus an audited AAL2 confirmation. Deposits, principal, realised profit and unrelated income types do not qualify for new commissions.
- Manual verification is enforced as always enabled in transaction-processing settings. Automatic mode is disabled until a trusted provider capability and real processing adapter are deployed and verified.
- Supa Admin Clear view controls do not delete database records; support archive is a separate audited archive operation.
- Distribution approval is separate from payout confirmation. `Paid` requires a provider event or an independently verified manual confirmation, AAL2 and an atomic ledger/audit post.
- Legacy admin helper functions are standardized on `crystal_admin_memberships` in the draft incremental migration.

## Critical live-database findings

- The live database has two admin membership systems. `admin_memberships` was empty; `crystal_admin_memberships` contained the active Supa Admin and Junior Admin.
- Broad permissive RLS policies bypassed some module-specific permissions.
- Authenticated users had direct INSERT/UPDATE/DELETE/TRUNCATE privileges on `investment_distributions`.
- Distribution RPCs expected by the active frontend were missing from the live database.
- The live integrated-financial-controls migration was incomplete: 12 of 13 expected columns were missing in the earlier comparison. The new draft migration adds the missing fields without rewriting historical financial rows.
- The KES 7 trillion approved deposit had no matching ledger credit. The KES 7 approved withdrawal had no matching ledger debit. Neither anomaly has been automatically credited/debited or otherwise changed.
- Investment allocations were pending; investment opportunities and site configuration were empty at the time of diagnostics.
- Live project migration history was not available in the expected project migration-history table.

## Current fail-closed controls

The new draft migration revokes authenticated execution of legacy deposit approval, withdrawal approval/payout, allocation and on-demand accrual mutation RPCs until the unmatched historical records are resolved and the integrated eight-division workflow is safely deployed. KES withdrawal request submission is available with a server-side balance/reservation check, but it does not debit funds or complete a payout. Deposit approval and withdrawal payout buttons remain paused. Distribution management is implemented separately in the draft migration.

## Not yet production-ready

- `202611240001_live_security_and_processing_controls.sql` has NOT been applied to Supabase.
- The migration has not been tested against a clone of the live database or executed by PostgreSQL.
- The M-Pesa Edge Function source is included but requires Daraja credentials, callback URL, deployment and sandbox testing. Callback verification records evidence but does not approve/credit a deposit.
- No bank payout adapter is included.
- The daily accrual Edge Function source is included, but no scheduler/cron invocation has been configured.
- Automatic financial approval/allocation is not enabled. The eight-division workflow still needs a schema-aware incremental integration and independent review after reconciliation.
- The full Next.js production build has not been verified because dependency installation timed out in this environment. A TypeScript/JSX syntax transpilation check passed for all 58 source files, and 23 static project-rule checks passed.

Do not deploy financial operations or apply the draft migration until the live backup, schema preflight, independent bank/provider reconciliation, migration clone test and explicit user approval are complete.
