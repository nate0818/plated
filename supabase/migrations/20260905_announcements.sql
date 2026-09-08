-- Founder operations and durable announcements.
--
-- This migration is deliberately safe to run more than once. Browser clients
-- never receive grants on these tables or RPCs. Edge Functions authenticate a
-- Supabase user at AAL2, check the active principal, and then use service_role
-- to call the narrow functions below.

create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_cron with schema pg_catalog;

-- The directory cutover is gated, because this migration has to be safe to
-- run while the shipped app still speaks the api_token protocol. Everything
-- the founder console reads is created either way. The statements that make
-- the old protocol impossible (dropping api_token, requiring a session on
-- every device row) run only once this flag says a build carrying the new
-- protocol is out. Set it and rerun this file to complete the cutover:
--   insert into public.server_config (key, value) values ('directory_cutover', 'on')
--     on conflict (key) do update set value = 'on';
create or replace function public.directory_cutover_enabled()
returns boolean language sql stable
set search_path = pg_catalog, public as $$
  select coalesce(
    (select value = 'on' from public.server_config where key = 'directory_cutover'), false
  );
$$;

-- A device has a stable database id and a stable app-installation id. The APNs
-- token is globally unique: when iOS hands the same token to a newly signed-in
-- account, registration moves that device instead of leaving a private invite
-- route attached to the previous account.
alter table public.device_tokens
  add column if not exists id uuid default gen_random_uuid(),
  add column if not exists installation_id uuid default gen_random_uuid(),
  add column if not exists app_build integer,
  add column if not exists app_version text,
  add column if not exists apns_environment text,
  add column if not exists release_channel text not null default 'unknown',
  add column if not exists notification_authorization text not null default 'unknown',
  add column if not exists created_at timestamptz not null default now();

-- OS permission was originally requested for interpersonal Table/cook alerts.
-- It is not consent to founder announcements. If a prototype `news` column
-- still has its unsafe TRUE default, reset those rows once before changing the
-- default; rerunning this migration sees FALSE and preserves explicit choices.
do $$
declare v_default text;
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'device_tokens' and column_name = 'news'
  ) then
    alter table public.device_tokens add column news boolean not null default false;
  else
    select pg_get_expr(ad.adbin, ad.adrelid) into v_default
    from pg_attribute a
    join pg_attrdef ad on ad.adrelid = a.attrelid and ad.adnum = a.attnum
    where a.attrelid = 'public.device_tokens'::regclass and a.attname = 'news';
    if lower(coalesce(v_default, '')) like '%true%' then
      update public.device_tokens set news = false;
    end if;
    alter table public.device_tokens alter column news set default false;
  end if;
end
$$;

update public.device_tokens set news = false where news is null;
alter table public.device_tokens alter column news set not null;

update public.device_tokens set id = gen_random_uuid() where id is null;
update public.device_tokens set installation_id = id where installation_id is null;
update public.device_tokens
set apns_environment = case when sandbox then 'sandbox' else 'production' end
where apns_environment is null;

alter table public.device_tokens
  alter column id set default gen_random_uuid(),
  alter column id set not null,
  alter column installation_id set default gen_random_uuid(),
  alter column installation_id set not null,
  alter column apns_environment set default 'production',
  alter column apns_environment set not null;

-- Keep the most recently registered owner before enforcing global identity.
do $$
begin
  if public.directory_cutover_enabled() then
    delete from public.device_tokens older
    using public.device_tokens newer
    where older.apns_token = newer.apns_token
      and (
        older.updated_at < newer.updated_at
        or (older.updated_at = newer.updated_at and older.id < newer.id)
      );
    create unique index if not exists device_tokens_apns_token_uidx
      on public.device_tokens (apns_token);
  end if;
end
$$;

create unique index if not exists device_tokens_id_uidx on public.device_tokens (id);
create unique index if not exists device_tokens_installation_uidx on public.device_tokens (installation_id);
create index if not exists device_tokens_admin_eligibility_idx
  on public.device_tokens
  (news, notification_authorization, release_channel, app_build, updated_at desc);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'device_tokens_app_build_check'
    and conrelid = 'public.device_tokens'::regclass) then
    alter table public.device_tokens add constraint device_tokens_app_build_check
      check (app_build is null or app_build between 0 and 1000000);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'device_tokens_apns_token_check'
    and conrelid = 'public.device_tokens'::regclass) then
    alter table public.device_tokens add constraint device_tokens_apns_token_check
      check (apns_token ~ '^[0-9a-f]{64}$');
  end if;
  if not exists (select 1 from pg_constraint where conname = 'device_tokens_app_version_check'
    and conrelid = 'public.device_tokens'::regclass) then
    alter table public.device_tokens add constraint device_tokens_app_version_check
      check (app_version is null or char_length(app_version) between 1 and 40);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'device_tokens_apns_environment_check'
    and conrelid = 'public.device_tokens'::regclass) then
    alter table public.device_tokens add constraint device_tokens_apns_environment_check
      check (apns_environment in ('sandbox', 'production'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'device_tokens_release_channel_check'
    and conrelid = 'public.device_tokens'::regclass) then
    alter table public.device_tokens add constraint device_tokens_release_channel_check
      check (release_channel in ('development', 'ad_hoc', 'testflight', 'app_store', 'unknown'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'device_tokens_notification_authorization_check'
    and conrelid = 'public.device_tokens'::regclass) then
    alter table public.device_tokens add constraint device_tokens_notification_authorization_check
      check (notification_authorization in
        ('not_determined', 'denied', 'authorized', 'provisional', 'ephemeral', 'unknown'));
  end if;
end
$$;

-- Directory credentials are per installation, revocable, and expire after an
-- absolute 30 days. Only the SHA-256 digest is stored. The opaque session id
-- is also the registration generation, which makes a delayed unregister from
-- an older sign-in incapable of deleting a newer binding on the same phone.
create table if not exists public.directory_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.directory_users(id) on delete cascade,
  installation_id uuid not null,
  token_hash text not null,
  created_at timestamptz not null default now(),
  last_used_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '30 days'),
  revoked_at timestamptz,
  check (token_hash ~ '^[0-9a-f]{64}$'),
  check (expires_at > created_at)
);
create unique index if not exists directory_sessions_token_hash_uidx
  on public.directory_sessions (token_hash);
create unique index if not exists directory_sessions_active_installation_uidx
  on public.directory_sessions (installation_id) where revoked_at is null;
create index if not exists directory_sessions_user_active_idx
  on public.directory_sessions (user_id, expires_at desc) where revoked_at is null;
create index if not exists directory_sessions_retention_idx
  on public.directory_sessions (coalesce(revoked_at, expires_at));

-- This is an intentional fail-closed cutover. Prototype directory bearer
-- tokens never expired and were shared by all of a person's installations.
-- Existing device bindings cannot be proven to belong to a new session, so
-- they are removed and reattached by the app after /register rotates a
-- per-install credential.
alter table public.device_tokens add column if not exists directory_session_id uuid;
do $$
begin
  if public.directory_cutover_enabled() then
    delete from public.device_tokens where directory_session_id is null;
  end if;
end
$$;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'device_tokens_directory_session_id_fkey'
      and conrelid = 'public.device_tokens'::regclass
  ) then
    alter table public.device_tokens add constraint device_tokens_directory_session_id_fkey
      foreign key (directory_session_id) references public.directory_sessions(id) on delete restrict;
  end if;
end
$$;
do $$
begin
  if public.directory_cutover_enabled()
    and exists (select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'device_tokens'
        and column_name = 'directory_session_id' and is_nullable = 'YES')
  then
    alter table public.device_tokens alter column directory_session_id set not null;
  end if;
end
$$;
alter table public.device_tokens add column if not exists token_registered_at timestamptz not null default now();
create index if not exists device_tokens_directory_session_idx
  on public.device_tokens (directory_session_id);

-- Remove the indefinite account bearer after the replacement relation exists.
-- Until then it is what the deployed register, device and invite functions
-- authenticate every phone with, so dropping it early takes the service down.
do $$
begin
  if public.directory_cutover_enabled() then
    drop index if exists public.directory_users_api_token_uidx;
    alter table public.directory_users drop column if exists api_token;
  end if;
end
$$;

-- Invitation records exist for abuse limits and operator diagnosis only. The
-- bearer share URL is never retained, and the remaining metadata has a strict
-- 30-day window. /invite also performs this purge on every request.
alter table public.invites
  add column if not exists expires_at timestamptz not null default (now() + interval '30 days');
do $$
begin
  if public.directory_cutover_enabled() then
    alter table public.invites drop column if exists share_url;
  end if;
end
$$;
update public.invites
set expires_at = least(expires_at, created_at + interval '30 days');
delete from public.invites where expires_at <= now();
create index if not exists invites_expiry_idx on public.invites (expires_at);

create table if not exists public.admin_principals (
  user_id uuid primary key references auth.users(id) on delete cascade,
  directory_user_id uuid unique references public.directory_users(id) on delete set null,
  role text not null default 'founder',
  permissions text[] not null default array['admin.read']::text[],
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (role in ('founder', 'operator', 'read_only')),
  check (cardinality(permissions) <= 32)
);
alter table public.admin_principals
  alter column permissions set default array['admin.read']::text[];
