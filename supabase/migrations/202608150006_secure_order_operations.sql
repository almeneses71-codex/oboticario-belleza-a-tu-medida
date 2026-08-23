create or replace function public.can_access_order(target_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.orders orders
    join public.staff_profiles staff
      on staff.user_id = (select auth.uid()) and staff.active
    where orders.id = target_order_id
      and (staff.role = 'admin' or staff.seller_id = orders.seller_id)
  );
$$;

revoke all on function public.can_access_order(uuid) from public;
grant execute on function public.can_access_order(uuid) to authenticated;

create or replace function public.update_order_status(
  target_order_id uuid,
  target_status public.order_status,
  change_note text default null
)
returns public.order_status
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  current_status public.order_status;
  transition_allowed boolean := false;
begin
  if not public.can_access_order(target_order_id) then
    raise exception 'order_access_denied';
  end if;

  select status into current_status
  from public.orders
  where id = target_order_id
  for update;
  if current_status is null then raise exception 'order_not_found'; end if;

  transition_allowed := case current_status
    when 'requested' then target_status in ('contacted', 'cancelled')
    when 'contacted' then target_status in ('availability_verified', 'cancelled')
    when 'availability_verified' then target_status in ('confirmed', 'cancelled')
    when 'confirmed' then target_status in ('pending_payment', 'cancelled')
    when 'pending_payment' then target_status in ('payment_under_review', 'cancelled')
    when 'payment_under_review' then target_status in ('paid', 'cancelled')
    when 'paid' then target_status in ('preparing', 'refunded')
    when 'preparing' then target_status in ('shipped', 'refunded')
    when 'shipped' then target_status in ('delivered', 'returned')
    when 'delivered' then target_status = 'returned'
    when 'returned' then target_status = 'refunded'
    else false
  end;
  if not transition_allowed then raise exception 'invalid_order_transition'; end if;

  update public.orders
  set status = target_status, updated_at = now()
  where id = target_order_id;

  insert into public.order_status_history(order_id, status, changed_by, note)
  values (
    target_order_id,
    target_status,
    (select auth.uid()),
    nullif(left(trim(change_note), 500), '')
  );
  return target_status;
end;
$$;

revoke all on function public.update_order_status(
  uuid, public.order_status, text
) from public;
grant execute on function public.update_order_status(
  uuid, public.order_status, text
) to authenticated;

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
  current_status public.order_status;
begin
  if not public.can_access_order(target_order_id) then
    raise exception 'order_access_denied';
  end if;
  if confirmed_shipping_cop < 0 or confirmed_shipping_cop > 100000 then
    raise exception 'invalid_shipping_amount';
  end if;

  select status into current_status
  from public.orders
  where id = target_order_id
  for update;
  if current_status is null then raise exception 'order_not_found'; end if;
  if current_status not in (
    'requested', 'contacted', 'availability_verified', 'confirmed'
  ) then
    raise exception 'shipping_can_no_longer_change';
  end if;

  update public.orders
  set shipping_cop = confirmed_shipping_cop,
      shipping_status = case
        when confirmed_shipping_cop = 0 then 'not_required'::public.shipping_status
        else 'manually_confirmed'::public.shipping_status
      end,
      updated_at = now()
  where id = target_order_id;
  return confirmed_shipping_cop;
end;
$$;

revoke all on function public.confirm_order_shipping(uuid, integer) from public;
grant execute on function public.confirm_order_shipping(uuid, integer)
  to authenticated;
