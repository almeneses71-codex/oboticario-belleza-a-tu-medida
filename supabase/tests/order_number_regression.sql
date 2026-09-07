begin;
set local statement_timeout = '15s';
set local lock_timeout = '5s';
set local timezone = 'America/Bogota';

-- All fixtures, orders and counter changes are rolled back.
create temporary table number_test_results (
  test text, actual text, expected text, passed boolean
) on commit drop;

do $test$
declare
  sample record;
  product_id text;
  product_code text;
  response jsonb;
  persisted_number text;
  previous_number text;
  expected_number text;
  attempt integer;
  unique_constraint_name text;
begin
  for sample in
    select * from (values
      (1, '0001'), (9, '0009'), (10, '0010'), (999, '0999'),
      (9999, '9999'), (10000, '10000'), (10001, '10001')
    ) cases(sequence_value, expected)
  loop
    insert into number_test_results
    select 'padding ' || sample.sequence_value,
      lpad(sample.sequence_value::text,
        greatest(4, length(sample.sequence_value::text)), '0'),
      sample.expected,
      lpad(sample.sequence_value::text,
        greatest(4, length(sample.sequence_value::text)), '0') = sample.expected;
  end loop;

  if not exists (
    select 1 from pg_constraint c
    join pg_attribute a on a.attrelid = c.conrelid
      and a.attname = 'order_number'
    where c.conrelid = 'public.orders'::regclass
      and c.contype = 'u' and c.convalidated
      and c.conkey = array[a.attnum]
  ) then
    raise exception 'UNIQUE(order_number) is missing';
  end if;
  insert into number_test_results values
    ('UNIQUE(order_number)', 'present', 'present', true);

  select p.id, p.code into product_id, product_code
  from public.products p
  where p.active and p.available and p.eligible and not p.is_suggested_kit
  order by p.id limit 1;
  if product_id is null then raise exception 'No eligible test product'; end if;

  -- Exercise the actual RPC across the formerly truncating boundary.
  insert into public.daily_order_sequences(sequence_date, last_value)
  values (current_date, 9999)
  on conflict (sequence_date) do update set last_value = 9999;

  for attempt in 1..2 loop
    response := public.create_order_request_with_delivery(jsonb_build_object(
      'journeyId', replace(gen_random_uuid()::text, '-', ''),
      'customer', jsonb_build_object(
        'name', 'Validacion transaccional numeracion',
        'whatsapp', '573000000001',
        'acceptsDataProcessing', true, 'acceptsPromotions', false),
      'attribution', jsonb_build_object('source', 'validation_rollback'),
      'items', jsonb_build_array(jsonb_build_object(
        'productId', product_id, 'productCode', product_code,
        'itemType', 'primary', 'quantity', 1)),
      'requiresDelivery', false, 'deliveryMethod', 'advisorArrangement'));

    select order_number into persisted_number
    from public.orders where id = (response->>'order_id')::uuid;
    expected_number := 'OBM-' || to_char(current_date, 'YYMMDD') ||
      '-WEB-' || (9999 + attempt)::text;
    insert into number_test_results values
      ('real creation ' || attempt, response->>'order_number', expected_number,
        response->>'order_number' = expected_number),
      ('persisted equals returned ' || attempt, persisted_number,
        response->>'order_number', persisted_number = response->>'order_number');
    if attempt = 2 then
      insert into number_test_results values
        ('consecutive numbers distinct', persisted_number, previous_number,
          persisted_number <> previous_number);
      -- Confirm the unique constraint also rejects an actual duplicate.
      begin
        update public.orders set order_number = previous_number
        where id = (response->>'order_id')::uuid;
        raise exception 'Duplicate order number was accepted';
      exception when unique_violation then
        get stacked diagnostics unique_constraint_name = constraint_name;
        if unique_constraint_name <> 'orders_order_number_key' then
          raise exception 'Unexpected constraint: %', unique_constraint_name;
        end if;
        insert into number_test_results values
          ('duplicate rejected', unique_constraint_name,
            'orders_order_number_key', true);
      end;
    end if;
    previous_number := persisted_number;
  end loop;

  if exists (select 1 from number_test_results where passed is distinct from true) then
    raise exception 'Order number regression failed: %',
      (select jsonb_agg(to_jsonb(r)) from number_test_results r
       where passed is distinct from true);
  end if;
end $test$;

select * from number_test_results;
rollback;