update public.admin_principals
set permissions = array(
  select distinct permission
  from unnest(permissions) permission
  where permission = any(case role
    when 'read_only' then array['admin.read']::text[]
    when 'operator' then array['admin.read', 'announcements.send', 'announcements.retract']::text[]
    else array['admin.read', 'announcements.send', 'announcements.retract',
      'announcements.override_caps', '*']::text[]
  end)
);
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'admin_principals_read_only_permissions_check'
      and conrelid = 'public.admin_principals'::regclass
  ) then
    alter table public.admin_principals
      add constraint admin_principals_read_only_permissions_check
      check (role <> 'read_only' or permissions <@ array['admin.read']::text[]);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'admin_principals_role_permissions_check'
      and conrelid = 'public.admin_principals'::regclass
  ) then
    alter table public.admin_principals
      add constraint admin_principals_role_permissions_check check (
        (role = 'read_only' and permissions <@ array['admin.read']::text[])
        or (role = 'operator' and permissions <@ array[
          'admin.read', 'announcements.send', 'announcements.retract'
        ]::text[])
        or (role = 'founder' and permissions <@ array[
          'admin.read', 'announcements.send', 'announcements.retract',
          'announcements.override_caps', '*'
        ]::text[])
      );
  end if;
end
$$;

create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  created_by uuid references auth.users(id) on delete set null,
  title text not null,
  body text not null,
  link text not null default 'plated://home',
  audience text not null,
  below_build integer,
  replaces uuid references public.announcements(id) on delete restrict,
  override_cap boolean not null default false,
  payload_hash text,
  status text not null default 'previewed',
  targeted_count integer not null default 0,
  accepted_count integer not null default 0,
  retryable_count integer not null default 0,
  permanent_failure_count integer not null default 0,
  pending_count integer not null default 0,
  created_at timestamptz not null default now(),
  queued_at timestamptz,
  started_at timestamptz,
  finished_at timestamptz,
  retracted_at timestamptz
);

-- Widen an earlier development prototype without requiring a destructive reset.
alter table public.announcements
  add column if not exists created_by uuid references auth.users(id) on delete set null,
  add column if not exists override_cap boolean not null default false,
  add column if not exists payload_hash text,
  add column if not exists targeted_count integer not null default 0,
  add column if not exists accepted_count integer not null default 0,
  add column if not exists retryable_count integer not null default 0,
  add column if not exists permanent_failure_count integer not null default 0,
  add column if not exists pending_count integer not null default 0,
  add column if not exists queued_at timestamptz,
  add column if not exists started_at timestamptz;
