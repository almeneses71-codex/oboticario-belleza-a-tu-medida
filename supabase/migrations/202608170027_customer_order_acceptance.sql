create type public.customer_acceptance_channel as enum ('whatsapp', 'phone');

create table public.customer_order_acceptances (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  channel public.customer_acceptance_channel not null,
  order_snapshot jsonb not null,
  accepted_total_cop integer not null check (accepted_total_cop >= 0),
  note text not null check (length(trim(note)) between 5 and 500),
  recorded_by uuid not null references auth.users(id),
  recorder_role public.staff_role not null,
  recorder_display_name text not null,
  accepted_at timestamptz not null default now()
);

create index customer_order_acceptances_order_idx
  on public.customer_order_acceptances(order_id, accepted_at desc);

alter table public.customer_order_acceptances enable row level security;
create policy "staff can view permitted customer acceptances"
on public.customer_order_acceptances for select to authenticated
using (public.can_access_order(order_id));
grant select on public.customer_order_acceptances to authenticated;

create or replace function public.record_customer_order_acceptance(
  target_order_id uuid,
  acceptance_channel text,
  acceptance_note text
)
returns uuid language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  actor public.staff_profiles%rowtype;
  target_order public.orders%rowtype;
  normalized_note text := nullif(left(trim(acceptance_note), 500), '');
  snapshot jsonb;
  new_id uuid;
begin
  select * into actor from public.staff_profiles
  where user_id = (select auth.uid()) and active;
  if actor.user_id is null or not public.can_access_order(target_order_id) then
    raise exception 'customer_acceptance_permission_denied';
  end if;

  select * into target_order from public.orders
  where id = target_order_id for update;
  if target_order.status <> 'availability_verified' then
    raise exception 'customer_acceptance_status_not_allowed';
  end if;
  if target_order.shipping_status = 'pending_quote' then
    raise exception 'customer_acceptance_shipping_required';
  end if;
  if not public.order_has_verified_availability(target_order_id) then
    raise exception 'customer_acceptance_availability_required';
  end if;
  if acceptance_channel not in ('whatsapp', 'phone') then
    raise exception 'customer_acceptance_channel_invalid';
  end if;
  if normalized_note is null or length(normalized_note) < 5 then
    raise exception 'customer_acceptance_note_required';
  end if;

  select jsonb_build_object(
    'subtotalCop', target_order.subtotal_cop,
    'discountCop', target_order.discount_cop,
    'shippingCop', target_order.shipping_cop,
    'totalCop', target_order.total_cop,
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'orderItemId', item.id,
      'productCode', item.product_code,
      'productName', item.product_name,
      'quantity', item.quantity,
      'unitPriceCop', item.final_unit_price_cop
    ) order by item.id), '[]'::jsonb)
  ) into snapshot
  from public.order_items item where item.order_id = target_order_id;

  insert into public.customer_order_acceptances(
    order_id, channel, order_snapshot, accepted_total_cop, note,
    recorded_by, recorder_role, recorder_display_name
  ) values (
    target_order_id, acceptance_channel::public.customer_acceptance_channel,
    snapshot, target_order.total_cop, normalized_note, (select auth.uid()),
    actor.role, actor.display_name
  ) returning id into new_id;
  return new_id;
end;
$$;

revoke all on function public.record_customer_order_acceptance(uuid, text, text)
  from public;
grant execute on function public.record_customer_order_acceptance(uuid, text, text)
  to authenticated;

create or replace function public.order_has_current_customer_acceptance(
  target_order_id uuid
)
returns boolean language sql stable security definer
set search_path = public, pg_temp as $$
  select exists (
    select 1 from public.customer_order_acceptances acceptance
    join public.orders target on target.id = acceptance.order_id
    where acceptance.order_id = target_order_id
      and acceptance.accepted_total_cop = target.total_cop
  );
$$;
revoke all on function public.order_has_current_customer_acceptance(uuid)
  from public;

create or replace function public.guard_customer_acceptance_before_confirmation()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $$
begin
  if new.status = 'confirmed' and old.status is distinct from new.status
     and not public.order_has_current_customer_acceptance(new.id) then
    raise exception 'current_customer_acceptance_required';
  end if;
  return new;
end;
$$;

create trigger orders_require_customer_acceptance
before update of status on public.orders
for each row execute function public.guard_customer_acceptance_before_confirmation();

comment on table public.customer_order_acceptances is
  'Audited customer acceptance of the commercial order and totals. '
  'This is not payment verification and does not authorize a store purchase.';
