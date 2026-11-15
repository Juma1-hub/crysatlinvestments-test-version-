-- CRYSTAL INVESTMENTS: reliable investor balances, transaction ledger and account summaries.
-- Run after 001, referral 002, 003, 004 and 005.

create table if not exists public.investor_ledger_entries (
 id uuid primary key default gen_random_uuid(),
 investor_id uuid not null references auth.users(id) on delete restrict,
 allocation_id uuid references public.investment_allocations(id) on delete restrict,
 source_type text not null check (source_type in ('Deposit','Withdrawal','Allocation','Distribution','Fee','Adjustment','Reversal')),
 source_id uuid,
 entry_type text not null check (entry_type in ('Credit','Debit')),
 amount numeric(20,6) not null check (amount > 0),
 currency text not null check (currency in ('KES','USD','GBP')),
 effective_at timestamptz not null default now(),
 description text not null default '',
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 unique(source_type,source_id,entry_type)
);
create index if not exists investor_ledger_owner_currency_idx on public.investor_ledger_entries(investor_id,currency,created_at desc);
create unique index if not exists investor_ledger_source_entry_unique on public.investor_ledger_entries(source_type,source_id,entry_type) where source_id is not null;
alter table public.investor_ledger_entries enable row level security;
drop policy if exists "Investors read own ledger entries" on public.investor_ledger_entries;
create policy "Investors read own ledger entries" on public.investor_ledger_entries for select to authenticated using(investor_id=(select auth.uid()));
drop policy if exists "Admins read all ledger entries" on public.investor_ledger_entries;
create policy "Admins read all ledger entries" on public.investor_ledger_entries for select to authenticated using(public.is_crystal_admin());
revoke all on public.investor_ledger_entries from anon,authenticated;
grant select on public.investor_ledger_entries to authenticated;

-- Review is atomic: status, ledger entry and audit event commit together.
create or replace function public.admin_review_financial_request(p_request_type text,p_request_id uuid,p_status text)
returns void language plpgsql security definer set search_path=''
as $$
declare v_investor uuid; v_amount numeric; v_currency text; v_old_status text; v_balance numeric;
begin
 if p_status not in ('approved','rejected') then raise exception 'Invalid review status'; end if;
 if p_request_type='deposit' then
  if not public.crystal_admin_has_permission('deposit_approvals') then raise exception 'Deposit approval permission required'; end if;
  select investor_id,amount,currency,status into v_investor,v_amount,v_currency,v_old_status from public.deposit_requests where id=p_request_id for update;
  if not found then raise exception 'Deposit request not found'; end if;
  if v_old_status not in ('pending','under_review') then raise exception 'This deposit request has already been reviewed'; end if;
  update public.deposit_requests set status=p_status,reviewed_by=(select auth.uid()),reviewed_at=now() where id=p_request_id;
  if p_status='approved' then
   insert into public.investor_ledger_entries(investor_id,source_type,source_id,entry_type,amount,currency,description,created_by)
   values(v_investor,'Deposit',p_request_id,'Credit',v_amount,v_currency,'Approved deposit',(select auth.uid())) on conflict(source_type,source_id,entry_type) where source_id is not null do nothing;
  end if;
 elsif p_request_type='withdrawal' then
  if not public.crystal_admin_has_permission('withdrawal_approvals') then raise exception 'Withdrawal approval permission required'; end if;
  select investor_id,amount,currency,status into v_investor,v_amount,v_currency,v_old_status from public.withdrawal_requests where id=p_request_id for update;
  if not found then raise exception 'Withdrawal request not found'; end if;
  if v_old_status not in ('pending','under_review') then raise exception 'This withdrawal request has already been reviewed'; end if;
  if p_status='approved' then
   select coalesce(sum(case when entry_type='Credit' then amount else -amount end),0)-coalesce((select sum(a.amount) from public.investment_allocations a where a.investor_id=v_investor and a.currency=v_currency and a.status in ('approved','active')),0) into v_balance from public.investor_ledger_entries where investor_id=v_investor and currency=v_currency;
   if v_balance < v_amount then raise exception 'Insufficient available balance for this withdrawal'; end if;
   insert into public.investor_ledger_entries(investor_id,source_type,source_id,entry_type,amount,currency,description,created_by)
   values(v_investor,'Withdrawal',p_request_id,'Debit',v_amount,v_currency,'Approved withdrawal',(select auth.uid()));
  end if;
  update public.withdrawal_requests set status=p_status,reviewed_by=(select auth.uid()),reviewed_at=now() where id=p_request_id;
 else raise exception 'Invalid request type'; end if;
 insert into public.crystal_admin_audit_log(actor_id,action,target_type,target_id,details)
 values((select auth.uid()),'financial_request_reviewed',p_request_type,p_request_id::text,jsonb_build_object('status',p_status,'amount',v_amount,'currency',v_currency));
