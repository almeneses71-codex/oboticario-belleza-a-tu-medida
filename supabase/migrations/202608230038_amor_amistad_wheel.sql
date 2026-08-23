begin;

insert into public.campaigns(code, display_name, starts_at, ends_at, active)
values (
  'AMOR_AMISTAD_2026',
  'Amor y Amistad 2026',
  '2026-09-01 00:00:00 America/Bogota'::timestamptz,
  '2026-09-20 00:00:00 America/Bogota'::timestamptz,
  true
)
on conflict (code) do update set
  display_name = excluded.display_name,
  starts_at = excluded.starts_at,
  ends_at = excluded.ends_at,
  active = excluded.active;

create table public.campaign_wheel_spins (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.campaigns(id),
  customer_id uuid not null references public.customers(id),
  whatsapp_reference text not null check (whatsapp_reference ~ '^573\d{9}$'),
  discount_percent smallint not null check (discount_percent in (5, 10, 15)),
  spun_at timestamptz not null default now(),
  initial_order_id uuid references public.orders(id),
  status text not null default 'awarded' check (status in ('awarded', 'applied')),
  audit jsonb not null default '{}'::jsonb,
  unique (customer_id, campaign_id),
  unique (whatsapp_reference, campaign_id)
);

alter table public.orders
  add column promotion_campaign_id uuid references public.campaigns(id),
  add column promotion_spin_id uuid unique references public.campaign_wheel_spins(id);

alter table public.campaign_wheel_spins enable row level security;
create policy "admins can view campaign wheel spins"
on public.campaign_wheel_spins for select to authenticated
using (public.is_admin());
grant select on public.campaign_wheel_spins to authenticated;

create or replace function public.round_cop_to_100(amount numeric)
returns integer
language sql
immutable
strict
set search_path = public, pg_temp
as $$
  select (floor((amount + 50) / 100) * 100)::integer;
$$;

create or replace function public.amor_amistad_2026_is_active(at_time timestamptz)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.campaigns
    where code = 'AMOR_AMISTAD_2026'
      and active
      and at_time >= starts_at
      and at_time < ends_at
  );
$$;

create or replace function public.get_amor_amistad_2026_status()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'code', 'AMOR_AMISTAD_2026',
    'active', public.amor_amistad_2026_is_active(now())
  );
