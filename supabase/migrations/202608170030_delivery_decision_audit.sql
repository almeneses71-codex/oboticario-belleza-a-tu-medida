create table public.order_delivery_events (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  previous_shipping_status public.shipping_status not null,
  previous_shipping_cop integer not null check (previous_shipping_cop >= 0),
  shipping_status public.shipping_status not null,
  shipping_cop integer not null check (shipping_cop >= 0),
  actor_user_id uuid not null references auth.users(id),
  actor_role public.staff_role not null,
  actor_display_name text not null,
  created_at timestamptz not null default now()
);

create index order_delivery_events_order_idx
  on public.order_delivery_events(order_id, created_at desc);

alter table public.order_delivery_events enable row level security;
create policy "staff can view permitted delivery events"
on public.order_delivery_events for select to authenticated
using (public.can_access_order(order_id));
grant select on public.order_delivery_events to authenticated;

create or replace function public.confirm_order_shipping(
  target_order_id uuid,
  confirmed_shipping_cop integer
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  actor public.staff_profiles%rowtype;
  target_order public.orders%rowtype;
  resolved_status public.shipping_status;
begin
  select * into actor from public.staff_profiles
  where user_id = (select auth.uid()) and active;
  if actor.user_id is null or not public.can_access_order(target_order_id) then
    raise exception 'order_access_denied';
  end if;
  if confirmed_shipping_cop < 0 or confirmed_shipping_cop > 100000 then
    raise exception 'invalid_shipping_amount';
  end if;

  select * into target_order from public.orders
  where id = target_order_id for update;
  if target_order.id is null then raise exception 'order_not_found'; end if;
  if target_order.status not in (
    'requested', 'contacted', 'availability_verified', 'confirmed'
  ) then raise exception 'shipping_can_no_longer_change'; end if;

  resolved_status := case
    when confirmed_shipping_cop = 0 then 'not_required'::public.shipping_status
    else 'manually_confirmed'::public.shipping_status
  end;

  update public.orders
  set shipping_cop = confirmed_shipping_cop,
      shipping_status = resolved_status,
      updated_at = now()
  where id = target_order_id;

  insert into public.order_delivery_events(
    order_id, previous_shipping_status, previous_shipping_cop,
    shipping_status, shipping_cop, actor_user_id, actor_role,
    actor_display_name
  ) values (
    target_order_id, target_order.shipping_status, target_order.shipping_cop,
    resolved_status, confirmed_shipping_cop, (select auth.uid()), actor.role,
    actor.display_name
  );

  return confirmed_shipping_cop;
end;
$$;

revoke all on function public.confirm_order_shipping(uuid, integer) from public;
grant execute on function public.confirm_order_shipping(uuid, integer)
  to authenticated;