alter table public.announcements alter column id set default gen_random_uuid();
alter table public.announcements alter column status set default 'previewed';
alter table public.announcements drop constraint if exists announcements_audience_check;
alter table public.announcements drop constraint if exists announcements_status_check;
drop index if exists public.announcements_fleet_hour_idx;
drop index if exists public.announcements_one_per_build_idx;
update public.announcements set audience = 'development' where audience = 'sandbox';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'announcements_audience_check'
    and conrelid = 'public.announcements'::regclass) then
    alter table public.announcements add constraint announcements_audience_check
      check (audience in ('me', 'development', 'testflight', 'app_store', 'all'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'announcements_status_check'
    and conrelid = 'public.announcements'::regclass) then
    alter table public.announcements add constraint announcements_status_check
      check (status in ('previewed', 'queued', 'sending', 'sent', 'partial', 'failed', 'retracted'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'announcements_below_build_check'
    and conrelid = 'public.announcements'::regclass) then
    alter table public.announcements add constraint announcements_below_build_check
      check (below_build is null or below_build between 1 and 1000000);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'announcements_copy_check'
    and conrelid = 'public.announcements'::regclass) then
    alter table public.announcements add constraint announcements_copy_check
      check (char_length(title) between 1 and 32 and char_length(body) between 1 and 140);
  end if;
end
$$;

create index if not exists announcements_created_idx on public.announcements (created_at desc, id desc);
create index if not exists announcements_status_idx on public.announcements (status, created_at desc);
-- Unlike date_trunc(timestamptz), this predicate and key are immutable on PG17.
drop index if exists public.announcements_one_original_per_build_idx;
create unique index if not exists announcements_one_original_per_build_idx
  on public.announcements (below_build)
  where below_build is not null
    and replaces is null
    and audience in ('testflight', 'app_store', 'all')
    and status in ('queued', 'sending', 'sent', 'partial', 'retracted');
drop index if exists public.announcements_one_correction_per_original_idx;
create unique index if not exists announcements_one_correction_per_original_idx
  on public.announcements (replaces)
  where replaces is not null
    and status in ('queued', 'sending', 'sent', 'partial', 'retracted');

create table if not exists public.admin_action_intents (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  kind text not null,
  announcement_id uuid not null references public.announcements(id) on delete cascade,
  payload jsonb not null,
  payload_hash text not null,
  recipient_count integer not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  consumed_by_request uuid,
  check (kind = 'announcement.send'),
  check (char_length(payload_hash) = 64),
  check (recipient_count >= 0),
  check (expires_at > created_at)
);
create index if not exists admin_action_intents_actor_created_idx
  on public.admin_action_intents (actor_user_id, created_at desc);
create index if not exists admin_action_intents_expiry_idx
  on public.admin_action_intents (expires_at) where consumed_at is null;

create table if not exists public.announcement_deliveries (
  id bigint generated by default as identity primary key,
  announcement_id uuid not null references public.announcements(id) on delete cascade,
  device_token_id uuid references public.device_tokens(id) on delete set null,
  user_id_snapshot uuid not null,
  installation_id_snapshot uuid not null,
  directory_session_id_snapshot uuid not null,
  token_registered_at_snapshot timestamptz not null,
  token_snapshot text,
  token_hash text not null,
  apns_environment text not null,
  release_channel text not null,
  app_build integer,
  status text not null default 'pending',
  attempts integer not null default 0,
  next_attempt_at timestamptz not null default now(),
  claimed_at timestamptz,
  claim_token uuid,
  response_status integer,
  response_reason text,
  apns_id text,
  accepted_at timestamptz,
  payload_expires_at timestamptz not null default (now() + interval '72 hours'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (announcement_id, token_hash),
  check (char_length(token_hash) = 64),
  check (apns_environment in ('sandbox', 'production')),
  check (release_channel in ('development', 'ad_hoc', 'testflight', 'app_store', 'unknown')),
  check (status in ('pending', 'claimed', 'accepted', 'retryable', 'permanent_failure')),
  check (attempts between 0 and 100)
);
alter table public.announcement_deliveries
  add column if not exists payload_expires_at timestamptz not null default (now() + interval '72 hours'),
  add column if not exists user_id_snapshot uuid,
  add column if not exists installation_id_snapshot uuid,
  add column if not exists directory_session_id_snapshot uuid,
  add column if not exists token_registered_at_snapshot timestamptz;
alter table public.announcement_deliveries alter column token_snapshot drop not null;
update public.announcement_deliveries delivery set
  user_id_snapshot = device.user_id,
  installation_id_snapshot = device.installation_id,
  directory_session_id_snapshot = device.directory_session_id,
  token_registered_at_snapshot = device.token_registered_at
from public.device_tokens device
where delivery.device_token_id = device.id
  and (delivery.user_id_snapshot is null or delivery.installation_id_snapshot is null
    or delivery.directory_session_id_snapshot is null
    or delivery.token_registered_at_snapshot is null);
-- A pre-cutover delivery cannot be revalidated against a revocable session.
-- Preserve its aggregate evidence while making the raw address unusable.
update public.announcement_deliveries set
  status = 'permanent_failure', response_reason = 'DirectorySessionCutover',
  claimed_at = null, claim_token = null, token_snapshot = null, updated_at = now()
where directory_session_id_snapshot is null or token_registered_at_snapshot is null;
delete from public.announcement_deliveries
where user_id_snapshot is null or installation_id_snapshot is null;
alter table public.announcement_deliveries
  alter column user_id_snapshot set not null,
  alter column installation_id_snapshot set not null;
create index if not exists announcement_deliveries_claim_idx
  on public.announcement_deliveries (announcement_id, status, next_attempt_at, id);
create index if not exists announcement_deliveries_device_idx
  on public.announcement_deliveries (device_token_id);

create table if not exists public.admin_audit_events (
  id bigint generated by default as identity primary key,
  -- Deliberately no FK: audit evidence remains byte-for-byte immutable even
  -- when an Auth user is deleted. `on delete set null` would be an UPDATE and
  -- would be rejected by the append-only trigger below.
  actor_user_id uuid,
  action text not null,
  outcome text not null,
  target_type text,
  target_id text,
  request_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (char_length(action) between 1 and 100),
  check (outcome in ('allowed', 'denied', 'failed')),
  check (jsonb_typeof(metadata) = 'object')
);
alter table public.admin_audit_events
  drop constraint if exists admin_audit_events_actor_user_id_fkey;
create index if not exists admin_audit_events_created_idx
  on public.admin_audit_events (created_at desc, id desc);
create index if not exists admin_audit_events_actor_idx
  on public.admin_audit_events (actor_user_id, created_at desc);

create or replace function public.prevent_admin_audit_mutation()
returns trigger language plpgsql set search_path = pg_catalog as $$
begin
  raise exception 'admin_audit_events is append-only' using errcode = '55000';
end
$$;
drop trigger if exists admin_audit_events_append_only on public.admin_audit_events;
create trigger admin_audit_events_append_only
before update or delete on public.admin_audit_events
for each row execute function public.prevent_admin_audit_mutation();

create or replace function public.admin_permission_allowed(p_actor_user_id uuid, p_permission text)
returns boolean language sql stable security definer
set search_path = pg_catalog, public, auth as $$
  select exists (
    select 1 from public.admin_principals p
    where p.user_id = p_actor_user_id and p.active
      and (p_permission = any(p.permissions) or '*' = any(p.permissions))
  )
$$;

create or replace function public.admin_record_audit_event(
  p_actor_user_id uuid, p_action text, p_outcome text,
  p_target_type text default null, p_target_id text default null,
  p_request_id uuid default null, p_metadata jsonb default '{}'::jsonb
)
returns bigint language plpgsql security definer
set search_path = pg_catalog, public, auth as $$
declare v_id bigint;
begin
  if not exists (
    select 1 from public.admin_principals p
    where p.user_id = p_actor_user_id and p.active
  ) then
    raise exception 'admin permission denied' using errcode = '42501';
  end if;
  if p_outcome not in ('allowed', 'denied', 'failed') then
    raise exception 'invalid audit outcome' using errcode = '22023';
  end if;
  insert into public.admin_audit_events
    (actor_user_id, action, outcome, target_type, target_id, request_id, metadata)
  values (
    p_actor_user_id, left(p_action, 100), p_outcome,
    nullif(left(coalesce(p_target_type, ''), 80), ''),
    nullif(left(coalesce(p_target_id, ''), 160), ''), p_request_id,
    case when jsonb_typeof(coalesce(p_metadata, '{}'::jsonb)) = 'object'
      then coalesce(p_metadata, '{}'::jsonb) else '{}'::jsonb end
  ) returning id into v_id;
  return v_id;
end
$$;

-- Apple identity verification happens in /register. This RPC performs the
-- mutation atomically, rotates the installation generation, and returns only
-- the new session id and absolute expiry. `p_token_hash` is a digest of 32
-- random bytes; raw bearer material never enters Postgres.
create or replace function public.register_directory_session(
  p_apple_user_id text,
  p_display_name text,
  p_phone_hash text,
  p_installation_id uuid,
  p_token_hash text
)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public as $$
declare
  v_user_id uuid;
  v_session_id uuid := gen_random_uuid();
  v_expires_at timestamptz := now() + interval '30 days';
begin
  p_apple_user_id := btrim(coalesce(p_apple_user_id, ''));
  p_display_name := btrim(coalesce(p_display_name, ''));
  if char_length(p_apple_user_id) not between 1 and 255
    or char_length(p_display_name) > 80
    or p_installation_id is null
    or p_token_hash !~ '^[0-9a-f]{64}$'
    or (p_phone_hash is not null and p_phone_hash !~ '^[0-9a-f]{64}$')
  then raise exception 'invalid directory registration' using errcode = '22023'; end if;

  -- Registration is rare. A single short lock gives a total order to Apple
  -- account changes, session rotation, device transfer, and stale cleanup.
  perform pg_advisory_xact_lock(hashtextextended('plated:directory-registration', 0));
  insert into public.directory_users (apple_user_id, display_name, phone_hash, created_at, updated_at)
  values (p_apple_user_id, p_display_name, p_phone_hash, now(), now())
  on conflict (apple_user_id) do update set
    display_name = case when excluded.display_name <> ''
      then excluded.display_name else directory_users.display_name end,
    phone_hash = coalesce(excluded.phone_hash, directory_users.phone_hash),
    updated_at = now()
  returning id into v_user_id;

  update public.announcement_deliveries delivery set
    status = 'permanent_failure', response_reason = 'DirectorySessionRotated',
    claimed_at = null, claim_token = null, token_snapshot = null, updated_at = now()
  where delivery.status in ('pending', 'claimed', 'retryable')
    and exists (
      select 1 from public.device_tokens device
      where device.id = delivery.device_token_id
        and device.installation_id = p_installation_id
        and device.directory_session_id = delivery.directory_session_id_snapshot
    );
  delete from public.device_tokens device
  where device.installation_id = p_installation_id;
  update public.directory_sessions session set revoked_at = coalesce(session.revoked_at, now())
  where session.installation_id = p_installation_id and session.revoked_at is null;

  insert into public.directory_sessions (
    id, user_id, installation_id, token_hash, created_at, last_used_at, expires_at
  ) values (
    v_session_id, v_user_id, p_installation_id, p_token_hash, now(), now(), v_expires_at
  );
  return jsonb_build_object(
    'userId', v_user_id, 'sessionId', v_session_id, 'expiresAt', v_expires_at
  );
end
$$;

create or replace function public.resolve_directory_session(
  p_session_id uuid,
  p_token_hash text,
  p_installation_id uuid
)
returns table (user_id uuid, display_name text, expires_at timestamptz)
language plpgsql security definer
set search_path = pg_catalog, public as $$
begin
  if p_session_id is null or p_installation_id is null
    or p_token_hash !~ '^[0-9a-f]{64}$'
  then raise exception 'invalid directory session' using errcode = '22023'; end if;
  return query
  update public.directory_sessions session set last_used_at = now()
  from public.directory_users person
  where session.id = p_session_id
    and session.token_hash = p_token_hash
    and session.installation_id = p_installation_id
    and session.revoked_at is null
    and session.expires_at > now()
    and person.id = session.user_id
  returning session.user_id, person.display_name, session.expires_at;
end
$$;

drop function if exists public.upsert_device_token(uuid, uuid, text, text, text, integer, text, text, boolean);
create or replace function public.upsert_device_token(
  p_session_id uuid, p_token_hash text, p_installation_id uuid, p_apns_token text,
  p_apns_environment text, p_release_channel text, p_app_build integer,
  p_app_version text, p_notification_authorization text, p_news boolean
)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public as $$
declare
  v_id uuid;
  v_user_id uuid;
  v_stale record;
begin
  if p_session_id is null or p_installation_id is null
    or p_token_hash !~ '^[0-9a-f]{64}$' or p_apns_token !~ '^[0-9a-f]{64}$'
    or p_news is null
    or p_apns_environment not in ('sandbox', 'production')
    or p_release_channel not in ('development', 'ad_hoc', 'testflight', 'app_store', 'unknown')
    or p_notification_authorization not in
      ('not_determined', 'denied', 'authorized', 'provisional', 'ephemeral', 'unknown')
    or (p_app_build is not null and p_app_build not between 0 and 1000000)
    or (p_app_version is not null and char_length(p_app_version) not between 1 and 40)
  then raise exception 'invalid device registration' using errcode = '22023'; end if;

  perform pg_advisory_xact_lock(hashtextextended('plated:directory-registration', 0));
  select session.user_id into v_user_id
  from public.directory_sessions session
  where session.id = p_session_id and session.token_hash = p_token_hash
    and session.installation_id = p_installation_id
    and session.revoked_at is null and session.expires_at > now()
  for update;
  if not found then
    raise exception 'directory session is unavailable' using errcode = '28000';
  end if;

  select device.id into v_id from public.device_tokens device
  where device.installation_id = p_installation_id
    and device.directory_session_id = p_session_id
  for update;

  -- An APNs token has one owner. Terminalize any work snapshotted for the
  -- former owner before moving the token to this session generation.
  update public.announcement_deliveries delivery set
    status = 'permanent_failure', response_reason = 'DeviceBindingMoved',
    claimed_at = null, claim_token = null, token_snapshot = null, updated_at = now()
  where delivery.status in ('pending', 'claimed', 'retryable')
    and exists (
      select 1 from public.device_tokens device
      where device.id = delivery.device_token_id
        and (device.apns_token = p_apns_token
          or (device.installation_id = p_installation_id
            and device.directory_session_id <> p_session_id))
        and device.directory_session_id = delivery.directory_session_id_snapshot
    );
  delete from public.device_tokens device
  where device.id is distinct from v_id
    and (device.apns_token = p_apns_token or device.installation_id = p_installation_id);

  if v_id is null then
    v_id := gen_random_uuid();
    insert into public.device_tokens (
      id, installation_id, directory_session_id, user_id, apns_token,
      sandbox, apns_environment, release_channel, app_build, app_version,
      notification_authorization, news, token_registered_at, created_at, updated_at
    ) values (
      v_id, p_installation_id, p_session_id, v_user_id, p_apns_token,
      p_apns_environment = 'sandbox', p_apns_environment, p_release_channel,
      p_app_build, p_app_version, p_notification_authorization, p_news,
      now(), now(), now()
    );
  else
    update public.device_tokens device set
      user_id = v_user_id, apns_token = p_apns_token,
      sandbox = p_apns_environment = 'sandbox', apns_environment = p_apns_environment,
      release_channel = p_release_channel, app_build = p_app_build,
      app_version = p_app_version, notification_authorization = p_notification_authorization,
      news = p_news, token_registered_at = now(), updated_at = now()
    where device.id = v_id and device.directory_session_id = p_session_id;
  end if;

  -- Bound account fan-out without leaving resumable snapshots for evicted
  -- installations. One account may keep its eight most recent devices.
  for v_stale in
    select ranked.id, ranked.installation_id, ranked.directory_session_id
    from (
      select device.id, device.installation_id, device.directory_session_id,
        row_number() over (order by device.updated_at desc, device.id desc) as position
      from public.device_tokens device where device.user_id = v_user_id
    ) ranked where ranked.position > 8
  loop
    update public.announcement_deliveries delivery set
      status = 'permanent_failure', response_reason = 'DeviceLimitEviction',
      claimed_at = null, claim_token = null, token_snapshot = null, updated_at = now()
    where delivery.device_token_id = v_stale.id
      and delivery.installation_id_snapshot = v_stale.installation_id
      and delivery.directory_session_id_snapshot = v_stale.directory_session_id
      and delivery.status in ('pending', 'claimed', 'retryable');
    delete from public.device_tokens where id = v_stale.id;
  end loop;
  update public.directory_sessions set last_used_at = now() where id = p_session_id;
  return v_id;
end
$$;

drop function if exists public.unregister_device_token(uuid, uuid, text);
create or replace function public.unregister_directory_session(
  p_session_id uuid,
  p_token_hash text,
  p_installation_id uuid,
  p_apns_token text default null
)
returns boolean language plpgsql security definer
set search_path = pg_catalog, public as $$
declare v_device_id uuid; v_session_user_id uuid;
begin
  if p_session_id is null or p_installation_id is null
    or p_token_hash !~ '^[0-9a-f]{64}$'
    or (p_apns_token is not null and p_apns_token !~ '^[0-9a-f]{64}$')
  then raise exception 'invalid device unregister' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('plated:directory-registration', 0));
  select session.user_id into v_session_user_id
  from public.directory_sessions session
  where session.id = p_session_id and session.token_hash = p_token_hash
    and session.installation_id = p_installation_id
  for update;
  if not found then return false; end if;

  select device.id into v_device_id from public.device_tokens device
  where device.directory_session_id = p_session_id
    and device.user_id = v_session_user_id
    and device.installation_id = p_installation_id
    and (p_apns_token is null or device.apns_token = p_apns_token)
  for update;
  if found then
    update public.announcement_deliveries delivery set
      status = 'permanent_failure', response_reason = 'DeviceUnregistered',
      claimed_at = null, claim_token = null, token_snapshot = null, updated_at = now()
    where delivery.device_token_id = v_device_id
      and delivery.user_id_snapshot = v_session_user_id
      and delivery.installation_id_snapshot = p_installation_id
      and delivery.directory_session_id_snapshot = p_session_id
      and delivery.status in ('pending', 'claimed', 'retryable');
    delete from public.device_tokens device
    where device.id = v_device_id and device.directory_session_id = p_session_id
      and device.user_id = v_session_user_id and device.installation_id = p_installation_id
      and (p_apns_token is null or device.apns_token = p_apns_token);
  end if;
  update public.directory_sessions session set revoked_at = coalesce(session.revoked_at, now())
  where session.id = p_session_id and session.token_hash = p_token_hash
    and session.installation_id = p_installation_id;
  return v_device_id is not null;
end
$$;

create or replace function public.record_invite_attempt(
  p_inviter_id uuid,
  p_invitee_phone_hash text,
  p_host_name text,
  p_known_recipient boolean
)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public as $$
declare
  v_host_count integer;
  v_pair_count integer;
begin
  if p_inviter_id is null
    or p_invitee_phone_hash !~ '^[0-9a-f]{64}$'
    or p_known_recipient is null
    or char_length(btrim(coalesce(p_host_name, ''))) > 80
  then
    raise exception 'invalid invite attempt' using errcode = '22023';
  end if;

  -- One inviter-scoped lock covers both limits. Concurrent requests cannot
  -- all observe the same pre-insert count and exceed either allowance.
  perform pg_advisory_xact_lock(hashtextextended(
    'plated:invite-rate:' || p_inviter_id::text, 0
  ));
  delete from public.invites invite where invite.expires_at <= now();

  select count(*)::integer into v_host_count
  from public.invites invite
  where invite.inviter_id = p_inviter_id
    and invite.created_at >= now() - interval '24 hours';
  if v_host_count >= 20 then
    return jsonb_build_object('recorded', false, 'notify', false, 'limit', 'host');
  end if;

  select count(*)::integer into v_pair_count
  from public.invites invite
  where invite.inviter_id = p_inviter_id
    and invite.invitee_phone_hash = p_invitee_phone_hash
    and invite.created_at >= now() - interval '24 hours';

  insert into public.invites (
    inviter_id, invitee_phone_hash, host_name, status, expires_at
  ) values (
    p_inviter_id, p_invitee_phone_hash,
    btrim(coalesce(p_host_name, '')),
    case when p_known_recipient then 'matched' else 'sent' end,
    now() + interval '30 days'
  );
  return jsonb_build_object(
    'recorded', true,
    'notify', p_known_recipient and v_pair_count < 2,
    'limit', case when v_pair_count >= 2 then 'pair' else null end
  );
end
$$;

create or replace function public.admin_preview_announcement(
  p_actor_user_id uuid, p_title text, p_body text, p_link text, p_audience text,
  p_below_build integer default null, p_replaces uuid default null,
  p_override_cap boolean default false, p_ttl_seconds integer default 600
)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, auth, extensions as $$
declare
  v_actor_directory uuid;
  v_announcement_id uuid := gen_random_uuid();
  v_intent_id uuid := gen_random_uuid();
  v_expires_at timestamptz;
  v_payload jsonb;
  v_hash text;
  v_count integer := 0;
  v_skipped_unknown integer := 0;
  v_by_channel jsonb := '{}'::jsonb;
  v_by_gateway jsonb := '{}'::jsonb;
  v_by_build jsonb := '{}'::jsonb;
  v_cap_warning text;
  v_original public.announcements%rowtype;
begin
  if not public.admin_permission_allowed(p_actor_user_id, 'announcements.send') then
    raise exception 'announcement permission denied' using errcode = '42501';
  end if;
  if p_override_cap and not public.admin_permission_allowed(p_actor_user_id, 'announcements.override_caps') then
    raise exception 'cap override permission denied' using errcode = '42501';
  end if;

  p_title := btrim(coalesce(p_title, ''));
  p_body := btrim(coalesce(p_body, ''));
  p_link := btrim(coalesce(p_link, ''));
  if char_length(p_title) not between 1 and 32
    or p_title ~ '[–—]' or p_title ~* '^plated\y'
    or char_length(p_body) not between 1 and 140
    or p_body ~ '[–—]' or p_body !~ '[.!?]$'
    or p_link !~ '^plated://(home|table|plan|cookbook|grocery|activity|update)([/?#].*)?$'
    or (p_below_build is null and p_link ~ '^plated://update([/?#]|$)')
    or p_audience not in ('me', 'development', 'testflight', 'app_store', 'all')
    or (p_below_build is not null and p_below_build not between 1 and 1000000)
  then
    raise exception 'announcement does not meet the copy or audience contract' using errcode = '22023';
  end if;

  select p.directory_user_id into v_actor_directory
  from public.admin_principals p where p.user_id = p_actor_user_id and p.active;
  if p_audience = 'me' and v_actor_directory is null then
    raise exception 'admin principal has no directory user for a me preview' using errcode = '55000';
  end if;

  if p_replaces is not null then
    select * into v_original from public.announcements a where a.id = p_replaces;
    if not found or v_original.retracted_at is null then
      raise exception 'a correction must replace a retracted announcement' using errcode = '22023';
    end if;
    if v_original.audience <> p_audience
      or v_original.below_build is distinct from p_below_build
    then
      raise exception 'a correction must keep the original audience and build boundary' using errcode = '22023';
    end if;
  end if;

  v_payload := jsonb_build_object(
    'title', p_title, 'body', p_body, 'link', p_link, 'audience', p_audience,
    'belowBuild', p_below_build, 'replaces', p_replaces, 'overrideCap', p_override_cap
  );
  v_hash := encode(digest(convert_to(v_payload::text, 'UTF8'), 'sha256'), 'hex');
  v_expires_at := now() + make_interval(secs => greatest(60, least(coalesce(p_ttl_seconds, 600), 900)));

  insert into public.announcements (
    id, created_by, title, body, link, audience, below_build, replaces,
    override_cap, payload_hash, status
  ) values (
    v_announcement_id, p_actor_user_id, p_title, p_body, p_link, p_audience,
    p_below_build, p_replaces, p_override_cap, v_hash, 'previewed'
  );

  insert into public.announcement_deliveries (
    announcement_id, device_token_id, user_id_snapshot, installation_id_snapshot,
    directory_session_id_snapshot, token_registered_at_snapshot,
    token_snapshot, token_hash,
    apns_environment, release_channel, app_build
  )
  select
    v_announcement_id, d.id, d.user_id, d.installation_id,
    d.directory_session_id, d.token_registered_at, d.apns_token,
    encode(digest(convert_to(d.apns_token, 'UTF8'), 'sha256'), 'hex'),
    d.apns_environment, d.release_channel, d.app_build
  from public.device_tokens d
  join public.directory_sessions session
    on session.id = d.directory_session_id
    and session.user_id = d.user_id
    and session.installation_id = d.installation_id
    and session.revoked_at is null and session.expires_at > now()
  where d.news
    and d.notification_authorization in ('authorized', 'provisional', 'ephemeral')
    and (
      p_audience = 'all'
      or (p_audience = 'me' and d.user_id = v_actor_directory)
      or d.release_channel = p_audience
    )
    and (p_below_build is null or (d.app_build is not null and d.app_build < p_below_build));
  get diagnostics v_count = row_count;

  if p_below_build is not null then
    select count(*)::integer into v_skipped_unknown
    from public.device_tokens d
    join public.directory_sessions session
      on session.id = d.directory_session_id
      and session.user_id = d.user_id
      and session.installation_id = d.installation_id
      and session.revoked_at is null and session.expires_at > now()
    where d.news
      and d.notification_authorization in ('authorized', 'provisional', 'ephemeral')
      and d.app_build is null
      and (
        p_audience = 'all'
        or (p_audience = 'me' and d.user_id = v_actor_directory)
        or d.release_channel = p_audience
      );
  end if;

  select coalesce(jsonb_object_agg(x.release_channel, x.n), '{}'::jsonb) into v_by_channel
  from (select d.release_channel, count(*)::integer n
        from public.announcement_deliveries d where d.announcement_id = v_announcement_id
        group by d.release_channel) x;
  select coalesce(jsonb_object_agg(x.apns_environment, x.n), '{}'::jsonb) into v_by_gateway
  from (select d.apns_environment, count(*)::integer n
        from public.announcement_deliveries d where d.announcement_id = v_announcement_id
        group by d.apns_environment) x;
  select coalesce(jsonb_object_agg(x.build, x.n), '{}'::jsonb) into v_by_build
  from (select coalesce(d.app_build::text, 'unknown') build, count(*)::integer n
        from public.announcement_deliveries d where d.announcement_id = v_announcement_id
        group by coalesce(d.app_build::text, 'unknown')) x;

  if p_replaces is not null and exists (
    select 1 from public.announcements a
    where a.id <> v_announcement_id and a.replaces = p_replaces
      and a.status in ('queued', 'sending', 'sent', 'partial', 'retracted')
  ) then
    v_cap_warning := 'This announcement already has a correction.';
  elsif p_replaces is null and p_audience in ('testflight', 'app_store', 'all') then
    if p_below_build is not null and exists (
      select 1 from public.announcements a
      where a.id <> v_announcement_id and a.replaces is null
        and a.below_build = p_below_build
        and a.audience in ('testflight', 'app_store', 'all')
        and a.status in ('queued', 'sending', 'sent', 'partial', 'retracted')
    ) then
      v_cap_warning := format('Build %s already has a fleet announcement.', p_below_build);
    elsif exists (
      select 1 from public.announcements a
      where a.audience in ('testflight', 'app_store', 'all')
        and a.status in ('queued', 'sending', 'sent', 'partial', 'retracted')
        and coalesce(a.queued_at, a.created_at) > now() - interval '24 hours'
    ) then
      v_cap_warning := 'A fleet announcement was queued in the last 24 hours.';
    end if;
  elsif p_audience in ('me', 'development') and (
    select count(*) from public.announcements a
    where a.created_by = p_actor_user_id and a.audience = p_audience
      and a.status in ('queued', 'sending', 'sent', 'partial', 'retracted')
      and coalesce(a.queued_at, a.created_at) > now() - interval '24 hours'
  ) >= 20 then
    v_cap_warning := 'Twenty test announcements were queued in the last 24 hours.';
  end if;

  insert into public.admin_action_intents (
    id, actor_user_id, kind, announcement_id, payload, payload_hash, recipient_count, expires_at
  ) values (
    v_intent_id, p_actor_user_id, 'announcement.send', v_announcement_id,
    v_payload, v_hash, v_count, v_expires_at
  );
  update public.announcements set targeted_count = v_count, pending_count = v_count
  where id = v_announcement_id;
  insert into public.admin_audit_events
    (actor_user_id, action, outcome, target_type, target_id, metadata)
  values (
    p_actor_user_id, 'announcement.preview', 'allowed', 'announcement', v_announcement_id::text,
    jsonb_build_object('audience', p_audience, 'recipientCount', v_count,
      'belowBuild', p_below_build, 'replaces', p_replaces, 'overrideCap', p_override_cap)
  );

  return jsonb_build_object(
    'announcementId', v_announcement_id, 'intentId', v_intent_id,
    'expiresAt', v_expires_at, 'payloadHash', v_hash, 'recipientCount', v_count,
    'skippedUnknownBuild', v_skipped_unknown, 'byReleaseChannel', v_by_channel,
    'byGateway', v_by_gateway, 'byBuild', v_by_build,
    'capWarning', v_cap_warning, 'overrideCap', p_override_cap
  );
end
$$;

create or replace function public.admin_consume_announcement_intent(
  p_actor_user_id uuid, p_intent_id uuid, p_typed_title text, p_request_id uuid
)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, auth, extensions as $$
declare
  v_intent public.admin_action_intents%rowtype;
  v_announcement public.announcements%rowtype;
  v_payload jsonb; v_hash text;
begin
  if not public.admin_permission_allowed(p_actor_user_id, 'announcements.send') then
    raise exception 'announcement permission denied' using errcode = '42501';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('plated:intent:' || p_intent_id::text, 0));
  select * into v_intent from public.admin_action_intents i where i.id = p_intent_id for update;
  if not found or v_intent.actor_user_id <> p_actor_user_id or v_intent.kind <> 'announcement.send' then
    raise exception 'action intent not found' using errcode = '22023';
  end if;
  select * into v_announcement from public.announcements a
  where a.id = v_intent.announcement_id for update;
  if not found or v_announcement.title <> p_typed_title then
    raise exception 'typed title does not match the preview' using errcode = '22023';
  end if;
  if v_announcement.override_cap
    and not public.admin_permission_allowed(p_actor_user_id, 'announcements.override_caps')
  then
    raise exception 'cap override permission denied' using errcode = '42501';
  end if;
  v_payload := jsonb_build_object(
    'title', v_announcement.title, 'body', v_announcement.body,
    'link', v_announcement.link, 'audience', v_announcement.audience,
    'belowBuild', v_announcement.below_build, 'replaces', v_announcement.replaces,
    'overrideCap', v_announcement.override_cap
  );
  v_hash := encode(digest(convert_to(v_payload::text, 'UTF8'), 'sha256'), 'hex');
  if v_hash <> v_intent.payload_hash or v_hash <> v_announcement.payload_hash then
    raise exception 'preview payload changed' using errcode = '55000';
  end if;
  if v_intent.consumed_at is not null then
    return jsonb_build_object('announcementId', v_announcement.id, 'alreadyConsumed', true,
      'status', v_announcement.status, 'recipientCount', v_announcement.targeted_count);
  end if;
  if v_intent.expires_at <= now() then
    raise exception 'action intent expired; preview again' using errcode = '22023';
  end if;
  if v_intent.recipient_count < 1 then
    raise exception 'the preview contains no eligible devices' using errcode = '22023';
  end if;

  if v_announcement.replaces is not null then
    perform pg_advisory_xact_lock(hashtextextended(
      'plated:announcement:correction:' || v_announcement.replaces::text, 0
    ));
    if exists (
      select 1 from public.announcements a
      where a.id <> v_announcement.id and a.replaces = v_announcement.replaces
        and a.status in ('queued', 'sending', 'sent', 'partial', 'retracted')
    ) then
      raise exception 'this announcement already has a correction' using errcode = '23505';
    end if;
  end if;

  -- Corrections consume the same audience volume allowance as originals.
  -- The separate correction lock above also limits each retracted link in the
  -- chain to one successor.
  if v_announcement.audience in ('testflight', 'app_store', 'all') then
    perform pg_advisory_xact_lock(hashtextextended('plated:announcement:fleet-cap', 0));
    -- override_cap is a deliberate escape hatch for the time-based volume
    -- cap. It never allows two original announcements for the same build.
    if v_announcement.replaces is null and v_announcement.below_build is not null and exists (
      select 1 from public.announcements a where a.id <> v_announcement.id
        and a.replaces is null and a.below_build = v_announcement.below_build
        and a.audience in ('testflight', 'app_store', 'all')
        and a.status in ('queued', 'sending', 'sent', 'partial', 'retracted')
    ) then raise exception 'this build already has a fleet announcement' using errcode = '23505'; end if;
    if not v_announcement.override_cap then
      if exists (
        select 1 from public.announcements a where a.id <> v_announcement.id
          and a.audience in ('testflight', 'app_store', 'all')
          and a.status in ('queued', 'sending', 'sent', 'partial', 'retracted')
          and coalesce(a.queued_at, a.created_at) > now() - interval '24 hours'
      ) then raise exception 'a fleet announcement was queued in the last 24 hours' using errcode = 'P0001'; end if;
    end if;
  elsif v_announcement.audience in ('me', 'development') then
    perform pg_advisory_xact_lock(hashtextextended(
      'plated:announcement:test-cap:' || p_actor_user_id::text || ':' || v_announcement.audience, 0));
    if not v_announcement.override_cap and (
      select count(*) from public.announcements a where a.id <> v_announcement.id
        and a.created_by = p_actor_user_id and a.audience = v_announcement.audience
        and a.status in ('queued', 'sending', 'sent', 'partial', 'retracted')
        and coalesce(a.queued_at, a.created_at) > now() - interval '24 hours'
    ) >= 20 then
      raise exception 'twenty test announcements were queued in the last 24 hours' using errcode = 'P0001';
    end if;
  end if;

  update public.admin_action_intents set consumed_at = now(), consumed_by_request = p_request_id
  where id = p_intent_id;
  update public.announcements set status = 'queued', queued_at = now(), pending_count = targeted_count
  where id = v_announcement.id;
  insert into public.admin_audit_events
    (actor_user_id, action, outcome, target_type, target_id, request_id, metadata)
  values (
    p_actor_user_id, 'announcement.queue', 'allowed', 'announcement',
    v_announcement.id::text, p_request_id,
    jsonb_build_object('audience', v_announcement.audience,
      'recipientCount', v_announcement.targeted_count, 'overrideCap', v_announcement.override_cap)
  );
  return jsonb_build_object('announcementId', v_announcement.id, 'alreadyConsumed', false,
    'status', 'queued', 'recipientCount', v_announcement.targeted_count);