end $$;
revoke all on function public.admin_review_financial_request(text,uuid,text) from public,anon;
grant execute on function public.admin_review_financial_request(text,uuid,text) to authenticated;

create or replace function public.investor_get_account_balances()
returns table(currency text,available_balance numeric,invested_capital numeric,accumulated_interest numeric,total_account_value numeric)
language sql security definer set search_path=''
as $$
 with currencies as (
  select currency from public.deposit_requests where investor_id=(select auth.uid())
  union select currency from public.withdrawal_requests where investor_id=(select auth.uid())
  union select currency from public.investment_allocations where investor_id=(select auth.uid())
  union select currency from public.investment_daily_accruals where investor_id=(select auth.uid())
 ), balances as (
  select c.currency,
   coalesce((select sum(case when l.entry_type='Credit' then l.amount else -l.amount end) from public.investor_ledger_entries l where l.investor_id=(select auth.uid()) and l.currency=c.currency),0)::numeric as cash,
   coalesce((select sum(a.amount) from public.investment_allocations a where a.investor_id=(select auth.uid()) and a.currency=c.currency and a.status='active'),0)::numeric as principal,
   coalesce((select sum(x.amount) from public.investment_daily_accruals x where x.investor_id=(select auth.uid()) and x.currency=c.currency),0)::numeric as interest
  from currencies c
 )
 select currency,cash,principal,interest,cash+principal+interest from balances order by currency;
$$;
revoke all on function public.investor_get_account_balances() from public,anon;
grant execute on function public.investor_get_account_balances() to authenticated;

-- Allow the existing investor-facing transaction history to show both request states and ledger-backed balances.

drop policy if exists "Admins read all deposit requests" on public.deposit_requests;
create policy "Admins read all deposit requests" on public.deposit_requests for select to authenticated using(public.is_crystal_admin());
drop policy if exists "Admins read all withdrawal requests" on public.withdrawal_requests;
create policy "Admins read all withdrawal requests" on public.withdrawal_requests for select to authenticated using(public.is_crystal_admin());
drop policy if exists "Admins read all investor profiles" on public.investor_profiles;
create policy "Admins read all investor profiles" on public.investor_profiles for select to authenticated using(public.is_crystal_admin());

-- Interest-rate changes are strictly reserved for the Supa Admin role, regardless of module grants.
create or replace function public.admin_set_global_interest_rate(p_annual_rate numeric,p_day_count_basis integer,p_effective_at timestamptz default now())
returns uuid language plpgsql security definer set search_path=''
as $$ declare v_id uuid; begin
 if not exists(select 1 from public.crystal_admin_memberships where user_id=(select auth.uid()) and role='Supa Admin' and is_active=true) then raise exception 'Only Supa Admin may change the global interest rate'; end if;
 if coalesce((select auth.jwt()->>'aal'),'aal1') <> 'aal2' then raise exception 'Multi-factor authentication is required for this action'; end if;
 if p_annual_rate<0 or p_annual_rate>100 or p_day_count_basis not in (360,365) then raise exception 'Invalid annual rate or day-count basis'; end if;
 if p_effective_at>now()+interval '1 day' then raise exception 'Effective date cannot be more than one day in the future'; end if;
 insert into public.crystal_interest_rate_history(annual_rate,day_count_basis,effective_at,created_by) values(p_annual_rate,p_day_count_basis,coalesce(p_effective_at,now()),(select auth.uid())) returning id into v_id;
 insert into public.crystal_admin_audit_log(actor_id,action,target_type,target_id,details) values((select auth.uid()),'global_interest_rate_changed','interest_rate',v_id::text,jsonb_build_object('annual_rate',p_annual_rate,'day_count_basis',p_day_count_basis,'effective_at',p_effective_at));
 return v_id;
end $$;
revoke all on function public.admin_set_global_interest_rate(numeric,integer,timestamptz) from public,anon;
grant execute on function public.admin_set_global_interest_rate(numeric,integer,timestamptz) to authenticated;

