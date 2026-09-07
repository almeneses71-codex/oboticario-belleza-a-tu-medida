CREATE OR REPLACE FUNCTION public.create_order_request(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
 SET "TimeZone" TO 'America/Bogota'
AS $function$
declare
  new_customer_id uuid; new_order_id uuid; new_order_number text;
  resolved_seller_id uuid; resolved_channel_id uuid; resolved_campaign_id uuid;
  seller_code text; sequence_value integer; item jsonb;
  product_row public.products%rowtype;
  relation_row public.cross_sell_relations%rowtype;
  item_quantity integer; item_kind public.order_item_type;
  primary_id text; primary_count integer := 0;
  complementary_count integer := 0; other_count integer := 0;
  computed_subtotal integer := 0; seen_codes text[] := '{}';
begin
  if coalesce((payload->'customer'->>'acceptsDataProcessing')::boolean, false) is not true then
    raise exception 'data_processing_consent_required';
  end if;
  if coalesce(payload->>'journeyId', '') !~ '^[a-f0-9]{32}$' then
    raise exception 'invalid_journey_id';
  end if;
  if length(trim(payload->'customer'->>'name')) < 2 then
    raise exception 'invalid_customer_name';
  end if;
  if coalesce(payload->'customer'->>'whatsapp', '') !~ '^\d{10,15}$' then
    raise exception 'invalid_whatsapp';
  end if;
  if jsonb_array_length(coalesce(payload->'items', '[]'::jsonb)) = 0 then
    raise exception 'order_requires_items';
  end if;

  for item in select value from jsonb_array_elements(payload->'items') loop
    begin
      item_kind := (item->>'itemType')::public.order_item_type;
    exception when others then
      raise exception 'invalid_item_type';
    end;
    if item_kind = 'primary' then
      primary_count := primary_count + 1;
      primary_id := item->>'productId';
    elsif item_kind = 'complementary' then
      complementary_count := complementary_count + 1;
    elsif item_kind = 'other' then
      other_count := other_count + 1;
    else
      raise exception 'kits_not_enabled';
    end if;
  end loop;
  if primary_count <> 1 then raise exception 'exactly_one_primary_required'; end if;
  if complementary_count > 2 then raise exception 'too_many_complementaries'; end if;
  if other_count > 3 then raise exception 'too_many_other_products'; end if;

  select id, code into resolved_seller_id, seller_code
  from public.sellers
  where code = upper(payload->'attribution'->>'sellerId') and active;
  seller_code := coalesce(seller_code, 'WEB');
  select id into resolved_channel_id
  from public.channels
  where code = lower(payload->'attribution'->>'channelId') and active;
  select id into resolved_campaign_id
  from public.campaigns
  where code = payload->'attribution'->>'campaignId' and active;

  for item in select value from jsonb_array_elements(payload->'items') loop
    item_quantity := coalesce((item->>'quantity')::integer, 0);
    item_kind := (item->>'itemType')::public.order_item_type;
    if item_quantity < 1 or item_quantity > 20 then
      raise exception 'invalid_quantity';
    end if;
    select * into product_row
    from public.products
    where (
        id = item->>'productId'
        or code = nullif(item->>'productCode', '')
      )
      and active and available and not is_suggested_kit
      and (item_kind = 'other' or eligible)
    order by (id = item->>'productId') desc
    limit 1;
    if not found then raise exception 'product_unavailable'; end if;
    if product_row.code = any(seen_codes) then
      raise exception 'duplicate_order_product';
    end if;
    seen_codes := array_append(seen_codes, product_row.code);
    if item_kind = 'other' and lower(coalesce(product_row.subcategory, '')) = 'kit' then
      raise exception 'kits_not_enabled';
    end if;
    if item_kind = 'complementary' then
      select * into relation_row
      from public.cross_sell_relations
      where id = nullif(item->>'crossSellRelationId', '')
        and source_product_id = primary_id
        and complementary_product_id = product_row.id
        and active
        and (starts_at is null or starts_at <= now())
        and (ends_at is null or ends_at >= now());
      if not found then raise exception 'invalid_cross_sell_relation'; end if;
    end if;
    computed_subtotal :=
      computed_subtotal + product_row.current_price_cop * item_quantity;
  end loop;

  insert into public.customers(name, whatsapp, city) values (
    trim(payload->'customer'->>'name'),
    payload->'customer'->>'whatsapp',
    nullif(trim(payload->'customer'->>'city'), '')
  ) on conflict (whatsapp) do update set
    name = excluded.name,
    city = coalesce(excluded.city, customers.city),
    updated_at = now()
  returning id into new_customer_id;

  insert into public.customer_consents(customer_id, consent_type, granted) values
    (new_customer_id, 'data_processing', true),
    (new_customer_id, 'promotions',
      coalesce((payload->'customer'->>'acceptsPromotions')::boolean, false));

  insert into public.daily_order_sequences(sequence_date, last_value)
  values (current_date, 1)
  on conflict (sequence_date) do update
    set last_value = daily_order_sequences.last_value + 1
  returning last_value into sequence_value;
  new_order_number := format(
    'OBM-%s-%s-%s',
    to_char(current_date, 'YYMMDD'),
    seller_code,
    lpad(sequence_value::text, greatest(4, length(sequence_value::text)), '0')
  );

  insert into public.orders(
    order_number, customer_id, seller_id, channel_id, campaign_id, source,
    journey_id, primary_product_id, subtotal_cop, discount_cop, shipping_cop,
    shipping_estimate_min_cop, shipping_estimate_max_cop
  ) values (
    new_order_number, new_customer_id, resolved_seller_id, resolved_channel_id,
    resolved_campaign_id,
    coalesce(nullif(payload->'attribution'->>'source', ''), 'directo'),
    payload->>'journeyId', primary_id, computed_subtotal, 0, 0, 10000, 15000
  ) returning id into new_order_id;

  for item in select value from jsonb_array_elements(payload->'items') loop
    item_quantity := (item->>'quantity')::integer;
    item_kind := (item->>'itemType')::public.order_item_type;
    select * into product_row
    from public.products
    where id = item->>'productId'
       or code = nullif(item->>'productCode', '')
    order by (id = item->>'productId') desc
    limit 1;
    insert into public.order_items(
      order_id, product_id, product_code, product_name, quantity, item_type,
      original_unit_price_cop, discount_cop, final_unit_price_cop,
      cross_sell_relation_id
    ) values (
      new_order_id, product_row.id, product_row.code, product_row.name,
      item_quantity, item_kind, product_row.current_price_cop, 0,
      product_row.current_price_cop,
      case when item_kind = 'complementary'
        then nullif(item->>'crossSellRelationId', '') else null end
    );
  end loop;

  insert into public.order_status_history(order_id, status, note)
  values (
    new_order_id,
    'requested',
    'Solicitud creada desde la aplicación pública.'
  );
  return jsonb_build_object(
    'order_id', new_order_id,
    'order_number', new_order_number,
    'status', 'requested'
  );
end;
$function$
;