end
$$;

create or replace function public.admin_recover_stuck_announcement_deliveries(
  p_actor_user_id uuid, p_announcement_id uuid, p_older_than_seconds integer default 300
)
returns integer language plpgsql security definer
set search_path = pg_catalog, public as $$
declare v_count integer;
begin
  if not public.admin_permission_allowed(p_actor_user_id, 'announcements.send') then
    raise exception 'announcement permission denied' using errcode = '42501';
  end if;
  update public.announcement_deliveries d
  set status = case
        when d.attempts >= 10 or d.payload_expires_at <= now() then 'permanent_failure'
        else 'retryable'
      end,
      next_attempt_at = now(), claimed_at = null, claim_token = null,
      response_reason = case
        when d.payload_expires_at <= now() then 'AnnouncementExpired'
        when d.attempts >= 10 then 'RetryLimitExceeded'
        else 'WorkerLeaseExpired'
      end,
      token_snapshot = case
        when d.attempts >= 10 or d.payload_expires_at <= now() then null
        else d.token_snapshot
      end,
      updated_at = now()
  where d.announcement_id = p_announcement_id and d.status = 'claimed'
    and d.claimed_at < now() - make_interval(
      secs => greatest(60, least(coalesce(p_older_than_seconds, 300), 3600))
    );
  get diagnostics v_count = row_count;
  return v_count;
