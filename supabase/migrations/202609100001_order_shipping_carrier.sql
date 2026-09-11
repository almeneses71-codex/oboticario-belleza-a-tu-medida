begin;

alter table public.orders
  add column if not exists shipping_carrier text;

create or replace function public.confirm_order_shipping(
  target_order_id uuid,
  confirmed_shipping_cop integer,
  shipping_carrier_name text
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
  normalized_carrier text;
begin
  select * into actor from public.staff_profiles
  where user_id = (select auth.uid()) and active;
  if actor.user_id is null or not public.can_access_order(target_order_id) then
    raise exception 'order_access_denied';
  end if;

  normalized_carrier := trim(coalesce(shipping_carrier_name, ''));
  if length(normalized_carrier) < 2 or length(normalized_carrier) > 120 then
    raise exception 'invalid_shipping_carrier';
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
      shipping_carrier = normalized_carrier,
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

revoke all on function public.confirm_order_shipping(uuid, integer, text)
from public;
grant execute on function public.confirm_order_shipping(uuid, integer, text)
to authenticated;

commit;
