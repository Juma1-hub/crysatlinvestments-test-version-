-- CRYSTAL INVESTMENTS integrated financial controls.
-- Apply after the existing investor, referral, central-backend and interest/admin migrations.
-- This migration preserves existing financial rows. It does not activate opportunities or enable live payments.

create extension if not exists pgcrypto;

create or replace function public.crystal_require_admin_mfa()
returns void language plpgsql stable security definer set search_path=''
as $$ begin
  if coalesce((select auth.jwt()->>'aal'),'aal1')<>'aal2' then raise exception 'Multi-factor authentication is required for this action'; end if;
end $$;
revoke all on function public.crystal_require_admin_mfa() from public,anon;
grant execute on function public.crystal_require_admin_mfa() to authenticated;

create or replace function public.crystal_accrue_investor_daily_earnings(p_investor_id uuid)
returns void language plpgsql security definer set search_path=''
as $$
begin
  if (select auth.uid()) is null then raise exception 'Authentication required'; end if;
  if (select auth.uid())<>p_investor_id and not public.is_crystal_admin() then raise exception 'Investor account access required'; end if;
  insert into public.investment_daily_accruals(allocation_id,investor_id,accrual_date,principal_basis,annual_rate,day_count_basis,amount,currency)
  select a.id,a.investor_id,g.day_value::date,a.amount,rate.annual_rate,rate.day_count_basis,
    round(a.amount*rate.annual_rate/100/rate.day_count_basis,6),a.currency
  from public.investment_allocations a
  cross join lateral generate_series(
    greatest(a.activated_at::date,(select min(h.effective_at)::date from public.crystal_interest_rate_history h)),
    least(current_date,(a.activated_at::date+interval '1 year'-interval '1 day')::date),interval '1 day'
  ) g(day_value)
  cross join lateral (select h.annual_rate,h.day_count_basis from public.crystal_interest_rate_history h where h.effective_at::date<=g.day_value::date order by h.effective_at desc limit 1) rate
  where a.investor_id=p_investor_id and a.status='active' and a.activated_at is not null
    and exists(select 1 from public.crystal_interest_rate_history)
  on conflict(allocation_id,accrual_date) do nothing;
end $$;
revoke all on function public.crystal_accrue_investor_daily_earnings(uuid) from public,anon,authenticated;

-- The eight website divisions are the only investment allocation destinations.
alter table public.investment_opportunities
  add column if not exists supported_currencies text[] not null default array['KES','USD','GBP']::text[];
create unique index if not exists investment_opportunities_division_uidx
  on public.investment_opportunities(division);

insert into public.investment_opportunities
  (title, division, summary, description, currency, status, terms_version, risk_disclosure, supported_currencies)
values
 ('Energy & Petroleum','Energy & Petroleum','Investment activity across energy and petroleum value chains.','Opportunities may include energy production, storage, distribution and related infrastructure. Participation is subject to approved project terms and risk disclosures.','KES','Draft','v1','Energy prices, regulation, project execution, environmental and counterparty risks.',array['KES','USD','GBP']::text[]),
 ('Agriculture & Agribusiness','Agriculture & Agribusiness','Agricultural production, processing and related value chains.','Opportunities may include farming, processing, storage, inputs and agribusiness infrastructure. Participation is subject to approved project terms and risk disclosures.','KES','Draft','v1','Weather, biological, commodity-price, logistics and operational risks.',array['KES','USD','GBP']::text[]),
 ('Real Estate & Infrastructure','Real Estate & Infrastructure','Property and essential infrastructure opportunities.','Opportunities may include development, property operations and infrastructure assets. Participation is subject to approved project terms and risk disclosures.','KES','Draft','v1','Construction, valuation, liquidity, occupancy, financing and regulatory risks.',array['KES','USD','GBP']::text[]),
 ('Mining & Minerals','Mining & Minerals','Mineral resources, extraction and related value chains.','Opportunities may include exploration, extraction, processing and mineral logistics. Participation is subject to approved project terms and risk disclosures.','KES','Draft','v1','Geological, commodity-price, licensing, environmental and operational risks.',array['KES','USD','GBP']::text[]),
 ('Shipping & Logistics','Shipping & Logistics','Trade, shipping, freight and logistics infrastructure.','Opportunities may include freight, shipping services, warehousing and logistics infrastructure. Participation is subject to approved project terms and risk disclosures.','KES','Draft','v1','Fuel, freight-rate, counterparty, geopolitical and operational risks.',array['KES','USD','GBP']::text[]),
 ('Technology & Innovation','Technology & Innovation','Technology, digital infrastructure and innovation opportunities.','Opportunities may include software, AI infrastructure, data centres, cloud, storage and related technology assets. Participation is subject to approved project terms and risk disclosures.','KES','Draft','v1','Technology obsolescence, cybersecurity, execution, concentration and valuation risks.',array['KES','USD','GBP']::text[]),
 ('Global Markets & Securities','Global Markets & Securities','Eligible global listed and private-market securities opportunities.','Opportunities may include securities and other eligible global market exposures, subject to legal availability and approved project terms. Participation is subject to approved project terms and risk disclosures.','KES','Draft','v1','Market, currency, custody, liquidity, issuer and cross-border regulatory risks.',array['KES','USD','GBP']::text[]),
 ('General Investments & Acquisitions','General Investments & Acquisitions','Other eligible investments, acquisitions and strategic opportunities.','Opportunities may include acquisitions and other approved investment transactions. Participation is subject to approved project terms and risk disclosures.','KES','Draft','v1','Due diligence, valuation, integration, liquidity and counterparty risks.',array['KES','USD','GBP']::text[])
on conflict (division) do nothing;

-- Preserve the current project_name/amount model while linking allocations to the canonical division.
alter table public.investment_allocations
  add column if not exists opportunity_id uuid references public.investment_opportunities(id) on delete restrict,
  add column if not exists source_deposit_id uuid references public.deposit_requests(id) on delete restrict;
create unique index if not exists investment_allocations_deposit_opportunity_uidx
  on public.investment_allocations(source_deposit_id, opportunity_id)
  where source_deposit_id is not null and opportunity_id is not null;

alter table public.deposit_requests
  add column if not exists allocation_processed_at timestamptz,
  add column if not exists verification_mode text not null default 'manual',
  add column if not exists verification_reference text;

alter table public.withdrawal_requests
  add column if not exists principal_reduction numeric(20,6) not null default 0,
  add column if not exists earnings_redeemed numeric(20,6) not null default 0,
  add column if not exists posted_at timestamptz;

alter table public.investment_daily_accruals
  add column if not exists redeemed_amount numeric(20,6) not null default 0;

alter table public.crystal_admin_memberships
  add column if not exists display_name text not null default '';

alter table public.crystal_support_messages
  add column if not exists archived_at timestamptz;

-- Admin-to-admin private conversation history used by the existing admin interface.
create table if not exists public.crystal_admin_conversations (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete restrict,
  sender_email text not null default '',
  message text not null check (length(trim(message)) between 1 and 5000),
  archived_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.crystal_admin_conversations
  add column if not exists sender_id uuid references auth.users(id) on delete restrict,
  add column if not exists sender_email text not null default '',
  add column if not exists message text not null default '',
  add column if not exists archived_at timestamptz,
  add column if not exists created_at timestamptz not null default now();
alter table public.crystal_admin_audit_log add column if not exists archived_at timestamptz;
alter table public.crystal_admin_conversations enable row level security;
drop policy if exists "Admins read conversations" on public.crystal_admin_conversations;
create policy "Admins read conversations" on public.crystal_admin_conversations
  for select to authenticated using (public.is_crystal_admin());
revoke all on public.crystal_admin_conversations from anon, authenticated;
grant select on public.crystal_admin_conversations to authenticated;

create or replace function public.admin_send_conversation_message(p_message text)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid; v_email text;
begin
  if not public.is_crystal_admin() then raise exception 'Administrator access required'; end if;
  if length(trim(coalesce(p_message,''))) not between 1 and 5000 then raise exception 'Message must contain 1 to 5000 characters'; end if;
  select coalesce(u.email,'') into v_email from auth.users u where u.id=(select auth.uid());
  insert into public.crystal_admin_conversations(sender_id,sender_email,message)
  values((select auth.uid()),v_email,trim(p_message)) returning id into v_id;
  insert into public.crystal_admin_audit_log(actor_id,action,target_type,target_id,details)
  values((select auth.uid()),'admin_conversation_message_sent','admin_conversation',v_id::text,'{}'::jsonb);
  return v_id;
end $$;
revoke all on function public.admin_send_conversation_message(text) from public,anon;
grant execute on function public.admin_send_conversation_message(text) to authenticated;

create or replace function public.crystal_actor_name(p_user_id uuid)
returns text language sql stable security definer set search_path=''
as $$
  select coalesce(nullif(m.display_name,''),nullif(p.full_name,''),nullif(u.email,''),'Administrator')
  from auth.users u
  left join public.crystal_admin_memberships m on m.user_id=u.id
  left join public.investor_profiles p on p.id=u.id
  where u.id=p_user_id
$$;
revoke all on function public.crystal_actor_name(uuid) from public,anon;
grant execute on function public.crystal_actor_name(uuid) to authenticated;

-- Balances are calculated in their original currencies from active capital and unredeemed accruals.
drop function if exists public.investor_get_account_balances();
create function public.investor_get_account_balances()
returns table(currency text,available_balance numeric,invested_capital numeric,accumulated_interest numeric,total_account_value numeric)
language plpgsql security definer set search_path=''
as $$
begin
  if (select auth.uid()) is null then raise exception 'Authentication required'; end if;
  perform public.investor_accrue_daily_earnings();
  return query
  with currencies as (
    select a.currency from public.investment_allocations a where a.investor_id=(select auth.uid())
    union select d.currency from public.deposit_requests d where d.investor_id=(select auth.uid()) and d.status='approved'
    union select w.currency from public.withdrawal_requests w where w.investor_id=(select auth.uid())
  ), capital as (
    select a.currency,coalesce(sum(a.amount) filter(where a.status='active'),0)::numeric as principal
    from public.investment_allocations a where a.investor_id=(select auth.uid()) group by a.currency
  ), interest as (
    select d.currency,coalesce(sum(greatest(d.amount-d.redeemed_amount,0)),0)::numeric as earnings
    from public.investment_daily_accruals d where d.investor_id=(select auth.uid()) group by d.currency
  ), reserved as (
    select w.currency,coalesce(sum(w.amount),0)::numeric as pending
    from public.withdrawal_requests w where w.investor_id=(select auth.uid()) and lower(w.status) in ('pending','submitted','under review','under_review','processing')
    group by w.currency
  )
  select c.currency,
    greatest(coalesce(k.principal,0)+coalesce(i.earnings,0)-coalesce(r.pending,0),0)::numeric,
    coalesce(k.principal,0)::numeric,
    coalesce(i.earnings,0)::numeric,
    (coalesce(k.principal,0)+coalesce(i.earnings,0))::numeric
  from currencies c left join capital k using(currency) left join interest i using(currency) left join reserved r using(currency)
  order by c.currency;
end $$;
revoke all on function public.investor_get_account_balances() from public,anon;
grant execute on function public.investor_get_account_balances() to authenticated;

-- Investor withdrawal requests reserve funds immediately and cannot exceed unreserved account value.
create or replace function public.investor_submit_withdrawal(p_amount numeric,p_currency text,p_destination jsonb)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_user uuid := (select auth.uid()); v_principal numeric; v_earnings numeric; v_reserved numeric; v_available numeric; v_id uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if p_amount is null or p_amount<=0 or p_currency not in ('KES','USD','GBP') then raise exception 'Invalid withdrawal amount or currency'; end if;
  if p_destination is null or jsonb_typeof(p_destination)<>'object'
    or length(trim(coalesce(p_destination->>'account_holder','')))<2
    or length(trim(coalesce(p_destination->>'account_number','')))<4
    or coalesce(p_destination->>'method','') not in ('Bank transfer','M-Pesa') then
    raise exception 'Complete the withdrawal destination details';
  end if;
  if p_destination->>'method'='Bank transfer' and length(trim(coalesce(p_destination->>'bank_name','')))<2 then
    raise exception 'Bank name is required for bank transfers';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_user::text||':'||p_currency,0));
  perform public.investor_accrue_daily_earnings();
  select coalesce(sum(a.amount),0) into v_principal from public.investment_allocations a where a.investor_id=v_user and a.currency=p_currency and a.status='active';
  select coalesce(sum(greatest(d.amount-d.redeemed_amount,0)),0) into v_earnings from public.investment_daily_accruals d where d.investor_id=v_user and d.currency=p_currency;
  select coalesce(sum(w.amount),0) into v_reserved from public.withdrawal_requests w where w.investor_id=v_user and w.currency=p_currency and lower(w.status) in ('pending','submitted','under review','under_review','processing');
  v_available:=v_principal+v_earnings-v_reserved;
  if p_amount>v_available then raise exception 'Withdrawal exceeds your available account balance'; end if;
  insert into public.withdrawal_requests(investor_id,amount,currency,destination_details)
  values(v_user,p_amount,p_currency,coalesce(p_destination,'{}'::jsonb)) returning id into v_id;
  return v_id;
