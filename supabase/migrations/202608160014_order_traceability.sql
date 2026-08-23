alter table public.order_status_history
  add column previous_status public.order_status,
  add column actor_role public.staff_role,
  add column actor_display_name text;

with ordered as (
  select id, lag(status) over (partition by order_id order by created_at, id) as previous_status
  from public.order_status_history
)
update public.order_status_history history
set previous_status = ordered.previous_status
from ordered where ordered.id = history.id;

update public.order_status_history history
set actor_role = staff.role,
    actor_display_name = staff.display_name
from public.staff_profiles staff
where staff.user_id = history.changed_by;

create or replace function public.can_view_all_orders()
returns boolean language sql stable security definer
set search_path = public, pg_temp as $$
  select exists (
    select 1 from public.staff_profiles
    where user_id = (select auth.uid()) and active
      and role in ('admin', 'owner', 'manager')
  );
$$;
revoke all on function public.can_view_all_orders() from public;
grant execute on function public.can_view_all_orders() to authenticated;

drop policy "staff can view permitted orders" on public.orders;
create policy "staff can view permitted orders" on public.orders
for select to authenticated using (
  public.can_view_all_orders() or seller_id = (
    select seller_id from public.staff_profiles
    where user_id = (select auth.uid()) and active
  )
);

drop policy "staff can view related customers" on public.customers;
create policy "staff can view related customers" on public.customers
for select to authenticated using (
  public.can_view_all_orders() or exists (
    select 1 from public.orders orders
    join public.staff_profiles staff on staff.seller_id = orders.seller_id
    where orders.customer_id = customers.id
      and staff.user_id = (select auth.uid()) and staff.active
  )
);

drop policy "staff can view related consents" on public.customer_consents;
create policy "staff can view related consents" on public.customer_consents
for select to authenticated using (
  public.can_view_all_orders() or exists (
    select 1 from public.orders orders
    join public.staff_profiles staff on staff.seller_id = orders.seller_id
    where orders.customer_id = customer_consents.customer_id
      and staff.user_id = (select auth.uid()) and staff.active
  )
);

drop policy "staff can view permitted commercial events" on public.commercial_events;
create policy "staff can view permitted commercial events" on public.commercial_events
for select to authenticated using (
  public.can_view_all_orders() or seller_id = (
    select seller_id from public.staff_profiles
    where user_id = (select auth.uid()) and active
  )
);

drop policy "staff can view permitted commissions" on public.order_item_commissions;
create policy "staff can view permitted commissions" on public.order_item_commissions
for select to authenticated using (
  public.can_view_all_orders() or seller_id = (
    select seller_id from public.staff_profiles
    where user_id = (select auth.uid()) and active
  )
);

create or replace function public.can_access_order(target_order_id uuid)
returns boolean language sql stable security definer
set search_path = public, pg_temp as $$
  select exists (
    select 1 from public.orders orders
    join public.staff_profiles staff
      on staff.user_id = (select auth.uid()) and staff.active
    where orders.id = target_order_id
      and (staff.role in ('admin', 'owner', 'manager') or staff.seller_id = orders.seller_id)
  );
$$;
revoke all on function public.can_access_order(uuid) from public;
grant execute on function public.can_access_order(uuid) to authenticated;

drop policy "staff can view own profile and admins can view all" on public.staff_profiles;
create policy "staff can view own profile and leadership can view all"
on public.staff_profiles for select to authenticated
using (user_id = (select auth.uid()) or public.can_view_all_orders());

create or replace function public.update_order_status(
  target_order_id uuid,
  target_status public.order_status,
  change_note text default null
)
returns public.order_status language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  current_status public.order_status;
  current_shipping_status public.shipping_status;
  normalized_note text := nullif(left(trim(change_note), 500), '');
  actor public.staff_profiles%rowtype;
  transition_allowed boolean := false;
begin
  if not public.can_access_order(target_order_id) then raise exception 'order_access_denied'; end if;
  select * into actor from public.staff_profiles
    where user_id = (select auth.uid()) and active;
  select status, shipping_status into current_status, current_shipping_status
    from public.orders where id = target_order_id for update;
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
    else false end;
  if not transition_allowed then raise exception 'invalid_order_transition'; end if;
  if target_status = 'confirmed' and current_shipping_status = 'pending_quote' then
    raise exception 'shipping_confirmation_required';
  end if;
  if target_status in ('cancelled', 'returned', 'refunded')
      and (normalized_note is null or length(normalized_note) < 5) then
    raise exception 'status_change_reason_required';
  end if;
  update public.orders set status = target_status, updated_at = now()
    where id = target_order_id;
  insert into public.order_status_history(
    order_id, previous_status, status, changed_by, actor_role,
    actor_display_name, note
  ) values (
    target_order_id, current_status, target_status, (select auth.uid()),
    actor.role, actor.display_name, normalized_note
  );
  return target_status;
end;
$$;
revoke all on function public.update_order_status(uuid, public.order_status, text) from public;
grant execute on function public.update_order_status(uuid, public.order_status, text) to authenticated;
