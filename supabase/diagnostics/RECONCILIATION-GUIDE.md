# Supabase reconciliation — read-only first

The current repository includes migrations that may already have been applied to the live Crystal Investments database. The database also contains existing financial records. **Do not rerun old migrations, edit an applied migration, reset the project, or apply a corrective financial migration until the live schema and migration history have been reconciled.**

## First step

1. Open the existing Crystal Investments Supabase project.
2. Open **SQL Editor** and create a new query.
3. Paste the complete contents of `READ_ONLY_RECONCILIATION.sql`.
4. Run it. All statements are `SELECT` statements and are intended to be read-only.
5. Export or copy the result sets, especially migration history, columns, RLS policies, functions, triggers, counts and financial totals.
6. Share those results for review before any new SQL is executed.

## Why this is required

- Two repository files share the migration prefix `202611110002` (`financial_and_admin_foundation` and `referral_program`). The actual `schema_migrations` history determines what was applied; filenames alone do not.
- The live project has pre-existing deposits, withdrawals, allocations and ledger entries. They must be preserved and reconciled, not replaced by seed data or recalculated from request totals.
- The repository contains multiple generations of financial RPCs and policies. Their live definitions, ownership, `SECURITY DEFINER` settings, search paths, grants and policies must be checked before writing a forward-only correction.
- The inspection deliberately reports aggregate financial totals rather than exposing investor PII, payment references or withdrawal destinations.

## Non-negotiable safety

This file does not change the database. Do not execute any `INSERT`, `UPDATE`, `DELETE`, `ALTER`, `DROP`, `TRUNCATE`, or corrective migration until the inspection results have been reviewed and the proposed changes are explicitly approved.