end
$$;

drop function if exists public.admin_claim_announcement_deliveries(uuid, uuid, uuid, integer);
create or replace function public.admin_claim_announcement_deliveries(
  p_actor_user_id uuid, p_announcement_id uuid, p_worker_token uuid, p_limit integer default 20
)
returns table (
  delivery_id bigint, device_token_id uuid, apns_token text,
  apns_environment text, release_channel text, attempt integer,
  directory_session_id uuid, token_registered_at timestamptz,
  title text, body text, link text, collapse_id text, expires_at bigint
)
language plpgsql security definer
set search_path = pg_catalog, public as $$
begin
  if not public.admin_permission_allowed(p_actor_user_id, 'announcements.send') then
    raise exception 'announcement permission denied' using errcode = '42501';
  end if;
  if p_worker_token is null then
    raise exception 'worker token required' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.announcements a
    where a.id = p_announcement_id and a.status in ('queued', 'sending')
  ) then
    raise exception 'announcement is not queued' using errcode = '22023';
  end if;
  update public.announcements a set status = 'sending', started_at = coalesce(a.started_at, now())
  where a.id = p_announcement_id and a.status in ('queued', 'sending');

  -- A preview freezes who was selected, but it never overrides a later sign
  -- out, token rotation, notification denial, or News switch change.
  update public.announcement_deliveries delivery set
    status = 'permanent_failure', response_reason = 'DeviceNoLongerEligible',
    token_snapshot = null, updated_at = now()
  where delivery.announcement_id = p_announcement_id
    and delivery.status in ('pending', 'retryable')
    and not exists (
      select 1 from public.device_tokens device
      where device.id = delivery.device_token_id
        and device.user_id = delivery.user_id_snapshot
        and device.installation_id = delivery.installation_id_snapshot
        and device.directory_session_id = delivery.directory_session_id_snapshot
        and device.apns_token = delivery.token_snapshot
        and device.news
        and device.notification_authorization in ('authorized', 'provisional', 'ephemeral')
        and exists (
          select 1 from public.directory_sessions session
          where session.id = device.directory_session_id
            and session.user_id = device.user_id
            and session.installation_id = device.installation_id
            and session.revoked_at is null and session.expires_at > now()
        )
    );

  return query
  with candidates as (
    select d.id from public.announcement_deliveries d
    where d.announcement_id = p_announcement_id
      and d.status in ('pending', 'retryable')
      and d.next_attempt_at <= now() and d.payload_expires_at > now() and d.attempts < 10
    order by d.id for update skip locked
    limit greatest(1, least(coalesce(p_limit, 20), 50))
  ), claimed as (
    update public.announcement_deliveries d
    set status = 'claimed', attempts = d.attempts + 1, claimed_at = now(),
        claim_token = p_worker_token, updated_at = now()
    from candidates c where d.id = c.id returning d.*
  )
  select c.id, c.device_token_id, c.token_snapshot, c.apns_environment,
    c.release_channel, c.attempts, c.directory_session_id_snapshot,
    c.token_registered_at_snapshot, a.title, a.body, a.link,
    coalesce(a.replaces, a.id)::text,
    extract(epoch from (a.queued_at + interval '72 hours'))::bigint
  from claimed c join public.announcements a on a.id = c.announcement_id
  order by c.id;
