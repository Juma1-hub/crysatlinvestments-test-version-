-- CRYSTAL INVESTMENTS — READ-ONLY SUPABASE RECONCILIATION
-- Run this in Supabase SQL Editor before applying ANY additional migration.
-- Every statement below is SELECT-only. It does not insert, update, delete, alter, or drop data.

-- 1. Applied migration history (important: the repository contains duplicate 202611110002 prefixes).
select version, name
from supabase_migrations.schema_migrations
order by version, name;

-- 2. Relevant public tables and their columns/types/defaults/nullability.
select table_name, ordinal_position, column_name, data_type, udt_name,
       is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
  and table_name in (
    'investor_profiles','deposit_requests','withdrawal_requests',
    'investment_allocations','investment_opportunities','investor_ledger_entries',
    'investment_earnings','crystal_admin_memberships','admin_memberships',
    'crystal_admin_audit_log','admin_audit_logs','crystal_site_configuration',
    'platform_settings','crystal_market_conditions','referral_codes',
    'referral_relationships','referral_commissions','support_messages',
    'admin_conversations'
  )
order by table_name, ordinal_position;

-- 3. Row-level security state for the relevant tables.
select n.nspname as schema_name, c.relname as table_name,
       c.relrowsecurity as rls_enabled,
       c.relforcerowsecurity as rls_forced
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind in ('r','p')
  and c.relname in (
    'investor_profiles','deposit_requests','withdrawal_requests',
    'investment_allocations','investment_opportunities','investor_ledger_entries',
    'investment_earnings','crystal_admin_memberships','admin_memberships',
    'crystal_admin_audit_log','admin_audit_logs','crystal_site_configuration',
    'platform_settings','crystal_market_conditions'
  )
order by c.relname;

-- 4. Policies on those tables. Review for broad policies that could bypass junior-admin permissions.
select schemaname, tablename, policyname, permissive, roles,
       cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in (
    'investor_profiles','deposit_requests','withdrawal_requests',
    'investment_allocations','investment_opportunities','investor_ledger_entries',
    'investment_earnings','crystal_admin_memberships','admin_memberships',
    'crystal_admin_audit_log','admin_audit_logs','crystal_site_configuration',
    'platform_settings','crystal_market_conditions'
  )
order by tablename, policyname;

-- 5. Public functions/RPCs relevant to authentication, permissions, finance, referrals and site config.
select p.proname as function_name,
       pg_get_function_identity_arguments(p.oid) as arguments,
       pg_get_function_result(p.oid) as result_type,
       p.prosecdef as security_definer,
       p.provolatile as volatility,
       pg_get_userbyid(p.proowner) as owner,
       p.proconfig as function_settings
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and (
    p.proname ilike '%admin%' or p.proname ilike '%deposit%'
    or p.proname ilike '%withdraw%' or p.proname ilike '%allocation%'
    or p.proname ilike '%earning%' or p.proname ilike '%interest%'
    or p.proname ilike '%referral%' or p.proname ilike '%site_configuration%'
    or p.proname ilike '%market_condition%'
  )
order by p.proname, arguments;

-- 6. Triggers on relevant financial/security/configuration tables.
select event_object_table as table_name, trigger_name,
       event_manipulation, action_timing, action_orientation,
       action_statement
from information_schema.triggers
where trigger_schema = 'public'
  and event_object_table in (
    'investor_profiles','deposit_requests','withdrawal_requests',
    'investment_allocations','investment_opportunities','investor_ledger_entries',
    'investment_earnings','crystal_admin_memberships','crystal_site_configuration'
  )
order by event_object_table, trigger_name, event_manipulation;

-- 7. Constraints/indexes relevant to integrity and duplicate prevention.
select conrelid::regclass::text as table_name, conname,
       contype, pg_get_constraintdef(oid) as definition
from pg_constraint
where connamespace = 'public'::regnamespace
  and conrelid::regclass::text in (
    'public.deposit_requests','public.withdrawal_requests',
    'public.investment_allocations','public.investor_ledger_entries',
    'public.investment_earnings','public.crystal_admin_memberships',
    'public.crystal_site_configuration'
  )
order by table_name, conname;

-- 8. Counts only; no investor names, emails, payment references or destination details are exposed.
select 'deposit_requests' as table_name, count(*) as row_count from public.deposit_requests
union all select 'withdrawal_requests', count(*) from public.withdrawal_requests
union all select 'investment_allocations', count(*) from public.investment_allocations
union all select 'investor_ledger_entries', count(*) from public.investor_ledger_entries
union all select 'investment_earnings', count(*) from public.investment_earnings
union all select 'crystal_admin_memberships', count(*) from public.crystal_admin_memberships
union all select 'admin_memberships', count(*) from public.admin_memberships;

-- 9. Financial request status totals, grouped by currency/status (not account balances).
select 'deposits' as request_type, currency, status, count(*) as requests,
       sum(amount) as requested_total
from public.deposit_requests
group by currency, status
union all
select 'withdrawals', currency, status, count(*), sum(amount)
from public.withdrawal_requests
group by currency, status
order by request_type, currency, status;

-- 10. Allocation status totals by currency and division/project label.
select currency, status, project_name, count(*) as records, sum(amount) as amount_total
from public.investment_allocations
group by currency, status, project_name
order by currency, status, project_name;

-- 11. Ledger totals by currency and entry type. This is a diagnostic summary, not a reconciled balance.
select currency, entry_type, count(*) as entries, sum(amount) as amount_total
from public.investor_ledger_entries
group by currency, entry_type
order by currency, entry_type;

-- 12. Admin role summary without user identifiers.
select role, is_active, count(*) as memberships
from public.crystal_admin_memberships
group by role, is_active
order by role, is_active;

-- 13. Site configuration keys only; do not export config values that may contain private settings.
select config_key, updated_at
from public.crystal_site_configuration
order by config_key;