end $$;
revoke all on function public.investor_submit_withdrawal(numeric,text,jsonb) from public,anon;
grant execute on function public.investor_submit_withdrawal(numeric,text,jsonb) to authenticated;

-- Financial approval is atomic: deposit approval creates exactly eight equal allocations;
-- withdrawal approval reduces capital proportionally and redeems accrued earnings if needed.
create or replace function public.admin_review_financial_request(p_request_type text,p_request_id uuid,p_status text)
returns void language plpgsql security definer set search_path=''
as $$
declare
  v_actor uuid := (select auth.uid()); v_actor_name text; v_status text;
  v_deposit public.deposit_requests%rowtype; v_withdrawal public.withdrawal_requests%rowtype;
  v_rate numeric; v_basis integer; v_count integer; v_op_count integer:=0; v_total numeric; v_principal numeric; v_earnings numeric;
  v_principal_reduction numeric; v_earnings_redeemed numeric; v_remaining numeric; v_piece numeric; v_last boolean;
  r record; v_allocation_id uuid; v_processed integer;
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  perform public.crystal_require_admin_mfa();
  if p_status not in ('approved','rejected') then raise exception 'Invalid review status'; end if;
  if p_request_type='deposit' then
    if not public.crystal_admin_has_permission('deposit_approvals') then raise exception 'Deposit approval permission required'; end if;
    select * into v_deposit from public.deposit_requests where id=p_request_id for update;
    if not found then raise exception 'Deposit request not found'; end if;
    if lower(v_deposit.status) not in ('pending','submitted','under review','under_review') then raise exception 'Deposit request has already been reviewed'; end if;
    if p_status='approved' then
      if not coalesce((select c.config_value->>'financial_operations_enabled'='true' from public.crystal_site_configuration c where c.config_key='platform_settings'),false) then raise exception 'Financial operations are not enabled'; end if;
      select count(*) into v_count from public.investment_opportunities o
      where o.division in ('Energy & Petroleum','Agriculture & Agribusiness','Real Estate & Infrastructure','Mining & Minerals','Shipping & Logistics','Technology & Innovation','Global Markets & Securities','General Investments & Acquisitions')
        and o.status='Active' and v_deposit.currency=any(o.supported_currencies);
      if v_count<>8 then raise exception 'All eight approved investment divisions must be active and support this currency before deposits can be invested'; end if;
      select h.annual_rate,h.day_count_basis into v_rate,v_basis from public.crystal_interest_rate_history h
      where h.effective_at<=now() order by h.effective_at desc limit 1;
      if v_rate is null then raise exception 'The Supa Admin must configure an effective annual interest rate before investment activation'; end if;
      for r in
        select o.id,o.title,o.terms_version from public.investment_opportunities o
        where o.division in ('Energy & Petroleum','Agriculture & Agribusiness','Real Estate & Infrastructure','Mining & Minerals','Shipping & Logistics','Technology & Innovation','Global Markets & Securities','General Investments & Acquisitions')
          and o.status='Active' and v_deposit.currency=any(o.supported_currencies)
        order by array_position(array['Energy & Petroleum','Agriculture & Agribusiness','Real Estate & Infrastructure','Mining & Minerals','Shipping & Logistics','Technology & Innovation','Global Markets & Securities','General Investments & Acquisitions']::text[],o.division)
      loop
        -- 7 rounded portions and an exact remainder in the final division.
        if v_op_count<7 then v_piece:=round(v_deposit.amount/8,6); else
          v_piece:=v_deposit.amount-(round(v_deposit.amount/8,6)*7);
        end if;
        insert into public.investment_allocations
          (investor_id,project_name,amount,currency,annual_rate,day_count_basis,terms_reference,status,approved_at,activated_at,created_by,opportunity_id,source_deposit_id)
        values(v_deposit.investor_id,r.title,v_piece,v_deposit.currency,v_rate,v_basis,coalesce(r.terms_version,'v1'),'active',now(),now(),v_actor,r.id,r.id)
        on conflict (source_deposit_id,opportunity_id) where source_deposit_id is not null and opportunity_id is not null do nothing
        returning id into v_allocation_id;
        v_op_count:=v_op_count+1;
      end loop;
      select count(*) into v_processed from public.investment_allocations where source_deposit_id=p_request_id;
      if v_processed<>8 then raise exception 'Automatic allocation did not create exactly eight division records'; end if;
      update public.deposit_requests set status='approved',reviewed_by=v_actor,reviewed_at=now(),allocation_processed_at=coalesce(allocation_processed_at,now()) where id=p_request_id;
      insert into public.investor_ledger_entries(investor_id,source_type,source_id,entry_type,amount,currency,effective_at,description,created_by)
      select v_deposit.investor_id,'Deposit',p_request_id,'Credit',v_deposit.amount,v_deposit.currency,now(),'Approved deposit automatically allocated across eight investment divisions',v_actor
      where not exists(select 1 from public.investor_ledger_entries l where l.source_type='Deposit' and l.source_id=p_request_id and l.entry_type='Credit');
    else
      update public.deposit_requests set status='rejected',reviewed_by=v_actor,reviewed_at=now() where id=p_request_id;
    end if;
  elsif p_request_type='withdrawal' then
    if not public.crystal_admin_has_permission('withdrawal_approvals') then raise exception 'Withdrawal approval permission required'; end if;
    select * into v_withdrawal from public.withdrawal_requests where id=p_request_id for update;
    if not found then raise exception 'Withdrawal request not found'; end if;
    if lower(v_withdrawal.status) not in ('pending','submitted','under review','under_review','processing') then raise exception 'Withdrawal request has already been reviewed'; end if;
    if p_status='approved' then
      perform pg_advisory_xact_lock(hashtextextended(v_withdrawal.investor_id::text||':'||v_withdrawal.currency,0));
      perform public.crystal_accrue_investor_daily_earnings(v_withdrawal.investor_id);
      select coalesce(sum(a.amount),0) into v_principal from public.investment_allocations a where a.investor_id=v_withdrawal.investor_id and a.currency=v_withdrawal.currency and a.status='active';
      select coalesce(sum(greatest(d.amount-d.redeemed_amount,0)),0) into v_earnings from public.investment_daily_accruals d where d.investor_id=v_withdrawal.investor_id and d.currency=v_withdrawal.currency;
      select coalesce(sum(w.amount),0) into v_total from public.withdrawal_requests w where w.investor_id=v_withdrawal.investor_id and w.currency=v_withdrawal.currency and lower(w.status) in ('pending','submitted','under review','under_review','processing') and w.id<>p_request_id;
      if v_withdrawal.amount>v_principal+v_earnings-v_total then raise exception 'Withdrawal exceeds the investor available account balance'; end if;
      v_principal_reduction:=least(v_withdrawal.amount,v_principal);
      v_earnings_redeemed:=v_withdrawal.amount-v_principal_reduction;
      v_remaining:=v_principal_reduction;
      for r in select a.id,a.amount from public.investment_allocations a where a.investor_id=v_withdrawal.investor_id and a.currency=v_withdrawal.currency and a.status='active' order by a.id loop
        select not exists(select 1 from public.investment_allocations a2 where a2.investor_id=v_withdrawal.investor_id and a2.currency=v_withdrawal.currency and a2.status='active' and a2.id>r.id) into v_last;
        if v_last then v_piece:=v_remaining;
        else v_piece:=least(r.amount,round(v_principal_reduction*r.amount/nullif(v_principal,0),6)); end if;
        v_piece:=least(greatest(v_piece,0),r.amount,v_remaining);
        if v_piece>0 then
          update public.investment_allocations set amount=case when amount-v_piece<=0 then amount else amount-v_piece end,status=case when amount-v_piece<=0 then 'closed' else status end where id=r.id;
          v_remaining:=v_remaining-v_piece;
        end if;
      end loop;
      if v_remaining>0.000001 then raise exception 'Could not reconcile proportional principal reduction'; end if;
      v_remaining:=v_earnings_redeemed;
      for r in select d.id,greatest(d.amount-d.redeemed_amount,0) as remaining from public.investment_daily_accruals d where d.investor_id=v_withdrawal.investor_id and d.currency=v_withdrawal.currency and d.amount>d.redeemed_amount order by d.accrual_date,d.id for update loop
        exit when v_remaining<=0;
        v_piece:=least(r.remaining,v_remaining);
        update public.investment_daily_accruals set redeemed_amount=redeemed_amount+v_piece where id=r.id;
        v_remaining:=v_remaining-v_piece;
      end loop;
      if v_remaining>0.000001 then raise exception 'Could not reconcile accrued earnings redemption'; end if;
      update public.withdrawal_requests set status='approved',reviewed_by=v_actor,reviewed_at=now(),principal_reduction=v_principal_reduction,earnings_redeemed=v_earnings_redeemed,posted_at=now() where id=p_request_id;
      insert into public.investor_ledger_entries(investor_id,source_type,source_id,entry_type,amount,currency,effective_at,description,created_by)
      values(v_withdrawal.investor_id,'Withdrawal',p_request_id,'Debit',v_withdrawal.amount,v_withdrawal.currency,now(),'Approved withdrawal posted with proportional investment reduction',v_actor);
    else
      update public.withdrawal_requests set status='rejected',reviewed_by=v_actor,reviewed_at=now() where id=p_request_id;
    end if;
  else
    raise exception 'Invalid request type';
  end if;

  v_actor_name:=public.crystal_actor_name(v_actor);
  insert into public.crystal_admin_audit_log(actor_id,action,target_type,target_id,details)
  values(v_actor,'financial_request_reviewed',p_request_type,p_request_id::text,
    jsonb_build_object('status',p_status,'admin_name',coalesce(v_actor_name,'Administrator')));
