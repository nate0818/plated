-- Authenticated, atomic deletion of the developer-side Plated directory
-- account. The user's recipes, plans, household, Table posts and photographs
-- are private CloudKit records and are intentionally outside this transaction.
--
-- The shipping client still carries the legacy UUID bearer minted by
-- /register. The column is removed only after the gated directory-session
-- cutover, so dynamic SQL keeps this migration valid on both sides of that
-- gate: before cutover the bearer can delete the account; after cutover it
-- fails closed until the account endpoint is upgraded to resolve the new
-- per-installation session format.

create table if not exists public.directory_account_deletion_receipts (
  request_id uuid primary key,
  credential_hash text not null,
  deleted_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '24 hours'),
  check (credential_hash ~ '^[0-9a-f]{64}$'),
  check (expires_at > deleted_at)
);

create index if not exists directory_account_deletion_receipts_expiry_idx
  on public.directory_account_deletion_receipts (expires_at);

alter table public.directory_account_deletion_receipts enable row level security;
revoke all on table public.directory_account_deletion_receipts
  from public, anon, authenticated;
grant all on table public.directory_account_deletion_receipts to service_role;

create or replace function public.delete_directory_account(
  p_credential text,
  p_request_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_user_id uuid;
  v_phone_hash text;
  v_credential_hash text;
  v_receipt_hash text;
  v_announcement_ids uuid[];
begin
  p_credential := lower(btrim(coalesce(p_credential, '')));
  if p_request_id is null
    or p_credential !~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  then
    raise exception 'invalid directory account deletion request' using errcode = '22023';
  end if;

  v_credential_hash := encode(digest(p_credential, 'sha256'), 'hex');

  -- Registration, device rotation and deletion share one short lock. A delayed
  -- registration cannot recreate a row halfway through deletion.
  perform pg_advisory_xact_lock(hashtextextended('plated:directory-registration', 0));

  delete from public.directory_account_deletion_receipts receipt
  where receipt.expires_at <= now();

  select receipt.credential_hash into v_receipt_hash
  from public.directory_account_deletion_receipts receipt
  where receipt.request_id = p_request_id;
  if found then
    -- A lost HTTP response can be retried with the same request id and bearer.
    -- The request id alone is never enough to claim a successful deletion.
    return v_receipt_hash = v_credential_hash;
  end if;

  -- `api_token` exists for the shipping protocol and is deliberately dropped
  -- by the future session cutover. Dynamic SQL lets the migration install in
  -- either state without accidentally accepting an unauthenticated user id.
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'directory_users'
      and column_name = 'api_token'
  ) then
    execute $query$
      select person.id, person.phone_hash
      from public.directory_users person
      where person.api_token = $1::uuid
      for update
    $query$
    into v_user_id, v_phone_hash
    using p_credential;
  end if;

  if v_user_id is null then return false; end if;

  -- Delivery rows contain installation/session identifiers and a digest of the
  -- APNs address. Remove them rather than merely detaching the device foreign
  -- key, then rebuild only the non-personal announcement aggregates.
  select array_agg(distinct delivery.announcement_id)
  into v_announcement_ids
  from public.announcement_deliveries delivery
  where delivery.user_id_snapshot = v_user_id;

  delete from public.announcement_deliveries delivery
  where delivery.user_id_snapshot = v_user_id;

  if cardinality(v_announcement_ids) > 0 then
    update public.announcements announcement set
      targeted_count = counts.targeted,
      accepted_count = counts.accepted,
      retryable_count = counts.retryable,
      permanent_failure_count = counts.permanent,
      pending_count = counts.pending
    from (
      select target.id,
        count(delivery.id)::integer as targeted,
        count(delivery.id) filter (where delivery.status = 'accepted')::integer as accepted,
        count(delivery.id) filter (where delivery.status = 'retryable')::integer as retryable,
        count(delivery.id) filter (where delivery.status = 'permanent_failure')::integer as permanent,
        count(delivery.id) filter (
          where delivery.status in ('pending', 'claimed', 'retryable')
        )::integer as pending
      from unnest(v_announcement_ids) target(id)
      left join public.announcement_deliveries delivery
        on delivery.announcement_id = target.id
      group by target.id
    ) counts
    where announcement.id = counts.id;
  end if;

  -- Delete both invitations sent by this person and invitations whose retained
  -- phone hash points at them. Unmatched invitations cannot be linked back to a
  -- directory user and remain subject to the existing 30-day retention limit.
  delete from public.invites invite
  where invite.inviter_id = v_user_id
    or (v_phone_hash is not null and invite.invitee_phone_hash = v_phone_hash);

  -- A delivery references a device with ON DELETE SET NULL, and a device
  -- references its session with ON DELETE RESTRICT. The order is intentional.
  delete from public.device_tokens device where device.user_id = v_user_id;
  delete from public.directory_sessions session where session.user_id = v_user_id;

  -- Instacart handoff rows use the directory UUID as text and may not exist in
  -- every environment. They contain no grocery contents, but removing their
  -- cached URLs and quota state closes the account cleanly where installed.
  if to_regclass('public.instacart_links') is not null then
    execute 'delete from public.instacart_links where user_id = $1'
      using v_user_id::text;
  end if;
  if to_regclass('public.instacart_rate_limits') is not null then
    execute 'delete from public.instacart_rate_limits where user_id = $1'
      using v_user_id::text;
  end if;

  -- admin_principals.directory_user_id is ON DELETE SET NULL. The independent
  -- Supabase Auth administrator identity, if any, is not a consumer account
  -- record and is deliberately not deleted here.
  delete from public.directory_users person where person.id = v_user_id;
  if not found then
    raise exception 'directory account changed during deletion' using errcode = '40001';
  end if;

  insert into public.directory_account_deletion_receipts (
    request_id, credential_hash, deleted_at, expires_at
  ) values (
    p_request_id, v_credential_hash, now(), now() + interval '24 hours'
  );

  return true;
end
$$;

revoke all on function public.delete_directory_account(text, uuid)
  from public, anon, authenticated;
grant execute on function public.delete_directory_account(text, uuid)
  to service_role;

-- Bound idempotency evidence even if no later deletion request arrives to run
-- the opportunistic purge above. The receipt contains only a request UUID and
-- the digest of a high-entropy bearer, never an Apple id or directory user id.
select cron.schedule(
  'plated-directory-deletion-receipts',
  '43 * * * *',
  'delete from public.directory_account_deletion_receipts where expires_at <= now()'
);
