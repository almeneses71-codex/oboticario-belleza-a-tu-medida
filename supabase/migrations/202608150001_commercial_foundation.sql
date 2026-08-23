create extension if not exists pgcrypto;

create type public.staff_role as enum ('seller', 'admin');
create type public.order_status as enum (
  'requested', 'contacted', 'availability_verified', 'confirmed',
  'pending_payment', 'payment_under_review', 'paid', 'preparing',
  'shipped', 'delivered', 'cancelled', 'returned', 'refunded'
);
create type public.shipping_status as enum (
  'pending_quote', 'manually_confirmed', 'promotional', 'not_required'
);

create table public.sellers (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z0-9]{2,12}$'),
  display_name text not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.channels (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  display_name text not null,
  active boolean not null default true
);

create table public.campaigns (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  display_name text not null,
  starts_at timestamptz,
  ends_at timestamptz,
  active boolean not null default true
);

create table public.staff_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role public.staff_role not null,
  seller_id uuid references public.sellers(id),
  display_name text not null,
  active boolean not null default true,
  check (role = 'admin' or seller_id is not null)
);

create table public.products (
  id text primary key,
  code text not null unique,
  name text not null,
  current_price_cop integer not null check (current_price_cop >= 0),
  available boolean not null default true,
  active boolean not null default true,
  updated_at timestamptz not null default now()
);

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  whatsapp text not null unique check (whatsapp ~ '^\d{10,15}$'),
  city text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.customer_consents (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id) on delete cascade,
  consent_type text not null check (consent_type in ('data_processing', 'promotions')),
  granted boolean not null,
  recorded_at timestamptz not null default now()
);

create table public.daily_order_sequences (
  sequence_date date primary key,
  last_value integer not null check (last_value > 0)
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  order_number text not null unique,
  customer_id uuid not null references public.customers(id),
  seller_id uuid references public.sellers(id),
  channel_id uuid references public.channels(id),
  campaign_id uuid references public.campaigns(id),
  source text not null default 'directo',
  status public.order_status not null default 'requested',
  shipping_status public.shipping_status not null default 'pending_quote',
  subtotal_cop integer not null check (subtotal_cop >= 0),
  discount_cop integer not null default 0 check (discount_cop >= 0),
  shipping_cop integer not null default 0 check (shipping_cop >= 0),
  total_cop integer generated always as
    (subtotal_cop - discount_cop + shipping_cop) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (discount_cop <= subtotal_cop)
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id text not null references public.products(id),
  product_code text not null,
  product_name text not null,
  quantity integer not null check (quantity > 0),
  unit_price_cop integer not null check (unit_price_cop >= 0),
  subtotal_cop integer generated always as (quantity * unit_price_cop) stored
);

create table public.order_status_history (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  status public.order_status not null,
  changed_by uuid references auth.users(id),
  note text,
  created_at timestamptz not null default now()
);

create index orders_seller_id_idx on public.orders(seller_id);
create index orders_customer_id_idx on public.orders(customer_id);
create index orders_created_at_idx on public.orders(created_at desc);
create index order_items_order_id_idx on public.order_items(order_id);
create index order_history_order_id_idx on public.order_status_history(order_id);

alter table public.sellers enable row level security;
alter table public.channels enable row level security;
alter table public.campaigns enable row level security;
alter table public.staff_profiles enable row level security;
alter table public.products enable row level security;
alter table public.customers enable row level security;
alter table public.customer_consents enable row level security;
alter table public.daily_order_sequences enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.order_status_history enable row level security;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.staff_profiles
    where user_id = (select auth.uid()) and role = 'admin' and active
  );
$$;

create policy "staff can view permitted orders"
on public.orders for select to authenticated
using (
  public.is_admin() or seller_id = (
    select seller_id from public.staff_profiles
    where user_id = (select auth.uid()) and active
  )
);

create policy "staff can view related customers"
on public.customers for select to authenticated
using (
  public.is_admin() or exists (
    select 1 from public.orders o
    join public.staff_profiles sp on sp.seller_id = o.seller_id
    where o.customer_id = customers.id
      and sp.user_id = (select auth.uid()) and sp.active
  )
);

create policy "staff can view permitted order items"
on public.order_items for select to authenticated
using (exists (select 1 from public.orders o where o.id = order_items.order_id));

create policy "staff can view permitted history"
on public.order_status_history for select to authenticated
using (exists (select 1 from public.orders o where o.id = order_status_history.order_id));

create policy "active products are public"
on public.products for select to anon, authenticated
using (active);

