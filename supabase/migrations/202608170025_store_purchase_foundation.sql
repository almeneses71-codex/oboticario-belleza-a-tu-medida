create type public.store_purchase_status as enum (
  'awaiting_payment_verification',
  'ready_to_purchase',
  'purchased',
  'cancelled'
);

create table public.store_purchases (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.orders(id) on delete restrict,
  status public.store_purchase_status not null
    default 'awaiting_payment_verification',
  external_reference text,
  purchased_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (status = 'purchased' and purchased_at is not null)
    or (status <> 'purchased' and purchased_at is null)
  )
);

create table public.store_purchase_events (
  id uuid primary key default gen_random_uuid(),
  store_purchase_id uuid not null references public.store_purchases(id)
    on delete cascade,
  status public.store_purchase_status not null,
  actor_user_id uuid references auth.users(id),
  actor_role public.staff_role,
  actor_display_name text,
  note text,
  created_at timestamptz not null default now()
);

create index store_purchase_events_purchase_idx
  on public.store_purchase_events(store_purchase_id, created_at);

alter table public.store_purchases enable row level security;
alter table public.store_purchase_events enable row level security;

create policy "staff can view permitted store purchases"
on public.store_purchases for select to authenticated
using (public.can_access_order(order_id));

create policy "staff can view permitted store purchase events"
on public.store_purchase_events for select to authenticated
using (
  exists (
    select 1 from public.store_purchases purchase
    where purchase.id = store_purchase_id
      and public.can_access_order(purchase.order_id)
  )
);

grant select on public.store_purchases to authenticated;
grant select on public.store_purchase_events to authenticated;

create or replace function public.create_store_purchase_after_confirmation()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  purchase_id uuid;
  actor public.staff_profiles%rowtype;
begin
  if new.status = 'confirmed' and old.status is distinct from new.status then
    insert into public.store_purchases(order_id)
    values (new.id)
    on conflict (order_id) do update set updated_at = excluded.updated_at
    returning id into purchase_id;

    select * into actor from public.staff_profiles
    where user_id = (select auth.uid()) and active;

    if not exists (
      select 1 from public.store_purchase_events event
      where event.store_purchase_id = purchase_id
        and event.status = 'awaiting_payment_verification'
    ) then
      insert into public.store_purchase_events(
        store_purchase_id, status, actor_user_id, actor_role,
        actor_display_name, note
      ) values (
        purchase_id, 'awaiting_payment_verification', (select auth.uid()),
        actor.role, actor.display_name,
        'Compra a tienda bloqueada hasta verificar el pago del cliente.'
      );
    end if;
  end if;
  return new;
end;
$$;

create trigger orders_create_store_purchase
after update of status on public.orders
for each row execute function public.create_store_purchase_after_confirmation();

insert into public.store_purchases(order_id)
select id from public.orders where status in (
  'confirmed', 'pending_payment', 'payment_under_review', 'paid',
  'preparing', 'shipped', 'delivered', 'returned', 'refunded'
)
on conflict (order_id) do nothing;

insert into public.store_purchase_events(store_purchase_id, status, note)
select purchase.id, purchase.status,
  'Registro inicial creado al separar el pedido del cliente de la compra a tienda.'
from public.store_purchases purchase
where not exists (
  select 1 from public.store_purchase_events event
  where event.store_purchase_id = purchase.id
);

comment on table public.store_purchases is
  'Purchase from the external store, separate from the customer order. '
  'No payment credentials or customer banking secrets may be stored here.';

comment on column public.store_purchases.status is
  'Initially locked awaiting customer payment verification. No mutation RPC is enabled in this phase.';