$$;

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
  if length(trim(coalesce(payload->'customer'->>'name', ''))) < 2 then
    raise exception 'invalid_customer_name';
  end if;
  normalized_whatsapp := regexp_replace(
    coalesce(payload->'customer'->>'whatsapp', ''), '\D', '', 'g'
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

  for item in select value from jsonb_array_elements(payload->'items') loop
    item_quantity := coalesce((item->>'quantity')::integer, 0);
    if item_quantity < 1 or item_quantity > 20 then
      raise exception 'invalid_quantity';
    end if;
    select current_price_cop into product_price
    from public.products
    where (id = item->>'productId' or code = nullif(item->>'productCode', ''))
      and active and available and not is_suggested_kit
    order by (id = item->>'productId') desc
    limit 1;
    if product_price is null then raise exception 'product_unavailable'; end if;
    computed_products := computed_products + product_price * item_quantity;
  end loop;

  select * into target_campaign from public.campaigns
  where code = 'AMOR_AMISTAD_2026';
  insert into public.customers(name, whatsapp, city)
  values (
    trim(payload->'customer'->>'name'),
    normalized_whatsapp,
    nullif(trim(payload->'customer'->>'city'), '')
  )
  on conflict (whatsapp) do update set
    name = excluded.name,
    city = coalesce(excluded.city, customers.city),
    updated_at = now()
  returning id into target_customer_id;

  random_bucket := floor(random() * 100)::integer;
  insert into public.campaign_wheel_spins(
    campaign_id, customer_id, whatsapp_reference, discount_percent, audit
  ) values (
    target_campaign.id,
    target_customer_id,
    normalized_whatsapp,
    case when random_bucket < 60 then 5 when random_bucket < 90 then 10 else 15 end,
    jsonb_build_object('source', 'public_app', 'created_at', now())
  ) on conflict (customer_id, campaign_id) do nothing;

  select * into target_spin from public.campaign_wheel_spins
  where customer_id = target_customer_id and campaign_id = target_campaign.id;
  computed_net := public.round_cop_to_100(
    computed_products::numeric * (100 - target_spin.discount_percent) / 100
  );
  computed_net := greatest(0, least(computed_products, computed_net));
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
  select spin.* into target_spin
  from public.campaign_wheel_spins spin
  join public.campaigns campaign on campaign.id = spin.campaign_id
  where spin.customer_id = new.customer_id
    and campaign.code = 'AMOR_AMISTAD_2026'
    and public.amor_amistad_2026_is_active(now())
  limit 1;
  if target_spin.id is null then return new; end if;
  target_campaign_id := target_spin.campaign_id;
  computed_net := public.round_cop_to_100(
    new.subtotal_cop::numeric * (100 - target_spin.discount_percent) / 100
  );
  computed_net := greatest(0, least(new.subtotal_cop, computed_net));
  new.discount_cop := new.subtotal_cop - computed_net;
  new.promotion_campaign_id := target_campaign_id;
  new.promotion_spin_id := target_spin.id;
  return new;
end;
$$;

create trigger orders_apply_amor_amistad_discount
before insert on public.orders
for each row execute function public.apply_amor_amistad_discount();

create or replace function public.link_amor_amistad_spin_order()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.promotion_spin_id is not null then
    update public.campaign_wheel_spins
    set initial_order_id = coalesce(initial_order_id, new.id), status = 'applied'
    where id = new.promotion_spin_id;
  end if;
  return new;
end;
$$;

create trigger orders_link_amor_amistad_spin
after insert on public.orders
for each row execute function public.link_amor_amistad_spin_order();

create or replace function public.sync_order_commissions()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.status = 'paid' and old.status <> 'paid' and new.seller_id is not null then
    insert into public.order_item_commissions(
      order_id, order_item_id, seller_id, commission_rule_id,
      base_cop, rate_basis_points, status
    )
    select
      new.id, item.id, new.seller_id, resolved_rule.id,
      case when new.subtotal_cop = 0 then 0 else
        round(item.subtotal_cop::numeric *
          (new.subtotal_cop - new.discount_cop) / new.subtotal_cop)::integer
      end,
      resolved_rule.rate_basis_points, 'pending'
    from public.order_items item
    join lateral (
      select rule.id, rule.rate_basis_points
      from public.commission_rules rule
      where rule.active
        and rule.item_type = item.item_type
        and (rule.seller_id = new.seller_id or rule.seller_id is null)
        and (rule.starts_at is null or rule.starts_at <= now())
        and (rule.ends_at is null or rule.ends_at >= now())
      order by (rule.seller_id = new.seller_id) desc, rule.priority desc, rule.id
      limit 1
    ) resolved_rule on true
    where item.order_id = new.id
    on conflict (order_item_id) do nothing;
  elsif new.status = 'delivered' and old.status <> 'delivered' then
    update public.order_item_commissions set status = 'earned', updated_at = now()
    where order_id = new.id and status = 'pending';
  elsif new.status in ('returned', 'refunded', 'cancelled') and old.status <> new.status then
    update public.order_item_commissions set status = 'reversed', updated_at = now()
    where order_id = new.id and status <> 'reversed';
  end if;
  return new;
end;
$$;

revoke all on function public.get_amor_amistad_2026_status() from public;
revoke all on function public.spin_amor_amistad_2026(jsonb) from public;
grant execute on function public.get_amor_amistad_2026_status() to anon, authenticated;
grant execute on function public.spin_amor_amistad_2026(jsonb) to anon, authenticated;

comment on table public.campaign_wheel_spins is
  'One immutable Amor y Amistad award per normalized customer and campaign.';
comment on column public.orders.promotion_campaign_id is
  'Promotion campaign, separate from acquisition attribution campaign_id.';

commit;
