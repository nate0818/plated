-- Provider state stays server-only; the founder BFF is the only review surface.
create table public.testflight_requests (
  request_id uuid primary key references public.waitlist(id) on delete cascade,
  status text not null default 'new' check (status in ('new','archived','sending','invited','accepted','installed','failed','uncertain','revoked')),
  apple_tester_id text,
  apple_state text,
  group_id text,
  invited_at timestamptz,
  checked_at timestamptz,
  updated_at timestamptz not null default now(),
  last_error_code text check (length(last_error_code) <= 100),
  lease_id uuid,
  lease_expires_at timestamptz
);
alter table public.testflight_requests enable row level security;
revoke all on public.testflight_requests from public, anon, authenticated;
grant select, insert, update, delete on public.testflight_requests to service_role;

create function public.admin_assert_testflight_founder(p_actor uuid) returns void
language plpgsql security invoker set search_path = '' as $$
begin
  if not exists(select 1 from public.admin_principals where user_id=p_actor and active and role='founder' and ('admin.read'=any(permissions) or '*'=any(permissions))) then
    raise exception 'Founder access required' using errcode='42501';
  end if;
end $$;

create function public.admin_list_testflight_requests(p_actor uuid, p_filter text default 'active', p_offset int default 0, p_limit int default 50) returns jsonb
language plpgsql security invoker set search_path = '' as $$
declare v_result jsonb;
begin
  perform public.admin_assert_testflight_founder(p_actor);
  if p_filter not in ('active','all','invited','archived') or p_offset < 0 or p_offset > 10000000 or p_limit < 1 or p_limit > 50 then raise exception 'Invalid page'; end if;
  with requests as (
    select w.id, w.email, w.created_at, coalesce(t.status,'new') as status, t.apple_state, t.invited_at, t.checked_at, t.last_error_code
    from public.waitlist w left join public.testflight_requests t on t.request_id=w.id where w.source='plated.food/early-access'
  ), filtered as (
    select * from requests where p_filter='all' or (p_filter='active' and status in ('new','failed','uncertain','sending')) or (p_filter='invited' and status in ('invited','accepted','installed','revoked')) or (p_filter='archived' and status='archived')
  ), page as (select * from filtered order by created_at, id offset p_offset limit p_limit)
  select jsonb_build_object(
    'rows',coalesce((select jsonb_agg(jsonb_build_object('id',id,'email',email,'requestedAt',created_at,'status',status,'appleState',apple_state,'invitedAt',invited_at,'checkedAt',checked_at,'errorCode',last_error_code) order by created_at,id) from page),'[]'::jsonb),
    'totalCount',(select count(*) from filtered),
    'counts',jsonb_build_object('pending',(select count(*) from requests where status in ('new','failed','uncertain','sending')),'invited',(select count(*) from requests where status in ('invited','accepted','installed','revoked')),'archived',(select count(*) from requests where status='archived'))
  ) into v_result;
  return v_result;
end $$;

-- A persisted lease serializes clicks across tabs and protects ambiguous sends.
create function public.admin_claim_testflight_request(p_actor uuid, p_id uuid, p_action text) returns jsonb
language plpgsql security invoker set search_path = '' as $$
declare v_row public.testflight_requests; v_email text; v_lease uuid; v_previous text;
begin
  perform public.admin_assert_testflight_founder(p_actor);
  if p_action not in ('invite','sync','archive','restore') then raise exception 'Invalid action'; end if;
  select email into v_email from public.waitlist where id=p_id and source='plated.food/early-access' for update;
  if not found then raise exception 'Access request not found' using errcode='P0002'; end if;
  insert into public.testflight_requests(request_id) values(p_id) on conflict do nothing;
  select * into v_row from public.testflight_requests where request_id=p_id for update;
  if v_row.lease_expires_at > now() then return jsonb_build_object('busy',true); end if;
  v_previous := case when v_row.status='sending' then 'uncertain' else v_row.status end;
  if p_action in ('archive','restore') then
    if (p_action='archive' and v_previous not in ('new','failed')) or (p_action='restore' and v_previous<>'archived') then raise exception 'This request cannot be changed in its current state'; end if;
    update public.testflight_requests set status=case when p_action='archive' then 'archived' else 'new' end, updated_at=now(), last_error_code=null where request_id=p_id;
    return jsonb_build_object('done',true);
  end if;
  if v_previous='archived' then raise exception 'Restore the request before checking or inviting'; end if;
  v_lease := gen_random_uuid();
  update public.testflight_requests set status='sending',lease_id=v_lease,lease_expires_at=now()+interval '2 minutes',updated_at=now() where request_id=p_id;
  return jsonb_build_object('leaseId',v_lease,'email',v_email,'previousStatus',v_previous,'maySend',p_action='invite' and v_previous in ('new','failed'),'testerId',v_row.apple_tester_id);
end $$;

create function public.admin_finish_testflight_request(p_actor uuid,p_id uuid,p_lease uuid,p_status text,p_tester text,p_state text,p_group text,p_error text) returns boolean
language plpgsql security invoker set search_path = '' as $$
begin
  perform public.admin_assert_testflight_founder(p_actor);
  if p_status not in ('new','invited','accepted','installed','failed','uncertain','revoked') or length(p_tester)>100 or length(p_state)>100 or length(p_group)>100 or length(p_error)>100 then raise exception 'Invalid result'; end if;
  update public.testflight_requests set status=p_status,apple_tester_id=coalesce(p_tester,apple_tester_id),apple_state=p_state,group_id=coalesce(p_group,group_id),
    invited_at=case when p_status in ('invited','accepted','installed') then coalesce(invited_at,now()) else invited_at end,
    checked_at=now(),updated_at=now(),last_error_code=p_error,lease_id=null,lease_expires_at=null
    where request_id=p_id and lease_id=p_lease;
  return found;
end $$;

revoke all on function public.admin_assert_testflight_founder(uuid) from public,anon,authenticated;
revoke all on function public.admin_list_testflight_requests(uuid,text,int,int) from public,anon,authenticated;
revoke all on function public.admin_claim_testflight_request(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.admin_finish_testflight_request(uuid,uuid,uuid,text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.admin_assert_testflight_founder(uuid) to service_role;
grant execute on function public.admin_list_testflight_requests(uuid,text,int,int) to service_role;
grant execute on function public.admin_claim_testflight_request(uuid,uuid,text) to service_role;
grant execute on function public.admin_finish_testflight_request(uuid,uuid,uuid,text,text,text,text,text) to service_role;