end $$;
revoke all on function public.admin_review_financial_request(text,uuid,text) from public,anon;
grant execute on function public.admin_review_financial_request(text,uuid,text) to authenticated;

-- Supa Admin-only history clearing. Financial source records and audit evidence are archived, never destroyed.
create or replace function public.admin_clear_activity_feed()
returns integer language plpgsql security definer set search_path=''
as $$ declare v_count integer; begin
  if not exists(select 1 from public.crystal_admin_memberships m where m.user_id=(select auth.uid()) and m.role='Supa Admin' and m.is_active=true) then raise exception 'Supa Admin permission required'; end if;
  perform public.crystal_require_admin_mfa();
  update public.crystal_admin_audit_log set archived_at=now() where archived_at is null;
  get diagnostics v_count=row_count;
  insert into public.crystal_admin_audit_log(actor_id,action,target_type,details)
  values((select auth.uid()),'recent_activity_feed_archived','audit_log',jsonb_build_object('archived_count',v_count,'admin_name',public.crystal_actor_name((select auth.uid()))));
  return v_count;
end $$;
revoke all on function public.admin_clear_activity_feed() from public,anon;
grant execute on function public.admin_clear_activity_feed() to authenticated;

create or replace function public.admin_clear_support_history()
returns integer language plpgsql security definer set search_path=''
as $$ declare v_count integer; begin
  if not exists(select 1 from public.crystal_admin_memberships m where m.user_id=(select auth.uid()) and m.role='Supa Admin' and m.is_active=true) then raise exception 'Supa Admin permission required'; end if;
  perform public.crystal_require_admin_mfa();
  update public.crystal_support_messages set archived_at=now() where archived_at is null;
  get diagnostics v_count=row_count;
  insert into public.crystal_admin_audit_log(actor_id,action,target_type,details)
  values((select auth.uid()),'support_history_archived','support_message',jsonb_build_object('archived_count',v_count,'admin_name',public.crystal_actor_name((select auth.uid()))));
  return v_count;
end $$;
revoke all on function public.admin_clear_support_history() from public,anon;
grant execute on function public.admin_clear_support_history() to authenticated;

create or replace function public.admin_clear_conversation_history()
returns integer language plpgsql security definer set search_path=''
as $$ declare v_count integer; begin
  if not exists(select 1 from public.crystal_admin_memberships m where m.user_id=(select auth.uid()) and m.role='Supa Admin' and m.is_active=true) then raise exception 'Supa Admin permission required'; end if;
  perform public.crystal_require_admin_mfa();
  update public.crystal_admin_conversations set archived_at=now() where archived_at is null;
  get diagnostics v_count=row_count;
  insert into public.crystal_admin_audit_log(actor_id,action,target_type,details)
  values((select auth.uid()),'admin_conversation_history_archived','admin_conversation',jsonb_build_object('archived_count',v_count,'admin_name',public.crystal_actor_name((select auth.uid()))));
  return v_count;
end $$;
revoke all on function public.admin_clear_conversation_history() from public,anon;
grant execute on function public.admin_clear_conversation_history() to authenticated;

-- Admins see complete investor details in their permitted modules; only Supa Admin sees admin PII.
drop function if exists public.admin_list_memberships();
create function public.admin_list_memberships()
returns table(user_id text,email text,role text,permissions jsonb,is_active boolean)
language plpgsql security definer set search_path=''
as $$
declare v_supa boolean;
begin
  if not public.is_crystal_admin() then raise exception 'Administrator access required'; end if;
  select exists(select 1 from public.crystal_admin_memberships m where m.user_id=(select auth.uid()) and m.role='Supa Admin' and m.is_active=true) into v_supa;
  return query
  select case when v_supa then m.user_id::text else left(m.user_id::text,4)||'…'||right(m.user_id::text,4) end,
    case when v_supa then coalesce(u.email,'') else
      case when coalesce(u.email,'') like '%@%' then
        left(split_part(u.email,'@',1),1)||repeat('*',greatest(length(split_part(u.email,'@',1))-2,1))||right(split_part(u.email,'@',1),1)||'@'||split_part(u.email,'@',2)
      else '***' end end,
    m.role,
    case when v_supa then m.permissions else '{}'::jsonb end,
    m.is_active
  from public.crystal_admin_memberships m join auth.users u on u.id=m.user_id
  order by m.created_at;
end $$;
revoke all on function public.admin_list_memberships() from public,anon;
grant execute on function public.admin_list_memberships() to authenticated;

-- Only Supa Admin can change admin membership; action identity is stored in audit details.
create or replace function public.admin_set_membership(p_email text,p_role text,p_permissions jsonb default '{}'::jsonb)
returns uuid language plpgsql security definer set search_path=''
as $$ declare v_uid uuid; v_actor uuid:=(select auth.uid()); v_actor_name text; v_count integer;
begin
  if not exists(select 1 from public.crystal_admin_memberships where user_id=v_actor and role='Supa Admin' and is_active=true) then raise exception 'Supa Admin permission required'; end if;
  perform public.crystal_require_admin_mfa();
  if p_role not in ('Supa Admin','Junior Admin') then raise exception 'Invalid administrator role'; end if;
  select id into v_uid from auth.users where lower(email)=lower(trim(p_email));
  if v_uid is null then raise exception 'Create the administrator login account first, then assign its role'; end if;
  if v_uid=v_actor and p_role<>'Supa Admin' then
    select count(*) into v_count from public.crystal_admin_memberships where role='Supa Admin' and is_active=true;
    if v_count<=1 then raise exception 'The last Supa Admin cannot be demoted'; end if;
  end if;
  insert into public.crystal_admin_memberships(user_id,role,permissions,is_active)
  values(v_uid,p_role,case when p_role='Supa Admin' then '{}'::jsonb else coalesce(p_permissions,'{}'::jsonb) end,true)
  on conflict(user_id) do update set role=excluded.role,permissions=excluded.permissions,is_active=true,updated_at=now();
  v_actor_name:=public.crystal_actor_name(v_actor);
  insert into public.crystal_admin_audit_log(actor_id,action,target_type,target_id,details)
  values(v_actor,'administrator_membership_changed','admin',v_uid::text,jsonb_build_object('role',p_role,'admin_name',v_actor_name));
  return v_uid;
end $$;
revoke all on function public.admin_set_membership(text,text,jsonb) from public,anon;
grant execute on function public.admin_set_membership(text,text,jsonb) to authenticated;

-- Currency conversion is held in Supabase and must be explicitly maintained by Supa Admin.
create table if not exists public.crystal_fx_rates (
  base_currency text not null check(base_currency in ('KES','USD','GBP')),
  quote_currency text not null check(quote_currency in ('KES','USD','GBP')),
  rate numeric(24,10) not null check(rate>0),
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  primary key(base_currency,quote_currency)
);
alter table public.crystal_fx_rates enable row level security;
drop policy if exists "Admins read FX rates" on public.crystal_fx_rates;
create policy "Admins read FX rates" on public.crystal_fx_rates for select to authenticated using(public.is_crystal_admin());
revoke all on public.crystal_fx_rates from anon,authenticated;
grant select on public.crystal_fx_rates to authenticated;

create or replace function public.admin_set_fx_rate(p_base text,p_quote text,p_rate numeric)
returns void language plpgsql security definer set search_path=''
as $$ begin
  if not exists(select 1 from public.crystal_admin_memberships where user_id=(select auth.uid()) and role='Supa Admin' and is_active=true) then raise exception 'Supa Admin permission required'; end if;
  perform public.crystal_require_admin_mfa();
  if p_base not in ('KES','USD','GBP') or p_quote not in ('KES','USD','GBP') or p_rate<=0 then raise exception 'Invalid FX rate'; end if;
  insert into public.crystal_fx_rates(base_currency,quote_currency,rate,updated_by)
  values(p_base,p_quote,case when p_base=p_quote then 1 else p_rate end,(select auth.uid()))
  on conflict(base_currency,quote_currency) do update set rate=excluded.rate,updated_by=excluded.updated_by,updated_at=now();
  insert into public.crystal_admin_audit_log(actor_id,action,target_type,target_id,details)
  values((select auth.uid()),'fx_rate_updated','fx_rate',p_base||'/'||p_quote,jsonb_build_object('rate',p_rate,'admin_name',public.crystal_actor_name((select auth.uid()))));
