-- CRYSTAL INVESTMENTS: remove the unintended one-year daily-interest accrual cap.
-- Fresh-install forward migration. This does not create or credit past earnings by itself;
-- the existing idempotent accrual RPC still records one row per allocation/date.
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
    current_date,interval '1 day'
  ) g(day_value)
  cross join lateral (
    select h.annual_rate,h.day_count_basis
    from public.crystal_interest_rate_history h
    where h.effective_at::date<=g.day_value::date
    order by h.effective_at desc limit 1
  ) rate
  where a.investor_id=p_investor_id and a.status='active' and a.activated_at is not null
    and exists(select 1 from public.crystal_interest_rate_history)
  on conflict(allocation_id,accrual_date) do nothing;
end $$;
revoke all on function public.crystal_accrue_investor_daily_earnings(uuid) from public,anon,authenticated;
