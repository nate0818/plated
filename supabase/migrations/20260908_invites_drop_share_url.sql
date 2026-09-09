-- STEP 3 OF 3. Do not apply this until the new `invite` function is
-- deployed and serving.
--
--   1. apply 20260907_invites_kind.sql (adds `kind`)
--   2. supabase functions deploy invite --no-verify-jwt
--   3. apply this file
--
-- The function live on the project before step 2 writes `share_url` on every
-- insert. Applied before that deploy, this file takes the column out from
-- under it and every invitation starts failing. After the deploy it is safe:
-- the new function never writes `share_url` or `seat`.
--
-- These drops are irreversible and the update below runs against live rows,
-- so this is the one file here worth reading before running. `supabase db
-- push` would apply it alongside step 1 and skip the deploy between them;
-- apply it by name instead.

-- The share URL is a bearer credential for a seat, and nothing ever read it
-- back out of this table: /invite composes the push link from the request it
-- was given. So the row stops carrying one, and stops carrying the seat name
-- with it, which is meaningless without the share it belongs to. The row that
-- remains is the record that an invitation happened, which is what the daily
-- limits count and what docs/privacy-policy.md describes.
--
-- Blanked before the drop so the value leaves the live rows and not just the
-- schema. Guarded so a re-run against a table that has already lost the
-- column is a no-op rather than an error.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'invites'
      and column_name = 'share_url'
  ) then
    update public.invites set share_url = '' where share_url <> '';
  end if;
end $$;

alter table public.invites
  drop column if exists share_url,
  drop column if exists seat;