end $$;
revoke all on function public.admin_set_fx_rate(text,text,numeric) from public,anon;
grant execute on function public.admin_set_fx_rate(text,text,numeric) to authenticated;

create or replace function public.admin_get_financial_summary(p_display_currency text)
returns table(display_currency text,total_site_balance numeric,approved_deposits numeric,approved_withdrawals numeric,fx_rates_complete boolean)
language plpgsql security definer set search_path=''
as $$
declare v_complete boolean;
begin
  if not public.crystal_admin_has_permission('reports') then raise exception 'Reports permission required'; end if;
  if p_display_currency not in ('KES','USD','GBP') then raise exception 'Invalid display currency'; end if;
  select count(*)=9 into v_complete from public.crystal_fx_rates;
  return query
  with totals as (
    select a.currency,sum(a.amount) as principal from public.investment_allocations a where a.status='active' group by a.currency
  ), earnings as (
    select d.currency,sum(greatest(d.amount-d.redeemed_amount,0)) as amount from public.investment_daily_accruals d group by d.currency
  ), dep as (
    select d.currency,sum(d.amount) as amount from public.deposit_requests d where d.status='approved' group by d.currency
  ), wit as (
    select w.currency,sum(w.amount) as amount from public.withdrawal_requests w where w.status='approved' and w.posted_at is not null group by w.currency
  ), currency_rows as (
    select c.currency,coalesce(t.principal,0)+coalesce(e.amount,0) as balance,coalesce(dp.amount,0) as deposits,coalesce(wt.amount,0) as withdrawals
    from (select unnest(array['KES','USD','GBP']::text[]) currency) c
    left join totals t using(currency) left join earnings e using(currency) left join dep dp using(currency) left join wit wt using(currency)
  ), converted as (
    select cr.*,
      case when cr.currency=p_display_currency then 1 else fx.rate end as fx_rate
    from currency_rows cr left join public.crystal_fx_rates fx on fx.base_currency=cr.currency and fx.quote_currency=p_display_currency
  )
  select p_display_currency,
    case when bool_and(fx_rate is not null) then sum(balance*fx_rate) else null end,
    case when bool_and(fx_rate is not null) then sum(deposits*fx_rate) else null end,
    case when bool_and(fx_rate is not null) then sum(withdrawals*fx_rate) else null end,
    bool_and(fx_rate is not null)
  from converted;
end $$;
revoke all on function public.admin_get_financial_summary(text) from public,anon;
grant execute on function public.admin_get_financial_summary(text) to authenticated;

-- Future automatic verification adapter: provider events are idempotent and not writable by browser users.
create table if not exists public.crystal_deposit_verification_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  provider_event_id text not null,
  deposit_request_id uuid references public.deposit_requests(id) on delete restrict,
  provider_reference text not null,
  verification_status text not null check(verification_status in ('received','verified','rejected','review_required')),
  payload jsonb not null default '{}'::jsonb,
  received_at timestamptz not null default now(),
  unique(provider,provider_event_id)
);
alter table public.crystal_deposit_verification_events enable row level security;
revoke all on public.crystal_deposit_verification_events from anon,authenticated;
grant select,insert,update on public.crystal_deposit_verification_events to service_role;

-- Restrict admin membership visibility: no direct table access; use the masked RPC above.
revoke all on public.crystal_admin_memberships from anon,authenticated;
-- Existing permission helper remains the authorization source for Junior Admin module access.

comment on table public.crystal_deposit_verification_events is 'Server-side adapter table for future payment-provider verification; manual deposit review remains available.';
comment on table public.crystal_fx_rates is 'Supa Admin-maintained FX rates used for consolidated display only; original financial records retain their currency.';

create or replace function public.admin_list_financial_requests(p_request_type text)
returns table(
  id uuid, investor_id uuid, investor_name text, investor_email text, investor_phone text, investor_country text,
  amount numeric, currency text, status text, created_at timestamptz, reviewed_at timestamptz,
  reviewed_by_name text, payment_method text, payment_reference text, sender_name text, destination_details jsonb
)
language plpgsql security definer set search_path=''
as $$
declare v_supa boolean; v_reviewer text;
begin
  select exists(select 1 from public.crystal_admin_memberships m where m.user_id=(select auth.uid()) and m.role='Supa Admin' and m.is_active=true) into v_supa;
  if p_request_type='deposit' then
    if not public.crystal_admin_has_permission('deposit_approvals') then raise exception 'Deposit approval permission required'; end if;
    return query
    select d.id,d.investor_id,coalesce(p.full_name,'Investor'),coalesce(u.email,''),coalesce(p.phone,''),coalesce(p.country,''),
      d.amount,d.currency,d.status,d.created_at,d.reviewed_at,case when v_supa then coalesce(public.crystal_actor_name(d.reviewed_by),'') else case when coalesce(public.crystal_actor_name(d.reviewed_by),'')='' then '' else left(public.crystal_actor_name(d.reviewed_by),1)||repeat('*',greatest(length(public.crystal_actor_name(d.reviewed_by))-2,1))||right(public.crystal_actor_name(d.reviewed_by),1) end end,
      coalesce(d.payment_method,''),coalesce(d.payment_reference,''),coalesce(d.sender_name,''),'{}'::jsonb
    from public.deposit_requests d left join public.investor_profiles p on p.id=d.investor_id
    left join auth.users u on u.id=d.investor_id order by d.created_at desc;
  elsif p_request_type='withdrawal' then
    if not public.crystal_admin_has_permission('withdrawal_approvals') then raise exception 'Withdrawal approval permission required'; end if;
    return query
    select w.id,w.investor_id,coalesce(p.full_name,'Investor'),coalesce(u.email,''),coalesce(p.phone,''),coalesce(p.country,''),
      w.amount,w.currency,w.status,w.created_at,w.reviewed_at,case when v_supa then coalesce(public.crystal_actor_name(w.reviewed_by),'') else case when coalesce(public.crystal_actor_name(w.reviewed_by),'')='' then '' else left(public.crystal_actor_name(w.reviewed_by),1)||repeat('*',greatest(length(public.crystal_actor_name(w.reviewed_by))-2,1))||right(public.crystal_actor_name(w.reviewed_by),1) end end,
      coalesce(w.destination_details->>'method',''),coalesce(w.destination_details->>'transaction_reference',''),
      coalesce(w.destination_details->>'account_holder',''),coalesce(w.destination_details,'{}'::jsonb)
    from public.withdrawal_requests w left join public.investor_profiles p on p.id=w.investor_id
    left join auth.users u on u.id=w.investor_id order by w.created_at desc;
  else
    raise exception 'Invalid financial request type';
  end if;
end $$;
revoke all on function public.admin_list_financial_requests(text) from public,anon;
grant execute on function public.admin_list_financial_requests(text) to authenticated;

-- Only active, non-archived administrator conversation/support history is visible in the workspace.
drop policy if exists "Admins read conversations" on public.crystal_admin_conversations;
create policy "Admins read conversations" on public.crystal_admin_conversations
  for select to authenticated using (public.is_crystal_admin() and archived_at is null);

create or replace function public.crystal_admin_access()
returns jsonb language plpgsql stable security definer set search_path=''
as $$ declare v_row public.crystal_admin_memberships%rowtype;
begin
  select * into v_row from public.crystal_admin_memberships m where m.user_id=(select auth.uid()) and m.is_active=true;
  if not found then return '{}'::jsonb; end if;
  return jsonb_build_object('role',v_row.role,'permissions',coalesce(v_row.permissions,'{}'::jsonb),'display_name',coalesce(v_row.display_name,''));
end $$;
revoke all on function public.crystal_admin_access() from public,anon;
grant execute on function public.crystal_admin_access() to authenticated;

-- Record the human-readable administrator name on every membership action.
drop function if exists public.admin_set_membership(text,text,jsonb);
 create or replace function public.admin_set_membership(p_email text,p_role text,p_permissions jsonb default '{}'::jsonb,p_display_name text default '')
returns uuid language plpgsql security definer set search_path=''
as $$ declare v_uid uuid; v_actor uuid:=(select auth.uid()); v_actor_name text; v_count integer;
begin
  if not exists(select 1 from public.crystal_admin_memberships where user_id=v_actor and role='Supa Admin' and is_active=true) then raise exception 'Supa Admin permission required'; end if;
  perform public.crystal_require_admin_mfa();
  if p_role not in ('Supa Admin','Junior Admin') then raise exception 'Invalid administrator role'; end if;
  select id into v_uid from auth.users where lower(email)=lower(trim(p_email));
  if v_uid is null then raise exception 'Create the administrator login account first, then assign its role'; end if;
  if v_uid=v_actor and p_role<>'Supa Admin' then
    select count(*) into v_count from public.crystal_admin_memberships where role='Supa Admin' and is_active=true;
    if v_count<=1 then raise exception 'The last Supa Admin cannot be demoted'; end if;
  end if;
  insert into public.crystal_admin_memberships(user_id,role,permissions,is_active,display_name)
  values(v_uid,p_role,case when p_role='Supa Admin' then '{}'::jsonb else coalesce(p_permissions,'{}'::jsonb) end,true,left(trim(coalesce(p_display_name,'')),160))
  on conflict(user_id) do update set role=excluded.role,permissions=excluded.permissions,is_active=true,display_name=case when excluded.display_name<>'' then excluded.display_name else public.crystal_admin_memberships.display_name end,updated_at=now();
  v_actor_name:=public.crystal_actor_name(v_actor);
  insert into public.crystal_admin_audit_log(actor_id,action,target_type,target_id,details)
  values(v_actor,'administrator_membership_changed','admin',v_uid::text,jsonb_build_object('role',p_role,'admin_name',v_actor_name,'subject_admin_name',coalesce(nullif(trim(p_display_name),''),p_email)));
  return v_uid;
end $$;
revoke all on function public.admin_set_membership(text,text,jsonb,text) from public,anon;
grant execute on function public.admin_set_membership(text,text,jsonb,text) to authenticated;

