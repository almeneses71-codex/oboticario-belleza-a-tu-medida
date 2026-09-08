begin;
set local statement_timeout = '15s';
set local lock_timeout = '5s';

create temporary table funnel_test_results (
  test text,
  passed boolean
) on commit drop;

do $test$
declare
  journey_dar constant text := '11111111111111111111111111111111';
  journey_ana constant text := '22222222222222222222222222222222';
  product_row public.products%rowtype;
  first_open uuid;
  duplicate_open uuid;
  rejected boolean;
begin
  select * into product_row
  from public.products
  where active and available and eligible and not is_suggested_kit
  order by id
  limit 1;
  if product_row.id is null then raise exception 'No eligible test product'; end if;

  first_open := public.record_pilot_funnel_event(jsonb_build_object(
    'journeyId', journey_dar,
    'eventType', 'app_open',
    'attribution', jsonb_build_object(
      'sellerId', 'DAR', 'channelId', 'whatsapp',
      'source', 'whatsapp', 'campaignId', 'AMOR_AMISTAD_2026')));
  perform public.record_pilot_funnel_event(jsonb_build_object(
    'journeyId', journey_dar, 'eventType', 'diagnosis_started',
    'attribution', jsonb_build_object('sellerId', 'DAR', 'channelId', 'whatsapp',
      'source', 'whatsapp', 'campaignId', 'AMOR_AMISTAD_2026')));
  perform public.record_pilot_funnel_event(jsonb_build_object(
    'journeyId', journey_dar, 'eventType', 'diagnosis_completed',
    'attribution', jsonb_build_object('sellerId', 'DAR', 'channelId', 'whatsapp',
      'source', 'whatsapp', 'campaignId', 'AMOR_AMISTAD_2026')));
  perform public.record_pilot_funnel_event(jsonb_build_object(
    'journeyId', journey_dar, 'eventType', 'recommendation_viewed',
    'productId', product_row.id, 'productCode', product_row.code,
    'attribution', jsonb_build_object('sellerId', 'DAR', 'channelId', 'whatsapp',
      'source', 'whatsapp', 'campaignId', 'AMOR_AMISTAD_2026')));
  perform public.record_pilot_funnel_event(jsonb_build_object(
    'journeyId', journey_dar, 'eventType', 'product_selected',
    'productId', product_row.id, 'productCode', product_row.code,
    'attribution', jsonb_build_object('sellerId', 'DAR', 'channelId', 'whatsapp',
      'source', 'whatsapp', 'campaignId', 'AMOR_AMISTAD_2026')));
  perform public.record_pilot_funnel_event(jsonb_build_object(
    'journeyId', journey_dar, 'eventType', 'request_started',
    'productId', product_row.id, 'productCode', product_row.code,
    'attribution', jsonb_build_object('sellerId', 'DAR', 'channelId', 'whatsapp',
      'source', 'whatsapp', 'campaignId', 'AMOR_AMISTAD_2026')));

  insert into funnel_test_results values
    ('six valid event types', (
      select count(*) = 6 and count(distinct event_type) = 6
      from public.pilot_funnel_events where journey_id = journey_dar)),
    ('DAR attribution resolved', exists (
      select 1 from public.pilot_funnel_events event
      join public.sellers seller on seller.id = event.seller_id
      where event.journey_id = journey_dar and seller.code = 'DAR')),
    ('WhatsApp channel resolved', exists (
      select 1 from public.pilot_funnel_events event
      join public.channels channel on channel.id = event.channel_id
      where event.journey_id = journey_dar and channel.code = 'whatsapp')),
    ('campaign resolved', exists (
      select 1 from public.pilot_funnel_events event
      join public.campaigns campaign on campaign.id = event.campaign_id
      where event.journey_id = journey_dar
        and campaign.code = 'AMOR_AMISTAD_2026')),
    ('product id and code agree', exists (
      select 1 from public.pilot_funnel_events event
      where event.journey_id = journey_dar
        and event.event_type = 'product_selected'
        and event.product_id = product_row.id
        and event.product_code = product_row.code));

  duplicate_open := public.record_pilot_funnel_event(jsonb_build_object(
    'journeyId', journey_dar, 'eventType', 'app_open',
    'attribution', jsonb_build_object('sellerId', 'DAR', 'source', 'whatsapp')));
  perform public.record_pilot_funnel_event(jsonb_build_object(
    'journeyId', journey_dar, 'eventType', 'product_selected',
    'productId', product_row.id, 'productCode', product_row.code,
    'attribution', jsonb_build_object('sellerId', 'DAR', 'source', 'whatsapp')));
  insert into funnel_test_results values
    ('duplicate app_open returns original', duplicate_open = first_open),
    ('duplicate app_open ignored', (
      select count(*) = 1 from public.pilot_funnel_events
      where journey_id = journey_dar and event_type = 'app_open')),
    ('duplicate product selection ignored', (
      select count(*) = 1 from public.pilot_funnel_events
      where journey_id = journey_dar and event_type = 'product_selected'
        and product_id = product_row.id));

  perform public.record_pilot_funnel_event(jsonb_build_object(
    'journeyId', journey_ana, 'eventType', 'app_open',
    'attribution', jsonb_build_object('sellerId', 'ANA', 'channelId', 'whatsapp',
      'source', 'whatsapp', 'campaignId', 'AMOR_AMISTAD_2026')));
  insert into funnel_test_results values ('ANA attribution resolved', exists (
    select 1 from public.pilot_funnel_events event
    join public.sellers seller on seller.id = event.seller_id
    where event.journey_id = journey_ana and seller.code = 'ANA'));

  rejected := false;
  begin
    perform public.record_pilot_funnel_event(jsonb_build_object(
      'journeyId', journey_ana, 'eventType', 'unknown_event',
      'attribution', '{}'::jsonb));
  exception when others then rejected := sqlerrm = 'invalid_funnel_event'; end;
  insert into funnel_test_results values ('invalid event rejected', rejected);

  rejected := false;
  begin
    perform public.record_pilot_funnel_event(jsonb_build_object(
      'journeyId', 'invalid', 'eventType', 'app_open',
      'attribution', '{}'::jsonb));
  exception when others then rejected := sqlerrm = 'invalid_journey_id'; end;
  insert into funnel_test_results values ('invalid journey rejected', rejected);

  rejected := false;
  begin
    perform public.record_pilot_funnel_event(jsonb_build_object(
      'journeyId', '33333333333333333333333333333333',
      'eventType', 'product_selected', 'productId', 'DOES-NOT-EXIST',
      'productCode', 'DOES-NOT-EXIST', 'attribution', '{}'::jsonb));
  exception when others then rejected := sqlerrm = 'invalid_funnel_product'; end;
  insert into funnel_test_results values ('invalid product rejected', rejected);

  rejected := false;
  begin
    perform public.record_pilot_funnel_event(jsonb_build_object(
      'journeyId', '44444444444444444444444444444444',
      'eventType', 'app_open', 'whatsapp', '573001234567',
      'attribution', '{}'::jsonb));
  exception when others then rejected := sqlerrm = 'personal_data_not_allowed'; end;
  insert into funnel_test_results values ('personal data rejected', rejected);

  insert into funnel_test_results values
    ('anon can execute RPC', has_function_privilege(
      'anon', 'public.record_pilot_funnel_event(jsonb)', 'EXECUTE')),
    ('authenticated can execute RPC', has_function_privilege(
      'authenticated', 'public.record_pilot_funnel_event(jsonb)', 'EXECUTE')),
    ('anon cannot select', not has_table_privilege(
      'anon', 'public.pilot_funnel_events', 'SELECT')),
    ('anon cannot insert directly', not has_table_privilege(
      'anon', 'public.pilot_funnel_events', 'INSERT')),
    ('anon cannot update', not has_table_privilege(
      'anon', 'public.pilot_funnel_events', 'UPDATE')),
    ('anon cannot delete', not has_table_privilege(
      'anon', 'public.pilot_funnel_events', 'DELETE')),
    ('RLS enabled', (
      select relrowsecurity from pg_class
      where oid = 'public.pilot_funnel_events'::regclass)),
    ('no personal columns', not exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'pilot_funnel_events'
        and column_name in ('name', 'whatsapp', 'address', 'customer', 'answers'))),
    ('commercial event enum unchanged', (
      select array_agg(enumlabel order by enumsortorder)
        = array['cross_sell_shown', 'complementary_added', 'complementary_removed']
      from pg_enum where enumtypid = 'public.commercial_event_name'::regtype));

  if exists (select 1 from funnel_test_results where passed is distinct from true) then
    raise exception 'Pilot funnel regression failed: %',
      (select jsonb_agg(to_jsonb(result)) from funnel_test_results result
       where passed is distinct from true);
  end if;
end $test$;

select * from funnel_test_results order by test;
rollback;