-- Supa Admin-only last-super-admin safeguard for promotions and demotions.
create or replace function public.admin_set_membership(p_email text,p_role text,p_permissions jsonb default '{}'::jsonb)
returns uuid language plpgsql security definer set search_path=''
as $$ declare v_uid uuid; v_old_role text; v_count integer; begin
 if not exists(select 1 from public.crystal_admin_memberships where user_id=(select auth.uid()) and role='Supa Admin' and is_active=true) then raise exception 'Supa Admin permission required'; end if;
 if coalesce((select auth.jwt()->>'aal'),'aal1') <> 'aal2' then raise exception 'Multi-factor authentication is required for administrator role changes'; end if;
 if p_role not in ('Supa Admin','Junior Admin') then raise exception 'Invalid administrator role'; end if;
 select id into v_uid from auth.users where lower(email)=lower(trim(p_email));
 if v_uid is null then raise exception 'Create the administrator login account first, then assign its role'; end if;
 select role into v_old_role from public.crystal_admin_memberships where user_id=v_uid and is_active=true;
 if v_old_role='Supa Admin' and p_role='Junior Admin' then
  perform pg_advisory_xact_lock(hashtext('crystal_supa_admin_role_lock'));
  select count(*) into v_count from public.crystal_admin_memberships where role='Supa Admin' and is_active=true;
  if v_count<=1 then raise exception 'The last Supa Admin cannot be demoted'; end if;
 end if;
 insert into public.crystal_admin_memberships(user_id,role,permissions,is_active)
 values(v_uid,p_role,case when p_role='Supa Admin' then '{}'::jsonb else coalesce(p_permissions,'{}'::jsonb) end,true)
 on conflict(user_id) do update set role=excluded.role,permissions=excluded.permissions,is_active=true,updated_at=now();
 insert into public.crystal_admin_audit_log(actor_id,action,target_type,target_id,details)
 values((select auth.uid()),'administrator_membership_set','admin',v_uid::text,jsonb_build_object('email',lower(trim(p_email)),'role',p_role,'permissions',p_permissions));
 return v_uid;
end $$;
revoke all on function public.admin_set_membership(text,text,jsonb) from public,anon;
grant execute on function public.admin_set_membership(text,text,jsonb) to authenticated;

create or replace function public.admin_list_investor_profiles()
returns table(id uuid,email text,full_name text,phone text,country text,preferred_currency text)
language sql security definer set search_path=''
as $$
 select p.id,u.email,p.full_name,p.phone,p.country,p.preferred_currency
 from public.investor_profiles p join auth.users u on u.id=p.id
 where public.crystal_admin_has_permission('investors') order by p.created_at desc;
$$;
revoke all on function public.admin_list_investor_profiles() from public,anon;
grant execute on function public.admin_list_investor_profiles() to authenticated;

create or replace function public.admin_update_investor_profile(p_investor_id uuid,p_full_name text,p_phone text,p_country text)
returns void language plpgsql security definer set search_path=''
as $$ begin
 if not public.crystal_admin_has_permission('investors') then raise exception 'Investor management permission required'; end if;
 update public.investor_profiles set full_name=left(trim(coalesce(p_full_name,'')),160),phone=left(trim(coalesce(p_phone,'')),40),country=left(trim(coalesce(p_country,'')),100),updated_at=now() where id=p_investor_id;
 if not found then raise exception 'Investor profile not found'; end if;
 insert into public.crystal_admin_audit_log(actor_id,action,target_type,target_id) values((select auth.uid()),'investor_profile_updated','investor',p_investor_id::text);
end $$;
revoke all on function public.admin_update_investor_profile(uuid,text,text,text) from public,anon;
grant execute on function public.admin_update_investor_profile(uuid,text,text,text) to authenticated;

-- The existing RPC has a different OUT-column signature; drop this exact zero-argument function before recreating it.
-- This removes only the RPC definition, not investor or financial data.
DROP FUNCTION IF EXISTS public.admin_list_investment_allocations();

create or replace function public.admin_list_investment_allocations()
returns table(id uuid,investor_id uuid,investor_email text,project_name text,amount numeric,currency text,annual_rate numeric,day_count_basis integer,terms_reference text,status text,activated_at timestamptz,created_at timestamptz)
language sql security definer set search_path=''
as $$
 select a.id,a.investor_id,u.email,a.project_name,a.amount,a.currency,a.annual_rate,a.day_count_basis,a.terms_reference,a.status,a.activated_at,a.created_at
 from public.investment_allocations a join auth.users u on u.id=a.investor_id
 where public.crystal_admin_has_permission('portfolio') order by a.created_at desc;
$$;
revoke all on function public.admin_list_investment_allocations() from public,anon;
grant execute on function public.admin_list_investment_allocations() to authenticated;