end
$$;

drop function if exists public.admin_finish_announcement_delivery(
  uuid, bigint, uuid, text, integer, text, text, timestamptz, text, boolean
);
drop function if exists public.admin_finish_announcement_delivery(
  uuid, bigint, uuid, text, integer, text, text, timestamptz, text, boolean, bigint
);
create or replace function public.admin_finish_announcement_delivery(
  p_actor_user_id uuid, p_delivery_id bigint, p_worker_token uuid, p_status text,
  p_response_status integer default null, p_response_reason text default null,
  p_apns_id text default null, p_next_attempt_at timestamptz default null,
  p_accepted_environment text default null, p_invalidate_token boolean default false,
  p_apns_timestamp_ms bigint default null
)
returns boolean language plpgsql security definer
set search_path = pg_catalog, public as $$
declare v_delivery public.announcement_deliveries%rowtype;
begin
  if not public.admin_permission_allowed(p_actor_user_id, 'announcements.send') then
    raise exception 'announcement permission denied' using errcode = '42501';
  end if;
  if p_status not in ('accepted', 'retryable', 'permanent_failure')
    or (p_accepted_environment is not null and p_accepted_environment not in ('sandbox', 'production'))
    or (p_response_status is not null and p_response_status not between 0 and 599)
    or (p_apns_timestamp_ms is not null and p_apns_timestamp_ms not between 1 and 32503680000000)
  then raise exception 'invalid delivery result' using errcode = '22023'; end if;
  if p_status = 'accepted' and (
    p_response_status is null or p_response_status not between 200 and 299
    or p_accepted_environment is null
  ) then
    raise exception 'an accepted delivery requires an Apple 2xx response and gateway' using errcode = '22023';
  end if;

  select * into v_delivery from public.announcement_deliveries d
  where d.id = p_delivery_id for update;
  if not found or v_delivery.status <> 'claimed' or v_delivery.claim_token <> p_worker_token then
    return false;
  end if;
  -- A normal worker completion at the retry ceiling is terminal too, not
  -- only a recovered stale lease. Otherwise claim's attempts < 10 predicate
  -- would leave an unreachable retryable row.
  if p_status = 'retryable' and v_delivery.attempts >= 10 then
    p_status := 'permanent_failure';
    p_response_reason := 'RetryLimitExceeded';
    p_next_attempt_at := null;
    p_invalidate_token := false;
  end if;
  if p_invalidate_token and (
    p_status <> 'permanent_failure'
    or p_response_reason not in ('BadDeviceToken', 'Unregistered', 'DeviceTokenNotForTopic')
    or (p_response_reason = 'Unregistered' and p_response_status <> 410)
    or (p_response_reason in ('BadDeviceToken', 'DeviceTokenNotForTopic') and p_response_status <> 400)
    or (p_response_reason = 'Unregistered' and (
      p_apns_timestamp_ms is null
      or v_delivery.token_registered_at_snapshot is null
      or to_timestamp(p_apns_timestamp_ms::double precision / 1000.0)
        < v_delivery.token_registered_at_snapshot
    ))
  ) then
    raise exception 'only an authoritative APNs token error may invalidate a token' using errcode = '22023';
  end if;

  update public.announcement_deliveries d set
    status = p_status,
    next_attempt_at = case when p_status = 'retryable'
      then greatest(coalesce(p_next_attempt_at, now() + interval '1 minute'), now())
      else d.next_attempt_at end,
    claimed_at = null, claim_token = null, response_status = p_response_status,
    response_reason = nullif(left(coalesce(p_response_reason, ''), 100), ''),
    apns_id = nullif(left(coalesce(p_apns_id, ''), 100), ''),
    accepted_at = case when p_status = 'accepted' then now() else null end,
    apns_environment = coalesce(p_accepted_environment, d.apns_environment),
    token_snapshot = case when p_status in ('accepted', 'permanent_failure') then null else d.token_snapshot end,
    updated_at = now()
  where d.id = p_delivery_id;

  if p_status = 'accepted' and p_accepted_environment is not null
    and v_delivery.device_token_id is not null
  then
    update public.device_tokens d set
      apns_environment = p_accepted_environment,
      sandbox = p_accepted_environment = 'sandbox', updated_at = now()
    where d.id = v_delivery.device_token_id
      and d.user_id = v_delivery.user_id_snapshot
      and d.installation_id = v_delivery.installation_id_snapshot
      and d.directory_session_id = v_delivery.directory_session_id_snapshot
      and d.token_registered_at = v_delivery.token_registered_at_snapshot
      and d.apns_token = v_delivery.token_snapshot;
  elsif p_invalidate_token and v_delivery.device_token_id is not null then
    delete from public.device_tokens d
    where d.id = v_delivery.device_token_id
      and d.user_id = v_delivery.user_id_snapshot
      and d.installation_id = v_delivery.installation_id_snapshot
      and d.directory_session_id = v_delivery.directory_session_id_snapshot
      and d.token_registered_at = v_delivery.token_registered_at_snapshot
      and d.apns_token = v_delivery.token_snapshot;
  end if;
  return true;
end
$$;

create or replace function public.purge_admin_ephemera()
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public as $$
declare
  v_expired_previews integer := 0;
  v_expired_deliveries integer := 0;
  v_cleared_tokens integer := 0;
  v_expired_intents integer := 0;
  v_expired_invites integer := 0;
  v_revoked_sessions integer := 0;
  v_deleted_sessions integer := 0;
