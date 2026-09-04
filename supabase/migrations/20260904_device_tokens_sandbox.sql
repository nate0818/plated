-- The directory tables as /register and /lookup already use them, restated
-- here so the migration can be read on its own. `if not exists` keeps it a
-- no-op against the live project, where the four tables were created by
-- hand on 2026-09-02 with RLS on and no policies (service role only).
create table if not exists public.directory_users (
  id uuid primary key default gen_random_uuid(),
  apple_user_id text not null unique,
  display_name text not null default '',
  phone_hash text unique,
  api_token uuid not null default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.invites (
  id uuid primary key default gen_random_uuid(),
  inviter_id uuid not null references public.directory_users(id),
  invitee_phone_hash text not null,
  status text not null default 'sent',
  created_at timestamptz not null default now()
);

create table if not exists public.device_tokens (
  user_id uuid not null references public.directory_users(id),
  apns_token text not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, apns_token)
);

-- APNs has two gateways and a token minted on a development build is only
-- valid at the sandbox one. Without remembering which, every push to a
-- TestFlight phone would be sent to the wrong door and fail as BadDeviceToken.
alter table public.device_tokens
  add column if not exists sandbox boolean not null default false;

-- Invites now carry what the push needs to say and where it goes. The share
-- URL is the credential for a seat, so it is kept only on rows whose number
-- belongs to somebody, and this table stays readable by the service role
-- only: RLS on, no policies, like everything else here.
alter table public.invites
  add column if not exists host_name text not null default '',
  add column if not exists share_url text not null default '';

-- The per-day counts /invite keeps.
create index if not exists invites_inviter_created_idx
  on public.invites (inviter_id, created_at desc);
create index if not exists invites_pair_created_idx
  on public.invites (inviter_id, invitee_phone_hash, created_at desc);

alter table public.directory_users enable row level security;
alter table public.invites enable row level security;
alter table public.device_tokens enable row level security;
grant all on public.directory_users, public.invites, public.device_tokens to service_role;