create or replace function public.admin_create_investment_allocation(p_investor_email text,p_project_name text,p_amount numeric,p_currency text,p_terms_reference text)
returns uuid language plpgsql security definer set search_path=''
as $$ declare v_investor uuid;v_available numeric;v_allocated numeric;v_id uuid;begin
 if not public.crystal_admin_has_permission('portfolio') then raise exception 'Portfolio management permission required'; end if;
 if p_amount<=0 or p_currency not in ('KES','USD','GBP') then raise exception 'Invalid allocation amount or currency'; end if;
 select id into v_investor from auth.users where lower(email)=lower(trim(p_investor_email));
 if v_investor is null then raise exception 'Investor account not found'; end if;
 select coalesce(sum(case when entry_type='Credit' then amount else -amount end),0) into v_available from public.investor_ledger_entries where investor_id=v_investor and currency=p_currency;
 select coalesce(sum(amount),0) into v_allocated from public.investment_allocations where investor_id=v_investor and currency=p_currency and status in ('approved','active');
 if p_amount>v_available-v_allocated then raise exception 'Allocation exceeds available approved deposit balance'; end if;
 insert into public.investment_allocations(investor_id,project_name,amount,currency,annual_rate,day_count_basis,terms_reference,status,created_by)
 values(v_investor,left(trim(p_project_name),180),p_amount,p_currency,0,365,left(trim(p_terms_reference),500),'pending',(select auth.uid())) returning id into v_id;
 insert into public.crystal_admin_audit_log(actor_id,action,target_type,target_id,details) values((select auth.uid()),'investment_allocation_created','investment',v_id::text,jsonb_build_object('investor_id',v_investor,'amount',p_amount,'currency',p_currency));
 return v_id;
end $$;
revoke all on function public.admin_create_investment_allocation(text,text,numeric,text,text) from public,anon;
grant execute on function public.admin_create_investment_allocation(text,text,numeric,text,text) to authenticated;

create or replace function public.admin_update_investment_allocation(p_allocation_id uuid,p_status text)
returns void language plpgsql security definer set search_path=''
as $$ declare v_status text;begin
 if not public.crystal_admin_has_permission('portfolio') then raise exception 'Portfolio management permission required'; end if;
 if p_status not in ('approved','active','declined') then raise exception 'Invalid allocation status'; end if;
 select status into v_status from public.investment_allocations where id=p_allocation_id for update;
 if not found then raise exception 'Investment allocation not found'; end if;
 if p_status='active' and v_status<>'approved' then raise exception 'Approve the allocation before activating it'; end if;
 update public.investment_allocations set status=p_status,approved_at=case when p_status='approved' then now() else approved_at end,activated_at=case when p_status='active' then now() else activated_at end where id=p_allocation_id;
 insert into public.crystal_admin_audit_log(actor_id,action,target_type,target_id,details) values((select auth.uid()),'investment_allocation_status_changed','investment',p_allocation_id::text,jsonb_build_object('status',p_status));
end $$;
revoke all on function public.admin_update_investment_allocation(uuid,text) from public,anon;
grant execute on function public.admin_update_investment_allocation(uuid,text) to authenticated;

-- Keep invested capital unavailable for withdrawals while preserving it in total account value.
create or replace function public.investor_get_account_balances()
returns table(currency text,available_balance numeric,invested_capital numeric,accumulated_interest numeric,total_account_value numeric)
language sql security definer set search_path=''
as $$
 with currencies as (
  select currency from public.investor_ledger_entries where investor_id=(select auth.uid())
  union select currency from public.investment_allocations where investor_id=(select auth.uid())
  union select currency from public.investment_daily_accruals where investor_id=(select auth.uid())
 ), balances as (
  select c.currency,
   coalesce((select sum(case when l.entry_type='Credit' then l.amount else -l.amount end) from public.investor_ledger_entries l where l.investor_id=(select auth.uid()) and l.currency=c.currency),0)::numeric as ledger_cash,
   coalesce((select sum(a.amount) from public.investment_allocations a where a.investor_id=(select auth.uid()) and a.currency=c.currency and a.status='active'),0)::numeric as principal,
   coalesce((select sum(x.amount) from public.investment_daily_accruals x where x.investor_id=(select auth.uid()) and x.currency=c.currency),0)::numeric as interest
  from currencies c
 )
 select currency,ledger_cash-coalesce((select sum(a.amount) from public.investment_allocations a where a.investor_id=(select auth.uid()) and a.currency=balances.currency and a.status in ('approved','active')),0),principal,interest,ledger_cash+interest from balances order by currency;
$$;
revoke all on function public.investor_get_account_balances() from public,anon;
grant execute on function public.investor_get_account_balances() to authenticated;