begin
  -- An unconsumed preview has no product history value after its confirmation
  -- window. Deleting it cascades its raw-token snapshot and expired intent.
  delete from public.announcements a
  where a.status = 'previewed'
    and not exists (
      select 1 from public.admin_action_intents i
      where i.announcement_id = a.id and i.consumed_at is null and i.expires_at > now()
    );
  get diagnostics v_expired_previews = row_count;

  -- No notification is useful after its APNs payload expiry. Keep the hashed
  -- delivery result and aggregates, but make the raw token unusable.
  update public.announcement_deliveries d set
    status = 'permanent_failure', response_reason = 'AnnouncementExpired',
    claimed_at = null, claim_token = null, token_snapshot = null, updated_at = now()
  where d.payload_expires_at <= now()
    and d.status in ('pending', 'claimed', 'retryable');
  get diagnostics v_expired_deliveries = row_count;

  update public.announcement_deliveries d
  set token_snapshot = null, updated_at = now()
  where d.token_snapshot is not null
    and (d.status in ('accepted', 'permanent_failure') or d.created_at < now() - interval '30 days');
  get diagnostics v_cleared_tokens = row_count;

  delete from public.admin_action_intents i
  where i.consumed_at is not null and i.consumed_at < now() - interval '24 hours';
  get diagnostics v_expired_intents = row_count;

  delete from public.invites invite where invite.expires_at <= now();
  get diagnostics v_expired_invites = row_count;

  -- Session expiry closes every private notification route even before a
  -- client gets a chance to send explicit sign-out cleanup.
  update public.announcement_deliveries delivery set
    status = 'permanent_failure', response_reason = 'DirectorySessionExpired',
    claimed_at = null, claim_token = null, token_snapshot = null, updated_at = now()
  where delivery.status in ('pending', 'claimed', 'retryable')
    and exists (
      select 1 from public.device_tokens device
      join public.directory_sessions session on session.id = device.directory_session_id
      where device.id = delivery.device_token_id
        and device.directory_session_id = delivery.directory_session_id_snapshot
        and session.revoked_at is null and session.expires_at <= now()
    );
  delete from public.device_tokens device
  where exists (
    select 1 from public.directory_sessions session
    where session.id = device.directory_session_id
      and session.revoked_at is null and session.expires_at <= now()
  );
  update public.directory_sessions session set revoked_at = now()
  where session.revoked_at is null and session.expires_at <= now();
  get diagnostics v_revoked_sessions = row_count;
  delete from public.directory_sessions session
  where session.revoked_at < now() - interval '30 days';
  get diagnostics v_deleted_sessions = row_count;

  with counts as (
    select d.announcement_id,
      count(*)::integer targeted,
      count(*) filter (where d.status = 'accepted')::integer accepted,
      count(*) filter (where d.status = 'retryable')::integer retryable,
      count(*) filter (where d.status = 'permanent_failure')::integer permanent,
      count(*) filter (where d.status in ('pending', 'claimed', 'retryable'))::integer pending
    from public.announcement_deliveries d
    join public.announcements active on active.id = d.announcement_id
      and active.status in ('queued', 'sending')
    group by d.announcement_id
  )
  update public.announcements a set
    targeted_count = c.targeted, accepted_count = c.accepted,
    retryable_count = c.retryable, permanent_failure_count = c.permanent,
    pending_count = c.pending,
    status = case
      when a.status = 'retracted' then 'retracted'
      when c.pending > 0 then 'sending'
      when c.accepted = c.targeted and c.targeted > 0 then 'sent'
      when c.accepted > 0 then 'partial'
      else 'failed' end,
    finished_at = case when c.pending = 0 then coalesce(a.finished_at, now()) else null end
  from counts c
  where a.id = c.announcement_id and a.status in ('queued', 'sending');

  if v_expired_previews + v_expired_deliveries + v_cleared_tokens
    + v_expired_intents + v_expired_invites + v_revoked_sessions + v_deleted_sessions > 0
  then
    insert into public.admin_audit_events
      (actor_user_id, action, outcome, target_type, metadata)
    values (null, 'admin.retention', 'allowed', 'admin_ephemera', jsonb_build_object(
      'expiredPreviewCount', v_expired_previews,
      'expiredDeliveryCount', v_expired_deliveries,
      'clearedTokenCount', v_cleared_tokens,
      'expiredIntentCount', v_expired_intents,
      'expiredInviteCount', v_expired_invites,
      'revokedSessionCount', v_revoked_sessions,
      'deletedSessionCount', v_deleted_sessions
    ));
  end if;
  return jsonb_build_object(
    'expiredPreviewCount', v_expired_previews,
    'expiredDeliveryCount', v_expired_deliveries,
    'clearedTokenCount', v_cleared_tokens,
    'expiredIntentCount', v_expired_intents,
    'expiredInviteCount', v_expired_invites,
    'revokedSessionCount', v_revoked_sessions,
    'deletedSessionCount', v_deleted_sessions
  );
end
$$;

create or replace function public.admin_refresh_announcement_counts(
  p_actor_user_id uuid, p_announcement_id uuid
)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public as $$
declare
  v_targeted integer; v_accepted integer; v_retryable integer;
  v_permanent integer; v_pending integer; v_status text;
begin
  if not public.admin_permission_allowed(p_actor_user_id, 'announcements.send') then
    raise exception 'announcement permission denied' using errcode = '42501';
  end if;
  select count(*)::integer,
    count(*) filter (where d.status = 'accepted')::integer,
    count(*) filter (where d.status = 'retryable')::integer,
    count(*) filter (where d.status = 'permanent_failure')::integer,
    count(*) filter (where d.status in ('pending', 'claimed', 'retryable'))::integer
  into v_targeted, v_accepted, v_retryable, v_permanent, v_pending
  from public.announcement_deliveries d where d.announcement_id = p_announcement_id;

  if v_pending > 0 then v_status := 'sending';
  elsif v_accepted = v_targeted and v_targeted > 0 then v_status := 'sent';
  elsif v_accepted > 0 then v_status := 'partial';
  else v_status := 'failed'; end if;

  update public.announcements a set
    status = case when a.status = 'retracted' then 'retracted' else v_status end,
    targeted_count = v_targeted, accepted_count = v_accepted,
    retryable_count = v_retryable, permanent_failure_count = v_permanent,
    pending_count = v_pending,
    finished_at = case when v_pending = 0 then coalesce(a.finished_at, now()) else null end
  where a.id = p_announcement_id
  returning a.status into v_status;
  if not found then raise exception 'announcement not found' using errcode = '22023'; end if;
  return jsonb_build_object(
    'announcementId', p_announcement_id, 'status', v_status,
    'targetedCount', v_targeted, 'acceptedCount', v_accepted,
    'retryableCount', v_retryable, 'permanentFailureCount', v_permanent,
    'pendingCount', v_pending
  );
end
$$;

create or replace function public.admin_retract_announcement(
  p_actor_user_id uuid, p_announcement_id uuid, p_request_id uuid
)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public as $$
declare v_row public.announcements%rowtype; v_was_retracted boolean;
begin
  if not public.admin_permission_allowed(p_actor_user_id, 'announcements.retract') then
    raise exception 'announcement retract permission denied' using errcode = '42501';
  end if;
  select a.retracted_at is not null into v_was_retracted
  from public.announcements a where a.id = p_announcement_id;
  update public.announcements a
  set retracted_at = coalesce(a.retracted_at, now()), status = 'retracted'
  where a.id = p_announcement_id and a.status in ('sent', 'partial', 'retracted')
  returning * into v_row;
  if not found then
    raise exception 'only a completed announcement can be retracted' using errcode = '22023';
  end if;
  insert into public.admin_audit_events
    (actor_user_id, action, outcome, target_type, target_id, request_id, metadata)
  values (p_actor_user_id, 'announcement.retract', 'allowed', 'announcement',
    p_announcement_id::text, p_request_id,
    jsonb_build_object('alreadyRetracted', coalesce(v_was_retracted, false)));
  return jsonb_build_object(
    'announcementId', v_row.id, 'status', v_row.status,
    'retractedAt', v_row.retracted_at,
    'note', 'Retraction is bookkeeping. Send a correction to replace a visible notification.'
  );
end
$$;

create or replace function public.admin_read_metrics(
  p_actor_user_id uuid,
  p_operation text
)
returns jsonb language plpgsql stable security definer
set search_path = pg_catalog, public as $$
declare
  v_result jsonb;
