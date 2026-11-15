# Fresh Supabase database — CRYSTAL INVESTMENTS

## Important distinction
This is a **new-project database installer**. It is not a remote database that has already been provisioned. OpenAI does not have your Supabase organization credentials, so you must create the new Supabase project in your own account and run the included SQL. Do not run this installer on your existing project: it is intended for a newly-created, empty project and does not copy the old project's financial records.

## Included database objects
The ordered migrations create the Auth-linked investor profile, referral attribution, admin memberships and permission functions, deposits, withdrawals, the eight fixed investment opportunities, allocations, ledger and daily accrual tables, support, admin conversations, audit records, website settings, market-condition records, RLS policies and privileged RPCs.

## Install
1. In Supabase, create a **new project** dedicated to CRYSTAL INVESTMENTS. Save its project URL and publishable/anon key privately.
2. Wait until the database is ready.
3. Open **SQL Editor → New query**.
4. Open `FRESH_DATABASE_INSTALL.sql`, copy its complete contents into SQL Editor and run it once.
5. If SQL Editor reports an error, stop. Do not run later sections selectively or repeat the entire file blindly. Save the exact error and ask for review first.
6. Run `VERIFY_FRESH_DATABASE.sql` and confirm every required object exists.
7. Add the new project's URL and publishable key to Vercel as `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` for Preview and Production. Never add a service-role key or database password to frontend environment variables or GitHub.
8. Configure Authentication → URL Configuration with your actual website origin and exact `/login`, `/reset-password` redirect URLs. Configure SMTP before inviting users.
9. Create your first Auth user through the normal signup/admin invitation process. Do not expose an administrator signup path. Provision the first Supa Admin using a trusted, private database-operator procedure after verifying the Auth user UUID. Do not paste passwords, service keys or database credentials into chat.

## Financial safety defaults
- Financial operations remain disabled until a Supa Admin deliberately enables them and all eight approved opportunities are Active for the relevant currency.
- All eight website divisions are the only allocation destinations; the integrated deposit approval RPC allocates 12.5% to each, with the final division receiving any rounding remainder.
- KES, USD and GBP remain separate currencies.
- Withdrawal requests reserve funds and approval reduces active allocation principal proportionally, with accrued earnings redemption as encoded in the integrated financial controls.
- The included fresh-install override removes the one-year accrual cap. It does not guarantee that historical accruals have been run or verified.
- Payment initiation, callback verification and settlement are not enabled by this SQL alone. M-Pesa Daraja credentials, callback URL, signature/receipt verification, reconciliation and live testing are separate prerequisites.

## Fresh install only — not an upgrade
The original migration directory is retained at `supabase/migrations/` and the legacy files are preserved at `supabase/legacy-reference/` for traceability. The clean, duplicate-free fresh-install sequence is in `supabase/fresh-install/migrations/`. The legacy alternate financial foundation migration is intentionally excluded from the fresh sequence because it creates a parallel, older admin model.

No existing Supabase data is imported. If you want the existing project's investor/financial records moved to this new project, that must be a separate audited migration with source/target reconciliation and explicit approval. Do not export or import blindly.
