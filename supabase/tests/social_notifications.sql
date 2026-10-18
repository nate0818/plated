begin;
do $$
declare
  u uuid:=gen_random_uuid(); i uuid:=gen_random_uuid(); i2 uuid:=gen_random_uuid(); j record; n integer; keys text[];
  event jsonb;
begin
  if has_table_privilege('anon','public.social_installations','SELECT') or has_table_privilege('authenticated','public.social_events','SELECT')
    or has_function_privilege('anon','public.social_claim(integer)','EXECUTE') then raise exception 'public notification access'; end if;
  insert into public.directory_users(id,apple_user_id,display_name) values(u,'social-test-'||u,'Notification test');
  perform public.social_register(i,u,'recipient','development',repeat('a',64),'{"enabled":true,"authorized":true}');
  event:=jsonb_build_object('room','development|owner|PlatedTable|share-test','actor','author','actorName','Author','members',jsonb_build_array('author','recipient'),
    'occurredAt',extract(epoch from now())*1000,'cancelled',false,'notices',jsonb_build_array(jsonb_build_object('key','note:test','recipient','recipient','kind','comment','category','comments','post','post','direct',true,'title','Comment','body','Test')));
  perform public.social_enqueue('social-test-1','development',event);
  perform public.social_enqueue('social-test-1','development',event);
  select count(*) into n from public.social_deliveries where event_id='social-test-1';
  if n<>1 then raise exception 'duplicate delivery: %',n; end if;
  keys:=public.social_local_claim(u,i,array['note:test']);
  if cardinality(keys)<>0 then raise exception 'local duplicates server'; end if;
  select * into j from public.social_claim(1);
  if j.event_id<>'social-test-1' or j.attempts<>1 then raise exception 'claim failed'; end if;
  select count(*) into n from public.social_claim(1);
  if n<>0 then raise exception 'leased work claimed twice'; end if;
  perform public.social_finish(j.delivery_id,gen_random_uuid(),'accepted','wrong lease',null,1,false,repeat('a',64),j.registered_at);
  if (select state from public.social_deliveries where id=j.delivery_id)<>'sending' then raise exception 'foreign lease completed'; end if;
  perform public.social_finish(j.delivery_id,j.lease_id,'pending','retry',null,15,false,repeat('a',64),j.registered_at);
  if (select state from public.social_deliveries where id=j.delivery_id)<>'pending' then raise exception 'retry dropped'; end if;
  update public.social_deliveries set next_attempt_at=now()-interval '1 second' where id=j.delivery_id;
  select * into j from public.social_claim(1);
  if j.attempts<>2 then raise exception 'attempt counter'; end if;
  perform public.social_finish(j.delivery_id,j.lease_id,'accepted','', 'apns-test',1,false,repeat('a',64),j.registered_at);
  select count(*) into n from public.social_claim(1);
  if n<>0 then raise exception 'accepted delivery replayed'; end if;

  keys:=public.social_local_claim(u,i,array['note:local']);
  if keys<>array['note:local'] then raise exception 'local claim denied'; end if;
  event:=jsonb_set(event,'{notices,0,key}','"note:local"');
  perform public.social_enqueue('social-test-2','development',event);
  if exists(select 1 from public.social_deliveries where event_id='social-test-2') then raise exception 'server duplicates local'; end if;

  event:=jsonb_set(event,'{notices,0,key}','"note:cancel"');
  perform public.social_enqueue('social-test-3','development',event);
  perform public.social_enqueue('social-test-3','development',jsonb_set(event,'{cancelled}','true'));
  if (select state from public.social_deliveries where event_id='social-test-3')<>'suppressed' then raise exception 'cancelled event still pending'; end if;

  event:=jsonb_set(event,'{notices,0,key}','"note:removal"');
  perform public.social_enqueue('social-test-4','development',event);
  perform public.social_reconcile_room(event->>'room',array['recipient']);
  if (select state from public.social_deliveries where event_id='social-test-4')<>'suppressed' then raise exception 'removed sender still pending'; end if;

  perform public.social_register(i2,u,'different-cloud-account','development',repeat('a',64),'{"enabled":true}');
  if exists(select 1 from public.social_installations where id=i) then raise exception 'old account token binding survived'; end if;
  if exists(select 1 from public.social_deliveries where installation_id=i) then raise exception 'old account deliveries survived'; end if;
  if not exists(select 1 from public.social_installations where id=i2 and cloud_id='different-cloud-account') then raise exception 'new binding missing'; end if;
end $$;
select 'social queue, authorization, deduplication, leases, retries, cancellation and account-boundary checks passed' as result;
rollback;
