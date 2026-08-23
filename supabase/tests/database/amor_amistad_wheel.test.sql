begin;
create extension if not exists pgtap with schema extensions;
select plan(21);

select has_table('public', 'campaign_wheel_spins', 'wheel awards are persisted');
select has_column('public', 'orders', 'promotion_spin_id', 'order links its protected award');
select results_eq(
  $$select count(*)::bigint from public.campaigns where code = 'AMOR_AMISTAD_2026'$$,
  array[1::bigint],
  'campaign is configured once'
);
select is(public.round_cop_to_100(70123), 70100, '70123 rounds down');
select is(public.round_cop_to_100(70149), 70100, '70149 rounds down');
select is(public.round_cop_to_100(70150), 70200, 'half hundred rounds up');
select is(public.round_cop_to_100(70168), 70200, '70168 rounds up');
select isnt(
  public.amor_amistad_2026_is_active('2026-08-31 23:59:59 America/Bogota'),
  true,
  'wheel is unavailable before September 1 in Colombia'
);
select isnt(
  public.amor_amistad_2026_is_active('2026-09-20 00:00:00 America/Bogota'),
  true,
  'wheel is unavailable from September 20 in Colombia'
);

update public.campaigns
set starts_at = now() - interval '1 day', ends_at = now() + interval '1 day'
where code = 'AMOR_AMISTAD_2026';

create temporary table wheel_test_results as
select public.spin_amor_amistad_2026(
  jsonb_build_object(
    'customer', jsonb_build_object('name', 'Cliente Ruleta', 'whatsapp', '573009991111'),
    'items', jsonb_build_array(
      jsonb_build_object('productId', 'OB001', 'productCode', '60138', 'quantity', 1),
      jsonb_build_object('productId', 'OB017', 'quantity', 1)
    )
  )
) result;

select ok((result->>'discount_percent')::integer in (5, 10, 15), 'server awards only configured prizes')
from wheel_test_results;
select is(
  (result->>'products_cop')::integer,
  (select sum(current_price_cop)::integer from public.products where id in ('OB001', 'OB017')),
  'server prices primary and complementary together'
) from wheel_test_results;

create temporary table recovered_wheel_result as
select public.spin_amor_amistad_2026(
  jsonb_build_object(
    'customer', jsonb_build_object('name', 'Cliente Ruleta', 'whatsapp', '3009991111'),
    'items', jsonb_build_array(jsonb_build_object('productId', 'OB001', 'quantity', 1))
  )
) result;

select is(
  (select result->>'spin_id' from recovered_wheel_result),
  (select result->>'spin_id' from wheel_test_results),
  'same normalized WhatsApp recovers the same spin'
);
select is(
  (select count(*)::integer from public.campaign_wheel_spins spin
    join public.customers customer on customer.id = spin.customer_id
    where customer.whatsapp = '573009991111'),
  1,
  'customer and campaign uniqueness blocks a second spin'
);

create temporary table other_customer_result as
select public.spin_amor_amistad_2026(
  jsonb_build_object(
    'customer', jsonb_build_object('name', 'Otro Cliente', 'whatsapp', '573009992222'),
    'items', jsonb_build_array(jsonb_build_object('productId', 'OB001', 'quantity', 1))
  )
) result;
select isnt(
  (select result->>'spin_id' from other_customer_result),
  (select result->>'spin_id' from wheel_test_results),
  'a different customer gets an independent award'
);

update public.campaign_wheel_spins
set discount_percent = 10
where id = (select (result->>'spin_id')::uuid from wheel_test_results);

create temporary table created_wheel_order as
select public.create_order_request_with_delivery(
  jsonb_build_object(
    'journeyId', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'customer', jsonb_build_object(
      'name', 'Cliente Ruleta', 'whatsapp', '573009991111',
      'acceptsDataProcessing', true, 'acceptsPromotions', false
    ),
    'attribution', jsonb_build_object('sellerId', 'DAR', 'channelId', 'directo', 'source', 'directo'),
    'items', jsonb_build_array(jsonb_build_object(
      'productId', 'OB001', 'productCode', '60138', 'itemType', 'primary', 'quantity', 1
    )),
    'requiresDelivery', true
  )
) result;

select is(
  (select discount_cop from public.orders where id =
    (select (result->>'order_id')::uuid from created_wheel_order)),
  (select current_price_cop - public.round_cop_to_100(current_price_cop * 0.90)
    from public.products where id = 'OB001'),
  'order discount is recalculated from protected price at 10 percent'
);
select is(
  (select shipping_cop from public.orders where id =
    (select (result->>'order_id')::uuid from created_wheel_order)),
  0,
  'shipping is outside the promotional discount'
);
select ok(
  (select promotion_spin_id is not null from public.orders where id =
    (select (result->>'order_id')::uuid from created_wheel_order)),
  'order preserves its campaign award'
);
select ok(
  (select initial_order_id is not null from public.campaign_wheel_spins where id =
    (select (result->>'spin_id')::uuid from wheel_test_results)),
  'first order is audited on the immutable spin'
);

update public.orders set status = 'cancelled' where id =
  (select (result->>'order_id')::uuid from created_wheel_order);
select is(
  (select count(*)::integer from public.campaign_wheel_spins where id =
    (select (result->>'spin_id')::uuid from wheel_test_results)),
  1,
  'cancellation does not restore another spin'
);
select ok(
  pg_get_functiondef('public.sync_order_commissions()'::regprocedure)
    like '%new.subtotal_cop - new.discount_cop%',
  'commission base uses product revenue after discount'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.campaign_wheel_spins'::regclass),
  'wheel table has RLS enabled'
);

select * from finish();
rollback;