create or replace function public.admin_remove_membership(p_user_id uuid)
returns void language plpgsql security definer set search_path=''
as $$ declare v_role text; v_count integer; v_actor uuid:=(select auth.uid());
begin
  if not exists(select 1 from public.crystal_admin_memberships where user_id=v_actor and role='Supa Admin' and is_active=true) then raise exception 'Supa Admin permission required'; end if;
  perform public.crystal_require_admin_mfa();
  select role into v_role from public.crystal_admin_memberships where user_id=p_user_id and is_active=true;
  if v_role='Supa Admin' then
    select count(*) into v_count from public.crystal_admin_memberships where role='Supa Admin' and is_active=true;
    if v_count<=1 then raise exception 'The last Supa Admin cannot be removed'; end if;
  end if;
  update public.crystal_admin_memberships set is_active=false,updated_at=now() where user_id=p_user_id and is_active=true;
  if not found then raise exception 'Administrator membership not found'; end if;
  insert into public.crystal_admin_audit_log(actor_id,action,target_type,target_id,details)
  values(v_actor,'administrator_membership_removed','admin',p_user_id::text,jsonb_build_object('admin_name',public.crystal_actor_name(v_actor),'removed_admin_name',public.crystal_actor_name(p_user_id)));
end $$;
revoke all on function public.admin_remove_membership(uuid) from public,anon;
grant execute on function public.admin_remove_membership(uuid) to authenticated;

-- Replace the earlier destructive support clear function with Supa Admin-only archiving.
create or replace function public.admin_clear_resolved_support_messages()
returns integer language plpgsql security definer set search_path=''
as $$ begin return public.admin_clear_support_history(); end $$;
revoke all on function public.admin_clear_resolved_support_messages() from public,anon;
grant execute on function public.admin_clear_resolved_support_messages() to authenticated;

-- Apply module-level access to opportunity management and audit history.
drop policy if exists "Admins manage opportunities" on public.investment_opportunities;
create policy "Admins manage opportunities" on public.investment_opportunities
  for all to authenticated using(public.crystal_admin_has_permission('opportunities'))
  with check(public.crystal_admin_has_permission('opportunities'));
drop policy if exists "admins read audit log" on public.crystal_admin_audit_log;
drop policy if exists "Admins read audit log" on public.crystal_admin_audit_log;
create policy "Admins read audit log" on public.crystal_admin_audit_log
  for select to authenticated using(public.crystal_admin_has_permission('reports') or exists(
    select 1 from public.crystal_admin_memberships m where m.user_id=(select auth.uid()) and m.role='Supa Admin' and m.is_active=true
  ));

create or replace function public.admin_update_opportunity_status(p_opportunity_id uuid,p_status text)
returns void language plpgsql security definer set search_path=''
as $$
declare v_division text;
begin
  if not public.crystal_admin_has_permission('opportunities') then raise exception 'Opportunity management permission required'; end if;
  perform public.crystal_require_admin_mfa();
  if p_status not in ('Draft','Under Review','Active','Paused','Closed','Archived') then raise exception 'Invalid opportunity status'; end if;
  update public.investment_opportunities set status=p_status,updated_at=now() where id=p_opportunity_id returning division into v_division;
  if v_division is null then raise exception 'Opportunity not found'; end if;
  insert into public.crystal_admin_audit_log(actor_id,action,target_type,target_id,details)
  values((select auth.uid()),'investment_division_status_changed','investment_opportunity',p_opportunity_id::text,
    jsonb_build_object('division',v_division,'status',p_status,'admin_name',public.crystal_actor_name((select auth.uid()))));
end $$;
revoke all on function public.admin_update_opportunity_status(uuid,text) from public,anon;
grant execute on function public.admin_update_opportunity_status(uuid,text) to authenticated;

create or replace function public.crystal_attach_audit_actor_name()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if new.actor_id is not null then
    new.details:=jsonb_set(coalesce(new.details,'{}'::jsonb),'{admin_name}',to_jsonb(coalesce(public.crystal_actor_name(new.actor_id),'Administrator')),true);
  end if;
  return new;
end $$;
revoke all on function public.crystal_attach_audit_actor_name() from public,anon,authenticated;
drop trigger if exists crystal_audit_actor_name on public.crystal_admin_audit_log;
create trigger crystal_audit_actor_name before insert on public.crystal_admin_audit_log
for each row execute function public.crystal_attach_audit_actor_name();

-- Strong authentication is enforced by the database for privileged administrator actions.

create or replace function public.admin_set_global_interest_rate(p_annual_rate numeric,p_day_count_basis integer,p_effective_at timestamptz default now())
returns uuid language plpgsql security definer set search_path=''
as $$ declare v_id uuid;
begin
  if not exists(select 1 from public.crystal_admin_memberships m where m.user_id=(select auth.uid()) and m.role='Supa Admin' and m.is_active=true) then raise exception 'Supa Admin permission required'; end if;
  perform public.crystal_require_admin_mfa();
  if p_annual_rate<0 or p_annual_rate>100 or p_day_count_basis not in (360,365) then raise exception 'Invalid annual rate or day-count basis'; end if;
  if p_effective_at>now()+interval '1 day' then raise exception 'Effective date cannot be more than one day in the future'; end if;
  insert into public.crystal_interest_rate_history(annual_rate,day_count_basis,effective_at,created_by)
  values(p_annual_rate,p_day_count_basis,coalesce(p_effective_at,now()),(select auth.uid())) returning id into v_id;
  insert into public.crystal_admin_audit_log(actor_id,action,target_type,target_id,details)
  values((select auth.uid()),'global_interest_rate_changed','interest_rate',v_id::text,jsonb_build_object('annual_rate',p_annual_rate,'day_count_basis',p_day_count_basis,'effective_at',p_effective_at));
  return v_id;
end $$;
revoke all on function public.admin_set_global_interest_rate(numeric,integer,timestamptz) from public,anon;
grant execute on function public.admin_set_global_interest_rate(numeric,integer,timestamptz) to authenticated;

drop policy if exists "Admins read interest rate history" on public.crystal_interest_rate_history;
create policy "Supa Admins read interest rate history" on public.crystal_interest_rate_history
  for select to authenticated using(exists(select 1 from public.crystal_admin_memberships m where m.user_id=(select auth.uid()) and m.role='Supa Admin' and m.is_active=true));

-- Public website configuration is served from Supabase; writes remain permission-controlled.
drop policy if exists "admins read site config" on public.crystal_site_configuration;
drop policy if exists "Admins read site configuration" on public.crystal_site_configuration;
create policy "Admins read site configuration" on public.crystal_site_configuration
  for select to authenticated using(
    (config_key='website_content' and public.crystal_admin_has_permission('website_content')) or
    (config_key='platform_settings' and public.crystal_admin_has_permission('platform_settings'))
  );

create or replace function public.admin_save_site_configuration(p_key text,p_value jsonb)
returns void language plpgsql security definer set search_path=''
as $$
begin
  if p_key='website_content' and not public.crystal_admin_has_permission('website_content') then raise exception 'Website content permission required'; end if;
  if p_key='platform_settings' and not public.crystal_admin_has_permission('platform_settings') then raise exception 'Platform settings permission required'; end if;
  if p_key='platform_settings' and (coalesce(p_value,'{}'::jsonb) ? 'financial_operations_enabled') and not exists(select 1 from public.crystal_admin_memberships m where m.user_id=(select auth.uid()) and m.role='Supa Admin' and m.is_active=true) then raise exception 'Supa Admin permission required for financial operations controls'; end if;
  if p_key not in ('platform_settings','website_content') then raise exception 'Invalid configuration key'; end if;
  insert into public.crystal_site_configuration(config_key,config_value,updated_by)
  values(p_key,coalesce(p_value,'{}'::jsonb),(select auth.uid()))
  on conflict(config_key) do update set config_value=crystal_site_configuration.config_value||excluded.config_value,updated_by=excluded.updated_by,updated_at=now();
  insert into public.crystal_admin_audit_log(actor_id,action,target_type,target_id,details)
  values((select auth.uid()),'site_configuration_saved',p_key,p_key,'{}'::jsonb);
end $$;
revoke all on function public.admin_save_site_configuration(text,jsonb) from public,anon;
grant execute on function public.admin_save_site_configuration(text,jsonb) to authenticated;

create or replace function public.get_crystal_site_configuration(p_key text)
returns jsonb language sql stable security definer set search_path=''
as $$
  select case when p_key='platform_settings' then coalesce(c.config_value,'{}'::jsonb)-'financial_operations_enabled' else coalesce(c.config_value,'{}'::jsonb) end
  from public.crystal_site_configuration c
  where c.config_key=p_key and p_key in ('platform_settings','website_content')
$$;
revoke all on function public.get_crystal_site_configuration(text) from public;
grant execute on function public.get_crystal_site_configuration(text) to anon,authenticated;

