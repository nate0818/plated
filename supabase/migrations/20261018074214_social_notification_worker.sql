-- Immediate sends happen in the event endpoint; this worker recovers transient
-- APNs failures and expired process leases without needing either phone awake.
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

do $$
declare secret text;
begin
  select decrypted_secret into secret from vault.decrypted_secrets where name='plated_social_worker';
  if secret is null then
    secret:=encode(extensions.gen_random_bytes(32),'hex');
    perform vault.create_secret(secret,'plated_social_worker','Authenticates only the Plated social notification retry worker');
  end if;
  insert into public.social_config(key,value) values('worker_hash',encode(extensions.digest(secret,'sha256'),'hex'))
  on conflict(key) do update set value=excluded.value;
end $$;

select cron.schedule('plated-social-delivery','* * * * *', $job$
  select net.http_post(
    url:='https://dyvrksooelbkzkprqlhk.supabase.co/functions/v1/social',
    headers:=jsonb_build_object('Content-Type','application/json','X-Plated-Worker',
      (select decrypted_secret from vault.decrypted_secrets where name='plated_social_worker')),
    body:='{"action":"drain"}'::jsonb,timeout_milliseconds:=25000
  );
$job$);
select cron.schedule('plated-social-retention','17 4 * * *',$job$
  delete from public.social_events where expires_at<now()-interval '1 day';
  delete from public.social_routes where created_at<now()-interval '7 days';
  delete from public.social_rate_limits where bucket<now()-interval '1 day';
$job$);
