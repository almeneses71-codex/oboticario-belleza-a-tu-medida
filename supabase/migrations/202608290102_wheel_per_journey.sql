alter table public.campaign_wheel_spins
  add column if not exists journey_id text;

alter table public.campaign_wheel_spins
  drop constraint if exists campaign_wheel_spins_journey_id_check;

alter table public.campaign_wheel_spins
  add constraint campaign_wheel_spins_journey_id_check
  check (journey_id is null or journey_id ~ '^[a-f0-9]{32}$');

-- Recuperar el journey de los giros históricos que ya tienen pedido asociado.
update public.campaign_wheel_spins spin
set journey_id = orders.journey_id
from public.orders orders
where orders.id = spin.initial_order_id
  and spin.journey_id is null
  and orders.journey_id is not null;

-- Ya no existe la regla "un giro por cliente durante toda la campaña".
alter table public.campaign_wheel_spins
  drop constraint if exists campaign_wheel_spins_customer_id_campaign_id_key;

alter table public.campaign_wheel_spins
  drop constraint if exists campaign_wheel_spins_whatsapp_reference_campaign_id_key;

alter table public.campaign_wheel_spins
  drop constraint if exists campaign_wheel_spins_campaign_id_journey_id_key;

alter table public.campaign_wheel_spins
  add constraint campaign_wheel_spins_campaign_id_journey_id_key
  unique (campaign_id, journey_id);


create or replace function public.spin_amor_amistad_2026(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  target_campaign public.campaigns%rowtype;
  target_customer_id uuid;
  target_spin public.campaign_wheel_spins%rowtype;
  normalized_whatsapp text;
  requested_journey text;
  item jsonb;
  item_quantity integer;
  product_price integer;
  computed_products integer := 0;
  computed_net integer;
  random_bucket integer;
begin
  if not public.amor_amistad_2026_is_active(now()) then
    raise exception 'wheel_campaign_unavailable';
  end if;

  requested_journey := coalesce(payload->>'journeyId', '');

  if requested_journey !~ '^[a-f0-9]{32}$' then
    raise exception 'invalid_journey_id';
  end if;

  if length(trim(coalesce(payload->'customer'->>'name', ''))) < 2 then
    raise exception 'invalid_customer_name';
  end if;

  normalized_whatsapp := regexp_replace(
    coalesce(payload->'customer'->>'whatsapp', ''),
    '\D',
    '',
    'g'
  );

  if normalized_whatsapp ~ '^3\d{9}$' then
    normalized_whatsapp := '57' || normalized_whatsapp;
  end if;

  if normalized_whatsapp !~ '^573\d{9}$' then
    raise exception 'invalid_whatsapp';
  end if;

  if jsonb_array_length(coalesce(payload->'items', '[]'::jsonb)) = 0 then
    raise exception 'wheel_requires_items';
  end if;

  for item in
    select value
    from jsonb_array_elements(payload->'items')
  loop
    item_quantity := coalesce((item->>'quantity')::integer, 0);

    if item_quantity < 1 or item_quantity > 20 then
      raise exception 'invalid_quantity';
    end if;

    select current_price_cop
    into product_price
    from public.products
    where (
      id = item->>'productId'
      or code = nullif(item->>'productCode', '')
    )
      and active
      and available
      and not is_suggested_kit
    order by (id = item->>'productId') desc
    limit 1;

    if product_price is null then
      raise exception 'product_unavailable';
    end if;

    computed_products :=
      computed_products + product_price * item_quantity;
  end loop;

  select *
  into target_campaign
  from public.campaigns
  where code = 'AMOR_AMISTAD_2026';

  insert into public.customers(name, whatsapp, city)
  values (
    trim(payload->'customer'->>'name'),
    normalized_whatsapp,
    nullif(trim(payload->'customer'->>'city'), '')
  )
  on conflict (whatsapp) do update
  set
    name = excluded.name,
    city = coalesce(excluded.city, customers.city),
    updated_at = now()
  returning id into target_customer_id;

  random_bucket := floor(random() * 100)::integer;

  insert into public.campaign_wheel_spins(
    campaign_id,
    customer_id,
    whatsapp_reference,
    journey_id,
    discount_percent,
    audit
  )
  values (
    target_campaign.id,
    target_customer_id,
    normalized_whatsapp,
    requested_journey,
    case
      when random_bucket < 60 then 5
      when random_bucket < 90 then 10
      else 15
    end,
    jsonb_build_object(
      'source', 'public_app',
      'created_at', now(),
      'journey_id', requested_journey
    )
  )
  on conflict (campaign_id, journey_id) do nothing;

  select *
  into target_spin
  from public.campaign_wheel_spins
  where campaign_id = target_campaign.id
    and journey_id = requested_journey;

  computed_net := public.round_cop_to_100(
    computed_products::numeric
    * (100 - target_spin.discount_percent)
    / 100
  );

  computed_net :=
    greatest(0, least(computed_products, computed_net));

  return jsonb_build_object(
    'spin_id', target_spin.id,
    'discount_percent', target_spin.discount_percent,
    'products_cop', computed_products,
    'discount_cop', computed_products - computed_net,
    'net_products_cop', computed_net,
    'recovered', target_spin.spun_at < statement_timestamp()
  );
end;
$$;


create or replace function public.apply_amor_amistad_discount()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  target_spin public.campaign_wheel_spins%rowtype;
  target_campaign_id uuid;
  computed_net integer;
begin
  select spin.*
  into target_spin
  from public.campaign_wheel_spins spin
  join public.campaigns campaign
    on campaign.id = spin.campaign_id
  where spin.journey_id = new.journey_id
    and spin.status = 'awarded'
    and campaign.code = 'AMOR_AMISTAD_2026'
    and public.amor_amistad_2026_is_active(now())
  limit 1;

  if target_spin.id is null then
    return new;
  end if;

  target_campaign_id := target_spin.campaign_id;

  computed_net := public.round_cop_to_100(
    new.subtotal_cop::numeric
    * (100 - target_spin.discount_percent)
    / 100
  );

  computed_net :=
    greatest(0, least(new.subtotal_cop, computed_net));

  new.discount_cop := new.subtotal_cop - computed_net;
  new.promotion_campaign_id := target_campaign_id;
  new.promotion_spin_id := target_spin.id;

  return new;
end;
$$;