insert into public.crystal_site_configuration(config_key,config_value)
values
 ('platform_settings',jsonb_build_object('headquarters','Kenya','defaultCurrency','KES','footerTagline','Investing Today. Building Tomorrow.','financial_operations_enabled',false)),
 ('website_content',jsonb_build_object(
   'homeEyebrow','A considered approach to investing',
   'homeDescription','We explore investment opportunities across sectors and markets, guided by disciplined evaluation, thoughtful capital allocation and a long-term perspective.',
   'aboutIntro','Headquartered in Kenya, Crystal Investments explores relevant opportunities around the world, across a diverse range of industries and markets.',
   'opportunitiesIntro','We consider opportunities worldwide, from operating businesses and real assets to infrastructure, technology and eligible financial markets.',
   'partners',jsonb_build_array(
     jsonb_build_object('name','Safaricom','mark','S','domain','safaricom.co.ke','logo','https://commons.wikimedia.org/wiki/Special:Redirect/file/Safaricom-logo-png_seeklogo-530479.svg','color','#e8f5e9','ink','#16833b'),
     jsonb_build_object('name','KCB Group','mark','KCB','domain','kcbgroup.com','logo','https://cdn.brandfetch.io/kcbgroup.com?c=1bxid64Mup7aczewSAYMX&w=512&h=512','color','#eaf4e8','ink','#17634d'),
     jsonb_build_object('name','Equity Group','mark','EQUITY','domain','equitygroupholdings.com','logo','https://cdn.brandfetch.io/equitygroupholdings.com?c=1bxid64Mup7aczewSAYMX&w=512&h=512','color','#fff0e9','ink','#bd3d28'),
     jsonb_build_object('name','Kenya Development Corporation','mark','KDC','domain','kdc.go.ke','logo','https://cdn.brandfetch.io/kdc.go.ke?c=1bxid64Mup7aczewSAYMX&w=512&h=512','color','#f8eee3','ink','#8a5525'),
     jsonb_build_object('name','International Finance Corporation','mark','IFC','domain','ifc.org','logo','https://cdn.brandfetch.io/ifc.org?c=1bxid64Mup7aczewSAYMX&w=512&h=512','color','#e8f1f8','ink','#17618a'),
     jsonb_build_object('name','African Development Bank','mark','AfDB','domain','afdb.org','logo','https://cdn.brandfetch.io/afdb.org?c=1bxid64Mup7aczewSAYMX&w=512&h=512','color','#e9f0f8','ink','#244e82')
   ),
   'regulators',jsonb_build_array(
     jsonb_build_object('name','Capital Markets Authority · Kenya','mark','CMA','domain','cma.or.ke','logo','https://commons.wikimedia.org/wiki/Special:Redirect/file/CMA_Logo.png','color','#f5edf7','ink','#6a3479'),
     jsonb_build_object('name','Central Bank of Kenya','mark','CBK','domain','centralbank.go.ke','logo','https://cdn.brandfetch.io/centralbank.go.ke?c=1bxid64Mup7aczewSAYMX&w=512&h=512','color','#f7f0e3','ink','#765b28'),
     jsonb_build_object('name','Insurance Regulatory Authority · Kenya','mark','IRA','domain','ira.go.ke','logo','https://cdn.brandfetch.io/ira.go.ke?c=1bxid64Mup7aczewSAYMX&w=512&h=512','color','#eaf2f8','ink','#285d84'),
     jsonb_build_object('name','Retirement Benefits Authority · Kenya','mark','RBA','domain','rba.go.ke','logo','https://cdn.brandfetch.io/rba.go.ke?c=1bxid64Mup7aczewSAYMX&w=512&h=512','color','#edf3e8','ink','#47733b'),
     jsonb_build_object('name','Financial Conduct Authority · UK','mark','FCA','domain','fca.org.uk','logo','https://www.fca.org.uk/sites/all/themes/fca/logo.png','color','#edf0f7','ink','#293b62'),
     jsonb_build_object('name','U.S. Securities and Exchange Commission','mark','SEC','domain','sec.gov','logo','https://cdn.brandfetch.io/sec.gov?c=1bxid64Mup7aczewSAYMX&w=512&h=512','color','#f7ecec','ink','#8b2f37'),
     jsonb_build_object('name','Financial Sector Conduct Authority · South Africa','mark','FSCA','domain','fsca.co.za','logo','https://cdn.brandfetch.io/fsca.co.za?c=1bxid64Mup7aczewSAYMX&w=512&h=512','color','#e8f2f1','ink','#286b63')
   )
 ))
on conflict(config_key) do update set config_value=case when excluded.config_key='platform_settings' then (excluded.config_value||crystal_site_configuration.config_value)||jsonb_build_object('financial_operations_enabled',false) else (excluded.config_value-'partners'-'regulators')||crystal_site_configuration.config_value||jsonb_build_object('partners',coalesce(crystal_site_configuration.config_value->'partners',excluded.config_value->'partners'),'regulators',coalesce(crystal_site_configuration.config_value->'regulators',excluded.config_value->'regulators')) end;

create or replace function public.public_get_investment_divisions()
returns table(id uuid,title text,division text,summary text,description text,risk_disclosure text)
language sql stable security definer set search_path=''
as $$
  select o.id,o.title,o.division,o.summary,o.description,o.risk_disclosure
  from public.investment_opportunities o
  where o.division in ('Energy & Petroleum','Agriculture & Agribusiness','Real Estate & Infrastructure','Mining & Minerals','Shipping & Logistics','Technology & Innovation','Global Markets & Securities','General Investments & Acquisitions')
  order by array_position(array['Energy & Petroleum','Agriculture & Agribusiness','Real Estate & Infrastructure','Mining & Minerals','Shipping & Logistics','Technology & Innovation','Global Markets & Securities','General Investments & Acquisitions']::text[],o.division);
$$;
revoke all on function public.public_get_investment_divisions() from public;
grant execute on function public.public_get_investment_divisions() to anon,authenticated;

-- All investor-facing market observations are read from Supabase, never browser storage.
drop policy if exists "authenticated read market conditions" on public.market_conditions;
create policy "authenticated read market conditions" on public.market_conditions
  for select to authenticated using(true);

-- Remove broad legacy Junior Admin policies and restore least-privilege module checks.
drop policy if exists "Admins manage allocations" on public.investment_allocations;
drop policy if exists "Admins read investor allocations" on public.investment_allocations;
create policy "Admins read investor allocations" on public.investment_allocations
  for select to authenticated using(public.crystal_admin_has_permission('portfolio'));

 drop policy if exists "Admins can view investor profiles" on public.investor_profiles;
create policy "Admins can view investor profiles" on public.investor_profiles
  for select to authenticated using(public.crystal_admin_has_permission('investors'));

drop policy if exists "Admins read audit log" on public.crystal_admin_audit_log;
create policy "Admins read audit log" on public.crystal_admin_audit_log
  for select to authenticated using(public.crystal_admin_has_permission('reports'));

-- The portfolio screen is read-only for automatic deposit allocations; no manual project allocation RPC remains available.
revoke all on function public.admin_create_investment_allocation(text,text,numeric,text,text) from public,anon,authenticated;
revoke all on function public.admin_set_investment_allocation_status(uuid,text) from public,anon,authenticated;
revoke all on function public.admin_adjust_investment_allocation_principal(uuid,numeric) from public,anon,authenticated;
create or replace function public.admin_list_auto_investment_allocations()
returns table(
 id uuid,investor_email text,project_name text,division text,opportunity_id uuid,source_deposit_id uuid,
 amount numeric,currency text,annual_rate numeric,day_count_basis integer,terms_reference text,status text,
 activated_at timestamptz,created_at timestamptz
)
language plpgsql security definer set search_path=''
as $$ begin
  if not public.crystal_admin_has_permission('portfolio') then raise exception 'Portfolio permission required'; end if;
  return query
  select a.id,coalesce(u.email,''),a.project_name,o.division,a.opportunity_id,a.source_deposit_id,a.amount,a.currency,a.annual_rate,a.day_count_basis,a.terms_reference,a.status,a.activated_at,a.created_at
  from public.investment_allocations a left join public.investment_opportunities o on o.id=a.opportunity_id
  left join auth.users u on u.id=a.investor_id order by a.created_at desc;
end $$;
revoke all on function public.admin_list_auto_investment_allocations() from public,anon;
grant execute on function public.admin_list_auto_investment_allocations() to authenticated;

-- Supabase-backed compliance review.
drop policy if exists "Admins review documents" on public.investor_documents;
create policy "Admins read investor documents" on public.investor_documents
  for select to authenticated using(public.crystal_admin_has_permission('kyc'));
revoke insert,update,delete on public.investor_documents from authenticated;
grant select,insert on public.investor_documents to authenticated;

create or replace function public.admin_review_investor_document(p_document_id uuid,p_status text)
returns void language plpgsql security definer set search_path=''
as $$ declare v_actor uuid:=(select auth.uid());
begin
  if not public.crystal_admin_has_permission('kyc') then raise exception 'KYC permission required'; end if;
  if p_status not in ('Under Review','Accepted','Rejected','Expired') then raise exception 'Invalid document status'; end if;
  update public.investor_documents set status=p_status,reviewed_by=v_actor,reviewed_at=now() where id=p_document_id;
  if not found then raise exception 'Investor document not found'; end if;
  insert into public.crystal_admin_audit_log(actor_id,action,target_type,target_id,details)
  values(v_actor,'investor_document_reviewed','investor_document',p_document_id::text,jsonb_build_object('status',p_status));
end $$;
revoke all on function public.admin_review_investor_document(uuid,text) from public,anon;
grant execute on function public.admin_review_investor_document(uuid,text) to authenticated;

-- Supabase-backed distributions; only explicitly assigned admins may review them.
drop policy if exists "Admins manage distributions" on public.investment_distributions;
create policy "Admins read distributions" on public.investment_distributions
  for select to authenticated using(public.crystal_admin_has_permission('distributions'));
revoke insert,update,delete on public.investment_distributions from authenticated;
grant select on public.investment_distributions to authenticated;

create or replace function public.admin_list_investment_distributions()
returns table(id uuid,investor_name text,investor_email text,project_name text,amount numeric,currency text,distribution_date date,status text,description text)
language plpgsql security definer set search_path=''
as $$ begin
 if not public.crystal_admin_has_permission('distributions') then raise exception 'Distribution permission required'; end if;
 return query select d.id,coalesce(p.full_name,'Investor'),coalesce(u.email,''),a.project_name,d.amount,d.currency,d.distribution_date,d.status,d.description
 from public.investment_distributions d left join public.investment_allocations a on a.id=d.allocation_id
 left join public.investor_profiles p on p.id=d.investor_id left join auth.users u on u.id=d.investor_id
 order by d.distribution_date desc,d.created_at desc;
end $$;
revoke all on function public.admin_list_investment_distributions() from public,anon;
grant execute on function public.admin_list_investment_distributions() to authenticated;

create or replace function public.admin_update_distribution_status(p_distribution_id uuid,p_status text)
returns void language plpgsql security definer set search_path=''
as $$ begin
 if not public.crystal_admin_has_permission('distributions') then raise exception 'Distribution permission required'; end if;
 if p_status not in ('Draft','Approved','Paid','Cancelled') then raise exception 'Invalid distribution status'; end if;
 update public.investment_distributions set status=p_status,approved_by=case when p_status='Approved' then (select auth.uid()) else approved_by end,paid_at=case when p_status='Paid' then now() else paid_at end where id=p_distribution_id;
 if not found then raise exception 'Distribution not found'; end if;
 insert into public.crystal_admin_audit_log(actor_id,action,target_type,target_id,details)
 values((select auth.uid()),'investment_distribution_status_changed','distribution',p_distribution_id::text,jsonb_build_object('status',p_status));
end $$;
revoke all on function public.admin_update_distribution_status(uuid,text) from public,anon;
grant execute on function public.admin_update_distribution_status(uuid,text) to authenticated;

