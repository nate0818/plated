-- Server-only cache and a durable, per-account limit. No client grants.
create table if not exists public.instacart_links (
    user_id text not null,
    fingerprint text not null,
    products_link_url text,
    expires_at timestamptz not null default now(),
    primary key (user_id, fingerprint)
);
alter table public.instacart_links enable row level security;
revoke all on public.instacart_links from anon, authenticated;
grant all on public.instacart_links to service_role;
create table if not exists public.instacart_rate_limits (
    user_id text primary key,
    window_start timestamptz not null,
    requests integer not null default 0
);
alter table public.instacart_rate_limits enable row level security;
revoke all on public.instacart_rate_limits from anon, authenticated;
grant all on public.instacart_rate_limits to service_role;
create or replace function public.claim_instacart_request(caller text)
returns boolean language plpgsql security invoker set search_path = '' as $$
declare used integer;
begin
    insert into public.instacart_rate_limits(user_id, window_start, requests)
    values (caller, now(), 1)
    on conflict (user_id) do update set
        requests = case when instacart_rate_limits.window_start < now() - interval '1 hour' then 1 else instacart_rate_limits.requests + 1 end,
        window_start = case when instacart_rate_limits.window_start < now() - interval '1 hour' then now() else instacart_rate_limits.window_start end
    returning requests into used;
    return used <= 30;
end;
$$;
revoke all on function public.claim_instacart_request(text) from public, anon, authenticated;
grant execute on function public.claim_instacart_request(text) to service_role;
