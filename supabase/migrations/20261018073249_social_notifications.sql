-- Service-only notification transport; CloudKit remains the social source of truth.
-- No CloudKit credentials or photos are stored. Payloads expire after one day.
create table public.social_config (
  key text primary key, value text not null
);
create table public.social_installations (
  id uuid primary key,
  user_id uuid not null references public.directory_users(id) on delete cascade,
  cloud_id text not null, environment text not null check (environment in ('development','production')),
  apns_token text not null check (apns_token ~ '^[a-fA-F0-9]{64}$'),
  preferences jsonb not null, registered_at timestamptz not null default now(),
  updated_at timestamptz not null default now(), revoked_at timestamptz,
  unique(environment,apns_token)
);
create index social_installations_recipient on public.social_installations(environment,cloud_id) where revoked_at is null;
create index social_installations_user on public.social_installations(user_id);
create table public.social_events (
  id text primary key, room text not null, actor text not null,
  environment text not null check(environment in ('development','production')),
  payload jsonb not null, created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '1 day', cancelled boolean not null default false
);
create index social_events_expiry on public.social_events(expires_at);
create table public.social_deliveries (
  id uuid primary key default gen_random_uuid(),
  event_id text not null references public.social_events(id) on delete cascade,
  installation_id uuid not null references public.social_installations(id) on delete cascade,
  notice jsonb not null, state text not null default 'pending'
    check(state in ('pending','sending','accepted','suppressed','failed')),
  attempts integer not null default 0, next_attempt_at timestamptz not null default now(),
  lease uuid, lease_until timestamptz, apns_id text, reason text,
  created_at timestamptz not null default now(), finished_at timestamptz,
  unique(event_id,installation_id)
);
create index social_deliveries_pending on public.social_deliveries(next_attempt_at) where state in ('pending','sending');
create index social_deliveries_installation on public.social_deliveries(installation_id);
create table public.social_routes (
  installation_id uuid not null references public.social_installations(id) on delete cascade,
  notice_key text not null, channel text not null check(channel in ('server','local')),
  created_at timestamptz not null default now(), primary key(installation_id,notice_key)
);
alter table public.social_routes enable row level security;
revoke all on public.social_routes from public,anon,authenticated;
grant all on public.social_routes to service_role;

create table public.social_rate_limits (user_id uuid primary key references public.directory_users(id) on delete cascade, bucket timestamptz not null, count integer not null);

alter table public.social_config enable row level security;
alter table public.social_installations enable row level security;
alter table public.social_events enable row level security;
alter table public.social_deliveries enable row level security;
alter table public.social_rate_limits enable row level security;
revoke all on public.social_config, public.social_installations, public.social_events, public.social_deliveries, public.social_rate_limits from public, anon, authenticated;
grant all on public.social_config, public.social_installations, public.social_events, public.social_deliveries, public.social_rate_limits to service_role;

create function public.social_allow_request(p_user uuid) returns boolean language plpgsql set search_path = '' as $$
declare n integer;
begin
  insert into public.social_rate_limits(user_id,bucket,count) values(p_user,date_trunc('minute',now()),1)
  on conflict(user_id) do update set bucket=excluded.bucket,
    count=case when social_rate_limits.bucket=excluded.bucket then social_rate_limits.count+1 else 1 end returning count into n;
  return n <= 90;
end $$;

create function public.social_register(p_id uuid,p_user uuid,p_cloud text,p_environment text,p_token text,p_preferences jsonb)
returns void language plpgsql set search_path = '' as $$
begin
  if exists(select 1 from public.social_installations where id=p_id and user_id<>p_user) then
    raise exception 'installation belongs to another session';
  end if;
  -- One APNs token can never remain attached to the previous signed-in account.
  delete from public.social_installations where environment=p_environment and apns_token=p_token and id<>p_id;
  -- On account/token change, discard the previous person's queued deliveries.
  delete from public.social_deliveries where installation_id=p_id and exists(
    select 1 from public.social_installations i where i.id=p_id and (i.user_id<>p_user or i.cloud_id<>p_cloud or i.environment<>p_environment or i.apns_token<>p_token));
  insert into public.social_installations(id,user_id,cloud_id,environment,apns_token,preferences)
    values(p_id,p_user,p_cloud,p_environment,p_token,p_preferences)
  on conflict(id) do update set user_id=p_user,cloud_id=p_cloud,environment=p_environment,apns_token=p_token,preferences=p_preferences,
    registered_at=case when social_installations.apns_token<>p_token or social_installations.user_id<>p_user or social_installations.cloud_id<>p_cloud then now() else social_installations.registered_at end,
    updated_at=now(),revoked_at=null;

end $$;

