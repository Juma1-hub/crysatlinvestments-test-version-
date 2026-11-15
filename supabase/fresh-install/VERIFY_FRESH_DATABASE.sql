-- Read-only verification for a newly installed CRYSTAL INVESTMENTS Supabase database.
with required_objects(object_name, object_type) as (
 values
 ('investor_profiles','table'),('crystal_admin_memberships','table'),
 ('deposit_requests','table'),('withdrawal_requests','table'),
 ('investment_allocations','table'),('investment_opportunities','table'),
 ('investor_ledger_entries','table'),('investment_daily_accruals','table'),
 ('investment_earnings','table'),('referral_relationships','table'),
 ('referral_commissions','table'),('crystal_admin_audit_log','table'),
 ('crystal_admin_conversations','table'),('crystal_support_messages','table'),
 ('crystal_site_configuration','table'),('market_condition_updates','table')
)
select r.object_name,r.object_type,
 case when to_regclass('public.'||r.object_name) is not null then 'PRESENT' else 'MISSING' end as status
from required_objects r order by r.object_name;

select division,status,supported_currencies
from public.investment_opportunities
where division in (
 'Energy & Petroleum','Agriculture & Agribusiness','Real Estate & Infrastructure',
 'Mining & Minerals','Shipping & Logistics','Technology & Innovation',
 'Global Markets & Securities','General Investments & Acquisitions'
)
order by array_position(array[
 'Energy & Petroleum','Agriculture & Agribusiness','Real Estate & Infrastructure',
 'Mining & Minerals','Shipping & Logistics','Technology & Innovation',
 'Global Markets & Securities','General Investments & Acquisitions'
]::text[],division);

select
 to_regprocedure('public.crystal_admin_access()') is not null as admin_access_rpc_present,
 to_regprocedure('public.admin_review_financial_request(text,uuid,text)') is not null as financial_review_rpc_present,
 to_regprocedure('public.investor_submit_withdrawal(numeric,text,jsonb)') is not null as withdrawal_submit_rpc_present,
 to_regprocedure('public.investor_get_account_balances()') is not null as investor_balances_rpc_present,
 to_regprocedure('public.crystal_accrue_investor_daily_earnings(uuid)') is not null as daily_interest_rpc_present;