begin
  if not public.admin_permission_allowed(p_actor_user_id, 'admin.read') then
    raise exception 'admin read permission denied' using errcode = '42501';
  end if;

  if p_operation = 'overview' then
    with active_devices as materialized (
      select device.* from public.device_tokens device
      left join public.directory_sessions session
        on session.id = device.directory_session_id
        and session.user_id = device.user_id
        and session.installation_id = device.installation_id
        and session.revoked_at is null and session.expires_at > now()
      -- A phone registered before the cutover has no session to prove and is
      -- still a phone this service reaches. Reporting it as absent would be a
      -- console that cannot see the one device there is. After the cutover
      -- the column is not null, so this branch is dead and the join is the
      -- whole rule. Sending still requires a session: see the preview.
      where device.directory_session_id is null or session.id is not null
    )
    select jsonb_build_object(
      'accounts', jsonb_build_object(
        'directoryCount', (select count(*) from public.directory_users)
      ),
      'waitlist', jsonb_build_object(
        'totalCount', (select count(*) from public.waitlist)
      ),
      'invitations', jsonb_build_object(
        'last24HoursCount', (
          select count(*) from public.invites
          where created_at >= now() - interval '24 hours' and expires_at > now()
        ),
        'retentionDays', 30
      ),
      'devices', jsonb_build_object(
        'registeredCount', (select count(*) from active_devices),
        'eligibleForNewsCount', (
          select count(*) from active_devices
          where news and notification_authorization in ('authorized', 'provisional', 'ephemeral')
        ),
        'deniedNotificationCount', (
          select count(*) from active_devices where notification_authorization = 'denied'
        ),
        'unknownAuthorizationCount', (
          select count(*) from active_devices
          where notification_authorization in ('unknown', 'not_determined')
        ),
        'byReleaseChannel', (
          select coalesce(jsonb_object_agg(x.release_channel, x.n), '{}'::jsonb)
          from (select release_channel, count(*) n from active_devices group by release_channel) x
        ),
        'byGateway', (
          select coalesce(jsonb_object_agg(x.apns_environment, x.n), '{}'::jsonb)
          from (select apns_environment, count(*) n from active_devices group by apns_environment) x
        )
      )
    ) into v_result;
  elsif p_operation = 'operations' then
    with active_devices as materialized (
      select device.* from public.device_tokens device
      left join public.directory_sessions session
        on session.id = device.directory_session_id
        and session.user_id = device.user_id
        and session.installation_id = device.installation_id
        and session.revoked_at is null and session.expires_at > now()
      -- A phone registered before the cutover has no session to prove and is
      -- still a phone this service reaches. Reporting it as absent would be a
      -- console that cannot see the one device there is. After the cutover
      -- the column is not null, so this branch is dead and the join is the
      -- whole rule. Sending still requires a session: see the preview.
      where device.directory_session_id is null or session.id is not null
    )
    select jsonb_build_object(
      'activePrincipalCount', (select count(*) from public.admin_principals where active),
      'deliveryCounts', (
        select coalesce(jsonb_object_agg(x.status, x.n), '{}'::jsonb)
        from (select status, count(*) n from public.announcement_deliveries group by status) x
      ),
      'exhaustedRetryCount', (
        select count(*) from public.announcement_deliveries
        where attempts >= 10 and status = 'retryable'
      ),
      'lastDeviceRegistrationAt', (select max(updated_at) from active_devices),
      'phonePepperConfigured', exists (
        select 1 from public.server_config where key = 'phone_salt' and value <> ''
      )
    ) into v_result;
  elsif p_operation = 'releases' then
    -- Return at most ten distinct versions per fixed release channel, ordered
    -- by the latest device report. Work is grouped in SQL and the response is
    -- bounded independently of fleet size.
    with active_devices as materialized (
      select device.* from public.device_tokens device
      left join public.directory_sessions session
        on session.id = device.directory_session_id
        and session.user_id = device.user_id
        and session.installation_id = device.installation_id
        and session.revoked_at is null and session.expires_at > now()
      -- A phone registered before the cutover has no session to prove and is
      -- still a phone this service reaches. Reporting it as absent would be a
      -- console that cannot see the one device there is. After the cutover
      -- the column is not null, so this branch is dead and the join is the
      -- whole rule. Sending still requires a session: see the preview.
      where device.directory_session_id is null or session.id is not null
    ), channel_totals as (
      select release_channel, count(*) device_count, max(app_build) highest_build
      from active_devices group by release_channel
    ), version_activity as (
      select release_channel, app_version, max(updated_at) last_seen_at
      from active_devices
      where app_version is not null
      group by release_channel, app_version
    ), ranked_versions as (
      select release_channel, app_version, last_seen_at,
        row_number() over (
          partition by release_channel order by last_seen_at desc, app_version desc
        ) version_rank
      from version_activity
    ), version_lists as (
      select release_channel,
        jsonb_agg(app_version order by last_seen_at desc, app_version desc) versions
      from ranked_versions where version_rank <= 10
      group by release_channel
    )
    select jsonb_build_object(
      'deviceReported', coalesce(jsonb_object_agg(t.release_channel, jsonb_build_object(
        'deviceCount', t.device_count,
        'highestBuild', t.highest_build,
        'versions', coalesce(v.versions, '[]'::jsonb)
      )), '{}'::jsonb)
    ) into v_result
    from channel_totals t
    left join version_lists v using (release_channel);
  else
    raise exception 'invalid admin metrics operation' using errcode = '22023';
  end if;
  return coalesce(v_result, '{}'::jsonb);
end
$$;

-- Privileged relations are service-only, even if a future policy is added by
-- mistake. RLS remains a second boundary.
alter table public.directory_users enable row level security;
alter table public.directory_sessions enable row level security;
alter table public.invites enable row level security;
alter table public.device_tokens enable row level security;
alter table public.admin_principals enable row level security;
alter table public.announcements enable row level security;
alter table public.admin_action_intents enable row level security;
alter table public.announcement_deliveries enable row level security;
alter table public.admin_audit_events enable row level security;

-- These predate the founder console but contain email, pepper, or integration
-- state. Keep their existing Edge Function access while closing direct browser
-- grants when the relation exists in this project.
do $$
declare v_table text;
begin
  foreach v_table in array array['server_config', 'waitlist', 'instacart_links', 'instacart_rate_limits']
  loop
    if to_regclass('public.' || v_table) is not null then
      execute format('alter table public.%I enable row level security', v_table);
      execute format('revoke all on table public.%I from public, anon, authenticated', v_table);
      execute format('grant all on table public.%I to service_role', v_table);
    end if;
  end loop;
end
$$;

revoke all on table public.directory_users, public.directory_sessions, public.invites, public.device_tokens,
  public.admin_principals, public.announcements, public.admin_action_intents,
  public.announcement_deliveries, public.admin_audit_events
from public, anon, authenticated;

grant all on table public.directory_users, public.directory_sessions, public.invites, public.device_tokens,
  public.admin_principals, public.announcements, public.admin_action_intents,
  public.announcement_deliveries to service_role;
grant select, insert on table public.admin_audit_events to service_role;
grant usage, select on sequence public.announcement_deliveries_id_seq to service_role;
grant usage, select on sequence public.admin_audit_events_id_seq to service_role;

revoke all on function public.prevent_admin_audit_mutation() from public, anon, authenticated;
revoke all on function public.admin_permission_allowed(uuid, text) from public, anon, authenticated;
revoke all on function public.admin_record_audit_event(uuid, text, text, text, text, uuid, jsonb) from public, anon, authenticated;
revoke all on function public.register_directory_session(text, text, text, uuid, text) from public, anon, authenticated;
revoke all on function public.resolve_directory_session(uuid, text, uuid) from public, anon, authenticated;
revoke all on function public.upsert_device_token(uuid, text, uuid, text, text, text, integer, text, text, boolean) from public, anon, authenticated;
revoke all on function public.unregister_directory_session(uuid, text, uuid, text) from public, anon, authenticated;
revoke all on function public.record_invite_attempt(uuid, text, text, boolean) from public, anon, authenticated;
revoke all on function public.admin_preview_announcement(uuid, text, text, text, text, integer, uuid, boolean, integer) from public, anon, authenticated;
revoke all on function public.admin_consume_announcement_intent(uuid, uuid, text, uuid) from public, anon, authenticated;
revoke all on function public.admin_recover_stuck_announcement_deliveries(uuid, uuid, integer) from public, anon, authenticated;
revoke all on function public.admin_claim_announcement_deliveries(uuid, uuid, uuid, integer) from public, anon, authenticated;
revoke all on function public.admin_finish_announcement_delivery(uuid, bigint, uuid, text, integer, text, text, timestamptz, text, boolean, bigint) from public, anon, authenticated;
revoke all on function public.admin_refresh_announcement_counts(uuid, uuid) from public, anon, authenticated;
revoke all on function public.admin_retract_announcement(uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function public.admin_read_metrics(uuid, text) from public, anon, authenticated;
revoke all on function public.purge_admin_ephemera() from public, anon, authenticated;

grant execute on function public.admin_permission_allowed(uuid, text) to service_role;
grant execute on function public.admin_record_audit_event(uuid, text, text, text, text, uuid, jsonb) to service_role;
grant execute on function public.register_directory_session(text, text, text, uuid, text) to service_role;
grant execute on function public.resolve_directory_session(uuid, text, uuid) to service_role;
grant execute on function public.upsert_device_token(uuid, text, uuid, text, text, text, integer, text, text, boolean) to service_role;
grant execute on function public.unregister_directory_session(uuid, text, uuid, text) to service_role;
grant execute on function public.record_invite_attempt(uuid, text, text, boolean) to service_role;
grant execute on function public.admin_preview_announcement(uuid, text, text, text, text, integer, uuid, boolean, integer) to service_role;
grant execute on function public.admin_consume_announcement_intent(uuid, uuid, text, uuid) to service_role;
grant execute on function public.admin_recover_stuck_announcement_deliveries(uuid, uuid, integer) to service_role;
grant execute on function public.admin_claim_announcement_deliveries(uuid, uuid, uuid, integer) to service_role;
grant execute on function public.admin_finish_announcement_delivery(uuid, bigint, uuid, text, integer, text, text, timestamptz, text, boolean, bigint) to service_role;
grant execute on function public.admin_refresh_announcement_counts(uuid, uuid) to service_role;
grant execute on function public.admin_retract_announcement(uuid, uuid, uuid) to service_role;
grant execute on function public.admin_read_metrics(uuid, text) to service_role;
grant execute on function public.purge_admin_ephemera() to service_role;

do $$
begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    revoke all on function public.rls_auto_enable() from public, anon, authenticated;
  end if;
end
$$;

-- Hourly enforcement keeps preview snapshots bounded even when nobody opens
-- the console. Reusing the job name updates the schedule on a migration rerun.
select cron.schedule(
  'plated-admin-retention',
  '17 * * * *',
  'select public.purge_admin_ephemera()'
);

-- Bootstrap is intentionally manual after the invited founder has completed
-- Supabase Auth enrollment. Replace the UUID with auth.users.id:
-- insert into public.admin_principals (user_id, directory_user_id, role, permissions)
-- values ('<auth-user-uuid>', '<directory-user-uuid>', 'founder', array[
--   'admin.read', 'announcements.send', 'announcements.retract',
--   'announcements.override_caps'
-- ]::text[]);