-- Supa Admin / assigned team admins can manage confirmed branch records.
create table if not exists public.crystal_branches(
 id uuid primary key default gen_random_uuid(),name text not null,location text not null,country text not null,
 contact_email text not null default '',contact_phone text not null default '',status text not null default 'Active' check(status in ('Active','Inactive')),
 created_by uuid references auth.users(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
alter table public.crystal_branches enable row level security;
drop policy if exists "Admins read branches" on public.crystal_branches;
create policy "Admins read branches" on public.crystal_branches for select to authenticated using(public.crystal_admin_has_permission('team'));
revoke all on public.crystal_branches from anon,authenticated;
grant select on public.crystal_branches to authenticated;

create or replace function public.admin_save_branch(p_id uuid,p_name text,p_location text,p_country text,p_email text,p_phone text,p_status text)
returns uuid language plpgsql security definer set search_path=''
as $$ declare v_id uuid;
begin
 if not public.crystal_admin_has_permission('team') then raise exception 'Team management permission required'; end if;
 if length(trim(coalesce(p_name,'')))<2 or length(trim(coalesce(p_location,'')))<2 or length(trim(coalesce(p_country,'')))<2 or p_status not in ('Active','Inactive') then raise exception 'Invalid branch details'; end if;
 if p_id is null then
  insert into public.crystal_branches(name,location,country,contact_email,contact_phone,status,created_by)
  values(left(trim(p_name),160),left(trim(p_location),160),left(trim(p_country),100),left(trim(coalesce(p_email,'')),254),left(trim(coalesce(p_phone,'')),60),p_status,(select auth.uid())) returning id into v_id;
 else
  update public.crystal_branches set name=left(trim(p_name),160),location=left(trim(p_location),160),country=left(trim(p_country),100),contact_email=left(trim(coalesce(p_email,'')),254),contact_phone=left(trim(coalesce(p_phone,'')),60),status=p_status,updated_at=now() where id=p_id returning id into v_id;
  if v_id is null then raise exception 'Branch not found'; end if;
 end if;
 insert into public.crystal_admin_audit_log(actor_id,action,target_type,target_id,details)
 values((select auth.uid()),'branch_saved','branch',v_id::text,jsonb_build_object('name',p_name,'status',p_status));
 return v_id;
end $$;
revoke all on function public.admin_save_branch(uuid,text,text,text,text,text,text) from public,anon;
grant execute on function public.admin_save_branch(uuid,text,text,text,text,text,text) to authenticated;

create or replace function public.admin_delete_branch(p_id uuid)
returns void language plpgsql security definer set search_path=''
as $$ begin
 if not public.crystal_admin_has_permission('team') then raise exception 'Team management permission required'; end if;
 delete from public.crystal_branches where id=p_id;
 if not found then raise exception 'Branch not found'; end if;
 insert into public.crystal_admin_audit_log(actor_id,action,target_type,target_id,details)
 values((select auth.uid()),'branch_deleted','branch',p_id::text,'{}'::jsonb);
end $$;
revoke all on function public.admin_delete_branch(uuid) from public,anon;
grant execute on function public.admin_delete_branch(uuid) to authenticated;

create or replace function public.crystal_attach_audit_actor_name()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if new.actor_id is not null then
    perform public.crystal_require_admin_mfa();
    new.details:=jsonb_set(coalesce(new.details,'{}'::jsonb),'{admin_name}',to_jsonb(coalesce(public.crystal_actor_name(new.actor_id),'Administrator')),true);
  end if;
  return new;
end $$;
revoke all on function public.crystal_attach_audit_actor_name() from public,anon,authenticated;

create or replace function public.admin_update_own_display_name(p_display_name text)
returns void language plpgsql security definer set search_path=''
as $$ begin
  if not public.is_crystal_admin() then raise exception 'Administrator access required'; end if;
  perform public.crystal_require_admin_mfa();
  if length(trim(coalesce(p_display_name,'')))<2 or length(trim(p_display_name))>160 then raise exception 'Enter a valid administrator name'; end if;
  update public.crystal_admin_memberships set display_name=trim(p_display_name),updated_at=now() where user_id=(select auth.uid());
  insert into public.crystal_admin_audit_log(actor_id,action,target_type,target_id,details)
  values((select auth.uid()),'administrator_display_name_updated','admin',(select auth.uid())::text,jsonb_build_object('display_name',trim(p_display_name)));
end $$;
revoke all on function public.admin_update_own_display_name(text) from public,anon;
grant execute on function public.admin_update_own_display_name(text) to authenticated;

create or replace function public.admin_list_kyc_investor_names()
returns table(id uuid,full_name text)
language plpgsql security definer set search_path=''
as $$ begin
 if not public.crystal_admin_has_permission('kyc') then raise exception 'KYC permission required'; end if;
 return query select p.id,p.full_name from public.investor_profiles p;
end $$;
revoke all on function public.admin_list_kyc_investor_names() from public,anon;
grant execute on function public.admin_list_kyc_investor_names() to authenticated;

drop policy if exists "Active opportunities visible to authenticated investors" on public.investment_opportunities;
create policy "Active opportunities visible to authenticated investors" on public.investment_opportunities
  for select to authenticated using(status='Active' or public.crystal_admin_has_permission('opportunities'));

-- Activity is exposed through a controlled feed so Junior Admins cannot read other admins' full identities.
revoke select on public.crystal_admin_audit_log from authenticated;
create or replace function public.admin_list_activity_feed()
returns table(id uuid,action text,target_type text,details jsonb,created_at timestamptz)
language plpgsql security definer set search_path=''
as $$
declare v_supa boolean;
begin
  if not public.is_crystal_admin() then raise exception 'Administrator access required'; end if;
  select exists(select 1 from public.crystal_admin_memberships m where m.user_id=(select auth.uid()) and m.role='Supa Admin' and m.is_active=true) into v_supa;
  return query
  select l.id,l.action,l.target_type,
    case when v_supa then l.details else
      jsonb_set(
        jsonb_set(
          jsonb_set(coalesce(l.details,'{}'::jsonb),'{admin_name}',
            to_jsonb(case when coalesce(l.details->>'admin_name','')='' then '' else left(l.details->>'admin_name',1)||repeat('*',greatest(length(l.details->>'admin_name')-2,1))||right(l.details->>'admin_name',1) end),true),
          '{subject_admin_name}',to_jsonb(case when coalesce(l.details->>'subject_admin_name','')='' then '' else left(l.details->>'subject_admin_name',1)||repeat('*',greatest(length(l.details->>'subject_admin_name')-2,1))||right(l.details->>'subject_admin_name',1) end),true),
        '{email}',to_jsonb(case when coalesce(l.details->>'email','')='' then '' else left(split_part(l.details->>'email','@',1),1)||repeat('*',greatest(length(split_part(l.details->>'email','@',1))-2,1))||right(split_part(l.details->>'email','@',1),1)||'@'||split_part(l.details->>'email','@',2) end),true)
    end,
    l.created_at
  from public.crystal_admin_audit_log l where l.archived_at is null order by l.created_at desc limit 500;
end $$;
revoke all on function public.admin_list_activity_feed() from public,anon;
grant execute on function public.admin_list_activity_feed() to authenticated;

drop policy if exists "Admins read support inbox" on public.crystal_support_messages;
create policy "Admins read support inbox" on public.crystal_support_messages
  for select to authenticated using(public.crystal_admin_has_permission('support') and archived_at is null);

-- Keep the deposit request form aligned with the live database shape, including payer details.
alter table public.deposit_requests
  add column if not exists sender_name text not null default '';
drop function if exists public.investor_submit_deposit(numeric,text,text,text);
drop function if exists public.investor_submit_deposit(numeric,text,text,text,text);
create function public.investor_submit_deposit(p_amount numeric,p_currency text,p_method text,p_reference text,p_sender_name text)
returns uuid language plpgsql security definer set search_path=''
as $$ declare v_id uuid; v_method text:=trim(coalesce(p_method,'')); v_sender text:=trim(coalesce(p_sender_name,'')); v_reference text:=trim(coalesce(p_reference,''));
begin
  if (select auth.uid()) is null then raise exception 'Authentication required'; end if;
  if p_amount is null or p_amount<=0 or p_currency not in ('KES','USD','GBP') then raise exception 'Invalid deposit amount or currency'; end if;
  if not coalesce((select c.config_value->>'financial_operations_enabled'='true' from public.crystal_site_configuration c where c.config_key='platform_settings'),false) then raise exception 'Deposits are not currently available'; end if;
  if v_method not in ('M-Pesa prompt','Bank transfer') or length(v_sender)<3 or length(v_sender)>160 then raise exception 'Enter valid payment method and payer details'; end if;
  if v_method='Bank transfer' and length(v_reference)<3 then raise exception 'Bank transfer reference is required'; end if;
  insert into public.deposit_requests(investor_id,amount,currency,payment_method,payment_reference,sender_name,verification_mode)
  values((select auth.uid()),p_amount,p_currency,v_method,left(v_reference,160),left(v_sender,160),'manual') returning id into v_id;
  return v_id;
end $$;
revoke all on function public.investor_submit_deposit(numeric,text,text,text,text) from public,anon;
grant execute on function public.investor_submit_deposit(numeric,text,text,text,text) to authenticated;

-- Replace legacy broad policies that allowed every administrator to see every investor record.
drop policy if exists "Investors read own deposit requests" on public.deposit_requests;
drop policy if exists "investors read own deposits" on public.deposit_requests;
drop policy if exists "Admins review deposit requests" on public.deposit_requests;
create policy "Investors read own deposit requests" on public.deposit_requests
  for select to authenticated using(investor_id=(select auth.uid()));
drop policy if exists "Admins read deposit requests" on public.deposit_requests;
create policy "Admins read deposit requests" on public.deposit_requests
  for select to authenticated using(public.crystal_admin_has_permission('deposit_approvals'));

drop policy if exists "Investors read own withdrawal requests" on public.withdrawal_requests;
drop policy if exists "investors read own withdrawals" on public.withdrawal_requests;
drop policy if exists "Admins review withdrawal requests" on public.withdrawal_requests;
create policy "Investors read own withdrawal requests" on public.withdrawal_requests
  for select to authenticated using(investor_id=(select auth.uid()));
drop policy if exists "Admins read withdrawal requests" on public.withdrawal_requests;
create policy "Admins read withdrawal requests" on public.withdrawal_requests
  for select to authenticated using(public.crystal_admin_has_permission('withdrawal_approvals'));

drop policy if exists "Investors read own allocations" on public.investment_allocations;
drop policy if exists "investors read own allocations" on public.investment_allocations;
create policy "Investors read own allocations" on public.investment_allocations
  for select to authenticated using(investor_id=(select auth.uid()));
drop policy if exists "Admins read investor allocations" on public.investment_allocations;
create policy "Admins read investor allocations" on public.investment_allocations
  for select to authenticated using(public.crystal_admin_has_permission('portfolio'));

 drop policy if exists "Investors read own ledger" on public.investor_ledger_entries;
create policy "Investors read own ledger" on public.investor_ledger_entries
  for select to authenticated using(investor_id=(select auth.uid()) or public.crystal_admin_has_permission('portfolio'));
drop policy if exists "Admins insert ledger entries" on public.investor_ledger_entries;
revoke insert,update,delete on public.investor_ledger_entries from authenticated;
grant select on public.investor_ledger_entries to authenticated;

drop policy if exists "Investors read own distributions" on public.investment_distributions;
create policy "Investors read own distributions" on public.investment_distributions
  for select to authenticated using(investor_id=(select auth.uid()));

drop policy if exists "Investors read own documents" on public.investor_documents;
create policy "Investors read own documents" on public.investor_documents
  for select to authenticated using(investor_id=(select auth.uid()));

create or replace function public.admin_list_referral_investors()
returns table(id uuid,full_name text,referral_code text)
language plpgsql security definer set search_path=''
as $$ begin
 if not public.crystal_admin_has_permission('referrals') then raise exception 'Referral management permission required'; end if;
 return query select p.id,p.full_name,p.referral_code from public.investor_profiles p order by p.created_at desc limit 500;
end $$;
revoke all on function public.admin_list_referral_investors() from public,anon;
grant execute on function public.admin_list_referral_investors() to authenticated;

drop policy if exists "Admins read FX rates" on public.crystal_fx_rates;
drop policy if exists "Authenticated read FX rates" on public.crystal_fx_rates;
create policy "Authenticated read FX rates" on public.crystal_fx_rates
  for select to authenticated using(true);

-- Require a verified AAL2 session for all admin module reads and actions, not only the UI gate.
create or replace function public.is_crystal_admin()
returns boolean language sql stable security definer set search_path=''
as $$
  select coalesce((select auth.jwt()->>'aal'),'aal1')='aal2' and exists(
    select 1 from public.crystal_admin_memberships m where m.user_id=(select auth.uid()) and m.is_active=true
  );
$$;
revoke all on function public.is_crystal_admin() from public,anon;
grant execute on function public.is_crystal_admin() to authenticated;

create or replace function public.crystal_admin_has_permission(p_permission text)
returns boolean language sql stable security definer set search_path=''
as $$
  select coalesce((select auth.jwt()->>'aal'),'aal1')='aal2' and exists(
    select 1 from public.crystal_admin_memberships m where m.user_id=(select auth.uid()) and m.is_active=true
      and (m.role='Supa Admin' or coalesce((m.permissions->>p_permission)::boolean,false))
  );
$$;
revoke all on function public.crystal_admin_has_permission(text) from public,anon;
grant execute on function public.crystal_admin_has_permission(text) to authenticated;

create or replace function public.can_manage_crystal_referrals()
returns boolean language sql stable security definer set search_path=''
as $$
  select coalesce((select auth.jwt()->>'aal'),'aal1')='aal2' and exists(
    select 1 from public.crystal_admin_memberships m where m.user_id=(select auth.uid()) and m.is_active=true
      and (m.role='Supa Admin' or coalesce((m.permissions->>'referrals')::boolean,false))
  );
$$;
revoke all on function public.can_manage_crystal_referrals() from public,anon;
grant execute on function public.can_manage_crystal_referrals() to authenticated;
revoke all on function public.crystal_actor_name(uuid) from public,anon,authenticated;

-- Retire legacy parallel admin tables from browser access; crystal_admin_memberships is authoritative.
revoke all on public.admin_memberships,public.admin_audit_logs,public.platform_settings from anon,authenticated;
create or replace function public.crystal_is_admin()
returns boolean language sql stable security definer set search_path=''
as $$ select public.is_crystal_admin(); $$;
create or replace function public.crystal_is_supa_admin()
returns boolean language sql stable security definer set search_path=''
as $$
 select coalesce((select auth.jwt()->>'aal'),'aal1')='aal2' and exists(
   select 1 from public.crystal_admin_memberships m where m.user_id=(select auth.uid()) and m.role='Supa Admin' and m.is_active=true
 );
$$;
revoke all on function public.crystal_is_admin() from public,anon;
revoke all on function public.crystal_is_supa_admin() from public,anon;
grant execute on function public.crystal_is_admin() to authenticated;
grant execute on function public.crystal_is_supa_admin() to authenticated;

revoke select on public.crystal_admin_conversations from authenticated;
create or replace function public.admin_list_conversation_history()
returns table(id uuid,sender_label text,message text,created_at timestamptz)
language plpgsql security definer set search_path=''
as $$ declare v_supa boolean;
begin
  if not public.is_crystal_admin() then raise exception 'Administrator access required'; end if;
  select exists(select 1 from public.crystal_admin_memberships m where m.user_id=(select auth.uid()) and m.role='Supa Admin' and m.is_active=true) into v_supa;
  return query select c.id,
    case when v_supa then coalesce(public.crystal_actor_name(c.sender_id),c.sender_email)
      else case when coalesce(c.sender_email,'')='' then 'Administrator' else left(split_part(c.sender_email,'@',1),1)||repeat('*',greatest(length(split_part(c.sender_email,'@',1))-2,1))||right(split_part(c.sender_email,'@',1),1)||'@'||split_part(c.sender_email,'@',2) end end,
    c.message,c.created_at
  from public.crystal_admin_conversations c where c.archived_at is null order by c.created_at asc limit 300;
end $$;
revoke all on function public.admin_list_conversation_history() from public,anon;
grant execute on function public.admin_list_conversation_history() to authenticated;

-- Keep the opportunity set fixed at the eight website divisions; status changes use the audited RPC only.
drop policy if exists "Admins manage opportunities" on public.investment_opportunities;
drop policy if exists "Admins read opportunities" on public.investment_opportunities;
create policy "Admins read opportunities" on public.investment_opportunities
  for select to authenticated using(public.crystal_admin_has_permission('opportunities'));
revoke insert,update,delete on public.investment_opportunities from authenticated;
grant select on public.investment_opportunities to authenticated;

revoke select on public.crystal_site_configuration from authenticated;
create or replace function public.admin_get_site_configuration(p_key text)
returns jsonb language plpgsql security definer set search_path=''
as $$ declare v_supa boolean; v_value jsonb;
begin
  if p_key not in ('platform_settings','website_content') then raise exception 'Invalid configuration key'; end if;
  if not public.crystal_admin_has_permission(case when p_key='website_content' then 'website_content' else 'platform_settings' end) then raise exception 'Configuration access permission required'; end if;
  select exists(select 1 from public.crystal_admin_memberships m where m.user_id=(select auth.uid()) and m.role='Supa Admin' and m.is_active=true) into v_supa;
  select c.config_value into v_value from public.crystal_site_configuration c where c.config_key=p_key;
  if p_key='platform_settings' and not v_supa then v_value:=coalesce(v_value,'{}'::jsonb)-'financial_operations_enabled'; end if;
  return coalesce(v_value,'{}'::jsonb);
end $$;
revoke all on function public.admin_get_site_configuration(text) from public,anon;
grant execute on function public.admin_get_site_configuration(text) to authenticated;

create or replace function public.admin_set_financial_operations_enabled(p_enabled boolean)
returns void language plpgsql security definer set search_path=''
as $$
begin
  if not exists(select 1 from public.crystal_admin_memberships m where m.user_id=(select auth.uid()) and m.role='Supa Admin' and m.is_active=true) then raise exception 'Supa Admin permission required'; end if;
  perform public.crystal_require_admin_mfa();
  insert into public.crystal_site_configuration(config_key,config_value,updated_by)
  values('platform_settings',jsonb_build_object('financial_operations_enabled',p_enabled),(select auth.uid()))
  on conflict(config_key) do update set config_value=crystal_site_configuration.config_value||excluded.config_value,updated_by=excluded.updated_by,updated_at=now();
  insert into public.crystal_admin_audit_log(actor_id,action,target_type,details)
  values((select auth.uid()),'financial_operations_toggled','platform_settings',jsonb_build_object('enabled',p_enabled));
end $$;
revoke all on function public.admin_set_financial_operations_enabled(boolean) from public,anon;
grant execute on function public.admin_set_financial_operations_enabled(boolean) to authenticated;

-- Explicit client grants: RLS policies alone do not remove existing table privileges.
revoke all on public.crystal_admin_audit_log,public.crystal_admin_conversations,public.crystal_site_configuration,public.crystal_admin_memberships from anon,authenticated;
revoke all on public.crystal_support_messages,public.crystal_fx_rates,public.market_conditions,public.investment_opportunities,
  public.investment_allocations,public.investment_distributions,public.investor_documents,
  public.deposit_requests,public.withdrawal_requests,public.investor_ledger_entries from anon,authenticated;
grant select on public.crystal_support_messages,public.crystal_fx_rates,public.market_conditions,public.investment_opportunities,
  public.investment_allocations,public.investment_distributions,public.investor_documents,
  public.deposit_requests,public.withdrawal_requests,public.investor_ledger_entries to authenticated;
grant insert on public.investor_documents to authenticated;

create index if not exists investment_allocations_investor_currency_status_idx on public.investment_allocations(investor_id,currency,status);
create index if not exists investment_daily_accruals_investor_currency_date_idx on public.investment_daily_accruals(investor_id,currency,accrual_date);
create index if not exists withdrawal_requests_investor_currency_status_idx on public.withdrawal_requests(investor_id,currency,status);
create index if not exists deposit_requests_status_created_idx on public.deposit_requests(status,created_at desc);
create index if not exists crystal_admin_audit_log_active_created_idx on public.crystal_admin_audit_log(archived_at,created_at desc);
create index if not exists crystal_admin_conversations_active_created_idx on public.crystal_admin_conversations(archived_at,created_at);
create index if not exists crystal_support_messages_active_created_idx on public.crystal_support_messages(archived_at,created_at desc);
create index if not exists investment_opportunities_division_status_idx on public.investment_opportunities(division,status);
create index if not exists crystal_branches_status_name_idx on public.crystal_branches(status,name);
