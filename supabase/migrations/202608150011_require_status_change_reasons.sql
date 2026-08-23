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
  current_shipping_status public.shipping_status;
  normalized_note text := nullif(left(trim(change_note), 500), '');
  transition_allowed boolean := false;
begin
  if not public.can_access_order(target_order_id) then
    raise exception 'order_access_denied';
  end if;

  select status, shipping_status
  into current_status, current_shipping_status
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
  if target_status = 'confirmed' and current_shipping_status = 'pending_quote' then
    raise exception 'shipping_confirmation_required';
  end if;
  if target_status in ('cancelled', 'returned', 'refunded')
      and (normalized_note is null or length(normalized_note) < 5) then
    raise exception 'status_change_reason_required';
  end if;

  update public.orders
  set status = target_status, updated_at = now()
  where id = target_order_id;

  insert into public.order_status_history(order_id, status, changed_by, note)
  values (target_order_id, target_status, (select auth.uid()), normalized_note);
  return target_status;
end;
$$;

revoke all on function public.update_order_status(
  uuid, public.order_status, text
) from public;
grant execute on function public.update_order_status(
  uuid, public.order_status, text
) to authenticated;
