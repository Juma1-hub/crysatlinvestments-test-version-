-- Persist administrator-published market observations in Supabase.
-- Forward-only, non-financial migration. Does not alter existing financial records.
create table if not exists public.market_condition_updates (
  id uuid primary key default gen_random_uuid(),
  market text not null check (length(trim(market)) between 1 and 160),
  sentiment text not null check (sentiment in ('Bullish','Bearish','Neutral')),
  source text not null check (length(trim(source)) between 1 and 240),
  note text not null default '',
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists market_condition_updates_updated_idx on public.market_condition_updates(updated_at desc);
alter table public.market_condition_updates enable row level security;
revoke all on public.market_condition_updates from anon, authenticated;
grant select on public.market_condition_updates to authenticated;
drop policy if exists "Authenticated users read market updates" on public.market_condition_updates;
create policy "Authenticated users read market updates" on public.market_condition_updates for select to authenticated using (true);

create or replace function public.admin_list_market_condition_updates()
returns table(id uuid, market text, sentiment text, source text, note text, updated_at timestamptz)
language plpgsql stable security definer set search_path=''
as $$
begin
 if not public.crystal_admin_has_permission('market_conditions') then raise exception 'Market conditions permission required'; end if;
 return query select m.id,m.market,m.sentiment,m.source,m.note,m.updated_at from public.market_condition_updates m order by m.updated_at desc;
end; $$;
revoke all on function public.admin_list_market_condition_updates() from public,anon;
grant execute on function public.admin_list_market_condition_updates() to authenticated;

create or replace function public.admin_create_market_condition_update(p_market text,p_sentiment text,p_source text,p_note text default '')
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid;
begin
 if not public.crystal_admin_has_permission('market_conditions') then raise exception 'Market conditions permission required'; end if;
 if length(trim(coalesce(p_market,''))) not between 1 and 160 or length(trim(coalesce(p_source,''))) not between 1 and 240 or p_sentiment not in ('Bullish','Bearish','Neutral') then raise exception 'Invalid market update'; end if;
 insert into public.market_condition_updates(market,sentiment,source,note,created_by) values(trim(p_market),p_sentiment,trim(p_source),left(coalesce(p_note,''),2000),(select auth.uid())) returning id into v_id;
 insert into public.crystal_admin_audit_log(actor_id,action,target_type,target_id,details) values((select auth.uid()),'market_condition_created','market_condition',v_id::text,jsonb_build_object('market',trim(p_market),'sentiment',p_sentiment));
 return v_id;
end; $$;
revoke all on function public.admin_create_market_condition_update(text,text,text,text) from public,anon;
grant execute on function public.admin_create_market_condition_update(text,text,text,text) to authenticated;

create or replace function public.admin_delete_market_condition_update(p_id uuid)
returns void language plpgsql security definer set search_path=''
as $$
begin
 if not public.crystal_admin_has_permission('market_conditions') then raise exception 'Market conditions permission required'; end if;
 delete from public.market_condition_updates where id=p_id;
 if not found then raise exception 'Market update not found'; end if;
 insert into public.crystal_admin_audit_log(actor_id,action,target_type,target_id) values((select auth.uid()),'market_condition_deleted','market_condition',p_id::text);
end; $$;
revoke all on function public.admin_delete_market_condition_update(uuid) from public,anon;
grant execute on function public.admin_delete_market_condition_update(uuid) to authenticated;
