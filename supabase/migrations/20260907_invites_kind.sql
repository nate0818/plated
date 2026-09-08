-- An invitation is now to one of two rooms: a seat at the host's Table, or
-- a place in the host's household (the plan, the grocery list and the
-- cookbook). /invite composes a different banner for each, and the app opens
-- a different sheet, so the row has to remember which it was. The default is
-- 'table' because every row before this date was one, and because an older
-- build that never sends `kind` is still inviting people to its Table.
-- docs/household.md sections 6 and 7.
alter table public.invites
  add column if not exists kind text not null default 'table';

-- The share URL is a bearer credential for a seat, and nothing ever read it
-- back out of this table: /invite composes the push link from the request it
-- was given. So the row stops carrying one, and stops carrying the seat name
-- with it, which is meaningless without the share it belongs to. The row that
-- remains is the record that an invitation happened, which is what the daily
-- limits count and what docs/privacy-policy.md describes.
--
-- Blanked before the drop so the value leaves the live rows and not just the
-- schema. Guarded so a re-run against a table that has already lost the
-- column is a no-op rather than an error, like the rest of this file.
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