create policy "staff can view related consents"
on public.customer_consents for select to authenticated
using (
  public.is_admin() or exists (
    select 1 from public.orders orders
    join public.staff_profiles staff on staff.seller_id = orders.seller_id
    where orders.customer_id = customer_consents.customer_id
      and staff.user_id = (select auth.uid()) and staff.active
  )
);

grant select on public.products to anon, authenticated;
grant select on public.orders, public.order_items,
  public.order_status_history, public.customers, public.customer_consents
  to authenticated;

create or replace function public.create_order_request(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  new_customer_id uuid;
  new_order_id uuid;
  new_order_number text;
  resolved_seller_id uuid;
  resolved_channel_id uuid;
  resolved_campaign_id uuid;
  seller_code text;
  sequence_value integer;
  item jsonb;
  product_row public.products%rowtype;
  item_quantity integer;
  computed_subtotal integer := 0;
begin
  if coalesce((payload->'customer'->>'acceptsDataProcessing')::boolean, false) is not true then
    raise exception 'data_processing_consent_required';
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

  select id, code into resolved_seller_id, seller_code
  from public.sellers
  where code = upper(payload->'attribution'->>'sellerId') and active;
  seller_code := coalesce(seller_code, 'WEB');

  select id into resolved_channel_id from public.channels
  where code = lower(payload->'attribution'->>'channelId') and active;
  select id into resolved_campaign_id from public.campaigns
  where code = payload->'attribution'->>'campaignId' and active;

  for item in select value from jsonb_array_elements(payload->'items') loop
    item_quantity := coalesce((item->>'quantity')::integer, 0);
    if item_quantity < 1 or item_quantity > 20 then
      raise exception 'invalid_quantity';
    end if;
    select * into product_row from public.products
    where id = item->>'productId' and active and available;
    if not found then raise exception 'product_unavailable'; end if;
    computed_subtotal := computed_subtotal + product_row.current_price_cop * item_quantity;
  end loop;

  insert into public.customers(name, whatsapp, city)
  values (
    trim(payload->'customer'->>'name'),
    payload->'customer'->>'whatsapp',
    nullif(trim(payload->'customer'->>'city'), '')
  )
  on conflict (whatsapp) do update set
    name = excluded.name, city = coalesce(excluded.city, customers.city), updated_at = now()
  returning id into new_customer_id;

  insert into public.customer_consents(customer_id, consent_type, granted)
  values
    (new_customer_id, 'data_processing', true),
    (new_customer_id, 'promotions', coalesce((payload->'customer'->>'acceptsPromotions')::boolean, false));

  insert into public.daily_order_sequences(sequence_date, last_value)
  values (current_date, 1)
  on conflict (sequence_date) do update
    set last_value = daily_order_sequences.last_value + 1
  returning last_value into sequence_value;

  new_order_number := format(
    'OBM-%s-%s-%s', to_char(current_date, 'YYMMDD'), seller_code,
    lpad(sequence_value::text, 4, '0')
  );

  insert into public.orders(
    order_number, customer_id, seller_id, channel_id, campaign_id, source,
    subtotal_cop, discount_cop, shipping_cop
  ) values (
    new_order_number, new_customer_id, resolved_seller_id, resolved_channel_id,
    resolved_campaign_id,
    coalesce(nullif(payload->'attribution'->>'source', ''), 'directo'),
    computed_subtotal, 0, 0
  ) returning id into new_order_id;

  for item in select value from jsonb_array_elements(payload->'items') loop
    select * into product_row from public.products where id = item->>'productId';
    item_quantity := (item->>'quantity')::integer;
    insert into public.order_items(
      order_id, product_id, product_code, product_name, quantity, unit_price_cop
    ) values (
      new_order_id, product_row.id, product_row.code, product_row.name,
      item_quantity, product_row.current_price_cop
    );
  end loop;

  insert into public.order_status_history(order_id, status, note)
  values (new_order_id, 'requested', 'Solicitud creada desde la aplicación pública.');

  return jsonb_build_object(
    'order_id', new_order_id,
    'order_number', new_order_number,
    'status', 'requested'
  );
end;
$$;

revoke all on function public.create_order_request(jsonb) from public;
grant execute on function public.create_order_request(jsonb) to anon, authenticated;

insert into public.channels(code, display_name) values
  ('directo', 'Acceso directo'),
  ('whatsapp', 'WhatsApp'),
  ('estado', 'Estado de WhatsApp'),
  ('facebook', 'Facebook'),
  ('instagram', 'Instagram'),
  ('tiktok', 'TikTok'),
  ('qr', 'Código QR')
on conflict (code) do nothing;
