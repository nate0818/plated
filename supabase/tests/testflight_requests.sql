-- Integration assertions are rolled back, including all synthetic addresses.
begin;
do $$
declare actor uuid; request uuid := gen_random_uuid(); launch uuid := gen_random_uuid(); result jsonb; lease uuid;
begin
  select user_id into actor from public.admin_principals where role='founder' and active limit 1;
  if actor is null then raise exception 'An active founder is required for this test'; end if;
  begin
    perform public.admin_assert_testflight_founder(gen_random_uuid());
    raise exception 'Non-founder authorization failed open';
  exception when insufficient_privilege then null;
  end;
  insert into public.waitlist(id,email,source) values(request,'plated-qa-'||request||'@example.invalid','plated.food/early-access'),(launch,'plated-qa-'||launch||'@example.invalid','plated.food');
  perform public.admin_claim_testflight_request(actor,request,'archive');
  if (select status from public.testflight_requests where request_id=request)<>'archived' then raise exception 'Archive failed'; end if;
  perform public.admin_claim_testflight_request(actor,request,'restore');
  result := public.admin_claim_testflight_request(actor,request,'invite');
  if not (result->>'maySend')::boolean then raise exception 'New request was not eligible'; end if;
  lease := (result->>'leaseId')::uuid;
  result := public.admin_claim_testflight_request(actor,request,'invite');
  if not (result->>'busy')::boolean then raise exception 'Concurrent invite was not serialized'; end if;
  if public.admin_finish_testflight_request(actor,request,gen_random_uuid(),'invited','qa','INVITED','qa',null) then raise exception 'Stale result overwrote lease'; end if;
  perform public.admin_finish_testflight_request(actor,request,lease,'uncertain',null,null,'qa','apple_timeout');
  result := public.admin_claim_testflight_request(actor,request,'invite');
  if (result->>'maySend')::boolean then raise exception 'Ambiguous retry was permitted to send'; end if;
  lease := (result->>'leaseId')::uuid;
  perform public.admin_finish_testflight_request(actor,request,lease,'invited','qa','INVITED','qa',null);
  result := public.admin_claim_testflight_request(actor,request,'invite');
  if (result->>'maySend')::boolean then raise exception 'Confirmed invitation was permitted to resend'; end if;
  lease := (result->>'leaseId')::uuid;
  perform public.admin_finish_testflight_request(actor,request,lease,'installed','qa','INSTALLED','qa',null);
  result := public.admin_list_testflight_requests(actor,'invited',0,50);
  if (result->'counts'->>'invited')::int < 1 then raise exception 'Invited count did not include installed tester'; end if;
  begin
    perform public.admin_claim_testflight_request(actor,launch,'invite');
    raise exception 'Launch-only subscriber was eligible';
  exception when no_data_found then null;
  end;
  -- Expired work is reconciled, never treated as a fresh request.
  update public.testflight_requests set status='sending',lease_expires_at=now()-interval '1 second' where request_id=request;
  result := public.admin_claim_testflight_request(actor,request,'invite');
  if (result->>'maySend')::boolean or result->>'previousStatus'<>'uncertain' then raise exception 'Expired send was not protected'; end if;
end $$;
rollback;