create function public.social_enqueue(p_id text,p_environment text,p_event jsonb)
returns void language plpgsql set search_path = '' as $$
begin
  insert into public.social_events(id,room,actor,environment,payload,cancelled,expires_at)
  values(p_id,p_event->>'room',p_event->>'actor',p_environment,p_event,coalesce((p_event->>'cancelled')::boolean,false),
    least(now()+interval '1 day',to_timestamp((p_event->>'occurredAt')::double precision/1000)+interval '1 day'))
  on conflict(id) do update set cancelled=social_events.cancelled or excluded.cancelled;
  -- A removed member cannot receive previously queued room alerts after a fresh proof.
  update public.social_deliveries d set state='suppressed',finished_at=now(),reason='membership_changed'
  from public.social_events e,public.social_installations i
  where d.event_id=e.id and d.installation_id=i.id and e.room=p_event->>'room'
    and d.state in ('pending','sending') and not (p_event->'members' ? i.cloud_id);
  update public.social_deliveries set state='suppressed',finished_at=now(),reason='cancelled'
  where event_id=p_id and state in ('pending','sending') and exists(select 1 from public.social_events where id=p_id and cancelled);
  insert into public.social_routes(installation_id,notice_key,channel)
  select i.id,n->>'key','server' from public.social_events e cross join lateral jsonb_array_elements(e.payload->'notices') n
  join public.social_installations i on i.cloud_id=n->>'recipient' and i.environment=p_environment and i.revoked_at is null
  where e.id=p_id and not e.cancelled and e.expires_at>now() and i.cloud_id<>e.actor
  on conflict(installation_id,notice_key) do nothing;
  insert into public.social_deliveries(event_id,installation_id,notice)
  select p_id,i.id,n from public.social_events e cross join lateral jsonb_array_elements(e.payload->'notices') n
  join public.social_installations i on i.cloud_id=n->>'recipient' and i.environment=p_environment and i.revoked_at is null
  where e.id=p_id and not e.cancelled and e.expires_at>now() and i.cloud_id<>e.actor
    and exists(select 1 from public.social_routes r where r.installation_id=i.id and r.notice_key=n->>'key' and r.channel='server')
  on conflict(event_id,installation_id) do nothing;
end $$;

create function public.social_claim(p_limit integer default 20)
returns table(delivery_id uuid,lease_id uuid,event_id text,installation_id uuid,payload jsonb,notice jsonb,preferences jsonb,
  apns_token text,environment text,registered_at timestamptz,attempts integer)
language plpgsql set search_path = '' as $$
begin
  update public.social_deliveries d set state='suppressed',finished_at=now(),reason='expired_or_revoked'
  from public.social_events e,public.social_installations i where d.event_id=e.id and d.installation_id=i.id
    and d.state in ('pending','sending') and (e.expires_at<=now() or e.cancelled or i.revoked_at is not null or d.attempts>=12);
  return query with ready as (
    select d.id from public.social_deliveries d
    where (d.state='pending' and d.next_attempt_at<=now()) or (d.state='sending' and d.lease_until<now())
    order by d.next_attempt_at for update skip locked limit greatest(1,least(p_limit,50))
  ), claimed as (
    update public.social_deliveries d set state='sending',lease=gen_random_uuid(),lease_until=now()+interval '90 seconds',attempts=d.attempts+1
    from ready where d.id=ready.id returning d.*
  ) select d.id,d.lease,d.event_id,d.installation_id,e.payload,d.notice,i.preferences,i.apns_token,i.environment,i.registered_at,d.attempts
  from claimed d join public.social_events e on e.id=d.event_id join public.social_installations i on i.id=d.installation_id;
end $$;

create function public.social_finish(p_id uuid,p_lease uuid,p_state text,p_reason text,p_apns_id text,p_delay integer,p_invalid boolean,p_token text,p_registered timestamptz)
returns void language plpgsql set search_path = '' as $$
declare installation uuid;
begin
  update public.social_deliveries set state=p_state,reason=left(p_reason,100),apns_id=p_apns_id,
    next_attempt_at=now()+make_interval(secs=>greatest(1,least(p_delay,1800))),
    finished_at=case when p_state='pending' then null else now() end,lease=null,lease_until=null
  where id=p_id and lease=p_lease and state='sending' returning installation_id into installation;
  if p_invalid and installation is not null then
    update public.social_installations set revoked_at=now() where id=installation and apns_token=p_token and registered_at=p_registered;
  end if;
end $$;

revoke all on function public.social_allow_request(uuid),public.social_register(uuid,uuid,text,text,text,jsonb),
 public.social_enqueue(text,text,jsonb),public.social_claim(integer),public.social_finish(uuid,uuid,text,text,text,integer,boolean,text,timestamptz) from public,anon,authenticated;
grant execute on function public.social_allow_request(uuid),public.social_register(uuid,uuid,text,text,text,jsonb),
 public.social_enqueue(text,text,jsonb),public.social_claim(integer),public.social_finish(uuid,uuid,text,text,text,integer,boolean,text,timestamptz) to service_role;

-- One atomic choice of local fallback versus APNs per installation/event.
-- This keeps older senders working and prevents a silent CloudKit wake from
-- showing a second alert while the same event is already in the APNs queue.
create function public.social_local_claim(p_user uuid,p_installation uuid,p_keys text[])
returns text[] language plpgsql set search_path = '' as $$
declare allowed text[];
begin
  if not exists(select 1 from public.social_installations where id=p_installation and user_id=p_user and revoked_at is null) then
    return p_keys;
  end if;
  insert into public.social_routes(installation_id,notice_key,channel)
  select p_installation,k,'local' from unnest(p_keys) k on conflict(installation_id,notice_key) do nothing;
  select array_agg(notice_key) into allowed from public.social_routes
  where installation_id=p_installation and notice_key=any(p_keys) and channel='local';
  return coalesce(allowed,array[]::text[]);
end $$;
revoke all on function public.social_local_claim(uuid,uuid,text[]) from public,anon,authenticated;
grant execute on function public.social_local_claim(uuid,uuid,text[]) to service_role;

create function public.social_reconcile_room(p_room text,p_members text[])
returns void language plpgsql set search_path = '' as $$
begin
  update public.social_deliveries d set state='suppressed',finished_at=now(),reason='membership_changed'
  from public.social_events e,public.social_installations i
  where d.event_id=e.id and d.installation_id=i.id and e.room=p_room and d.state in ('pending','sending')
    and (not (i.cloud_id=any(p_members)) or not (e.actor=any(p_members)));
end $$;
revoke all on function public.social_reconcile_room(text,text[]) from public,anon,authenticated;
grant execute on function public.social_reconcile_room(text,text[]) to service_role;
