-- CRYSTAL INVESTMENTS: public contact intake, private admin conversations and privilege hardening.
-- Run after migrations 001-004.

create table if not exists public.crystal_contact_throttle(
 email text primary key,
 last_submitted_at timestamptz not null default now()
);
alter table public.crystal_contact_throttle enable row level security;
revoke all on public.crystal_contact_throttle from anon,authenticated;

create or replace function public.public_submit_contact_enquiry(
 p_name text,p_email text,p_category text,p_subject text,p_message text,p_website text default ''
) returns uuid
language plpgsql security definer set search_path=''
as $$
declare v_id uuid; v_email text:=lower(trim(coalesce(p_email,''))); v_name text:=trim(coalesce(p_name,'')); v_message text:=trim(coalesce(p_message,''));
begin
 if length(trim(coalesce(p_website,'')))>0 then raise exception 'Invalid submission'; end if;
 if length(v_name)<2 or length(v_name)>160 or v_email !~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+[.][A-Z]{2,}$' or length(v_email)>254 or length(v_message)<5 or length(v_message)>10000 then
  raise exception 'Invalid enquiry details';
 end if;
 insert into public.crystal_contact_throttle(email,last_submitted_at) values(v_email,now())
 on conflict(email) do update set last_submitted_at=now()
 where public.crystal_contact_throttle.last_submitted_at < now()-interval '60 seconds';
 if not found then raise exception 'Please wait before sending another enquiry'; end if;
 insert into public.crystal_support_messages(investor_id,sender_name,sender_email,category,subject,message)
 values(null,left(v_name,160),v_email,left(coalesce(p_category,'General enquiry'),80),left(coalesce(p_subject,'Website enquiry'),180),v_message)
 returning id into v_id;
 return v_id;
end $$;
revoke all on function public.public_submit_contact_enquiry(text,text,text,text,text,text) from public,authenticated;
grant execute on function public.public_submit_contact_enquiry(text,text,text,text,text,text) to anon;

create table if not exists public.crystal_admin_conversations(
 id uuid primary key default gen_random_uuid(),
 sender_id uuid not null references auth.users(id) on delete restrict,
 sender_email text not null,
 message text not null check(length(message) between 1 and 5000),
 created_at timestamptz not null default now()
);
alter table public.crystal_admin_conversations enable row level security;
revoke all on public.crystal_admin_conversations from anon,authenticated;
grant select on public.crystal_admin_conversations to authenticated;
drop policy if exists "Only admins read admin conversations" on public.crystal_admin_conversations;
create policy "Only admins read admin conversations" on public.crystal_admin_conversations
 for select to authenticated using(public.is_crystal_admin());

create or replace function public.admin_send_conversation_message(p_message text)
returns uuid language plpgsql security definer set search_path=''
as $$ declare v_id uuid; v_email text; begin
 if not public.is_crystal_admin() then raise exception 'Administrator access required'; end if;
 if length(trim(coalesce(p_message,'')))<1 or length(p_message)>5000 then raise exception 'Message must be 1 to 5000 characters'; end if;
 select email into v_email from auth.users where id=(select auth.uid());
 insert into public.crystal_admin_conversations(sender_id,sender_email,message)
 values((select auth.uid()),coalesce(v_email,''),trim(p_message)) returning id into v_id;
 insert into public.crystal_admin_audit_log(actor_id,action,target_type,target_id)
 values((select auth.uid()),'admin_conversation_message_sent','admin_conversation',v_id::text);
 return v_id;
end $$;
revoke all on function public.admin_send_conversation_message(text) from public,anon;
grant execute on function public.admin_send_conversation_message(text) to authenticated;

-- Only a Supa Admin may set the global annual rate, regardless of junior module permissions.
create or replace function public.admin_set_global_interest_rate(p_annual_rate numeric,p_day_count_basis integer,p_effective_at timestamptz default now())
returns uuid language plpgsql security definer set search_path=''
as $$ declare v_id uuid; begin
 if not exists(select 1 from public.crystal_admin_memberships m where m.user_id=(select auth.uid()) and m.role='Supa Admin' and m.is_active=true) then raise exception 'Supa Admin permission required'; end if;
 if coalesce((select auth.jwt()->>'aal'),'aal1') <> 'aal2' then raise exception 'Multi-factor authentication is required for this action'; end if;
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
drop policy if exists "Supa Admins read interest rate history" on public.crystal_interest_rate_history;
create policy "Supa Admins read interest rate history" on public.crystal_interest_rate_history
 for select to authenticated using(exists(select 1 from public.crystal_admin_memberships m where m.user_id=(select auth.uid()) and m.role='Supa Admin' and m.is_active=true));

-- Guard promotion/demotion and preserve at least one active Supa Admin.
create or replace function public.admin_set_membership(p_email text,p_role text,p_permissions jsonb default '{}'::jsonb)
returns uuid language plpgsql security definer set search_path=''
as $$ declare v_uid uuid; v_id uuid; v_old_role text; v_count integer; begin
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
 values(v_uid,p_role,coalesce(p_permissions,'{}'::jsonb),true)
 on conflict(user_id) do update set role=excluded.role,permissions=excluded.permissions,is_active=true,updated_at=now()
 returning user_id into v_id;
 insert into public.crystal_admin_audit_log(actor_id,action,target_type,target_id,details)
 values((select auth.uid()),'administrator_membership_set','admin',v_id::text,jsonb_build_object('email',lower(trim(p_email)),'role',p_role,'previous_role',v_old_role,'permissions',p_permissions));
 return v_id;
end $$;
revoke all on function public.admin_set_membership(text,text,jsonb) from public,anon;
grant execute on function public.admin_set_membership(text,text,jsonb) to authenticated;

create or replace function public.admin_remove_membership(p_user_id uuid)
returns void language plpgsql security definer set search_path=''
as $$ declare v_role text; v_count integer; begin
 if not exists(select 1 from public.crystal_admin_memberships where user_id=(select auth.uid()) and role='Supa Admin' and is_active=true) then raise exception 'Supa Admin permission required'; end if;
 if coalesce((select auth.jwt()->>'aal'),'aal1') <> 'aal2' then raise exception 'Multi-factor authentication is required for administrator role changes'; end if;
 select role into v_role from public.crystal_admin_memberships where user_id=p_user_id and is_active=true;
 if v_role='Supa Admin' then
  perform pg_advisory_xact_lock(hashtext('crystal_supa_admin_role_lock'));
  select count(*) into v_count from public.crystal_admin_memberships where role='Supa Admin' and is_active=true;
  if v_count<=1 then raise exception 'The last Supa Admin cannot be removed'; end if;
 end if;
 update public.crystal_admin_memberships set is_active=false,updated_at=now() where user_id=p_user_id;
 insert into public.crystal_admin_audit_log(actor_id,action,target_type,target_id) values((select auth.uid()),'administrator_membership_removed','admin',p_user_id::text);
end $$;
revoke all on function public.admin_remove_membership(uuid) from public,anon;
grant execute on function public.admin_remove_membership(uuid) to authenticated;

create or replace function public.crystal_admin_access()
returns jsonb language sql stable security definer set search_path=''
as $$
 select coalesce((select jsonb_build_object('role',m.role,'permissions',m.permissions)
 from public.crystal_admin_memberships m where m.user_id=(select auth.uid()) and m.is_active=true),'{}'::jsonb);
$$;
revoke all on function public.crystal_admin_access() from public,anon;
grant execute on function public.crystal_admin_access() to authenticated;
