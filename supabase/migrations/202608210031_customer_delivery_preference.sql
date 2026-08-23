begin;

create table public.order_customer_delivery_preferences (
  order_id uuid primary key references public.orders(id) on delete cascade,
  requires_delivery boolean not null,
  created_at timestamptz not null default now()
);

alter table public.order_customer_delivery_preferences enable row level security;

create policy "staff can view permitted delivery preferences"
on public.order_customer_delivery_preferences for select to authenticated
using (public.can_access_order(order_id));

grant select on public.order_customer_delivery_preferences to authenticated;

create or replace function public.create_order_request_with_delivery(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  created_order jsonb;
  requested_delivery boolean;
begin
  if jsonb_typeof(payload->'requiresDelivery') <> 'boolean' then
    raise exception 'delivery_preference_required';
  end if;

  requested_delivery := (payload->>'requiresDelivery')::boolean;
  created_order := public.create_order_request(payload);

  insert into public.order_customer_delivery_preferences(
    order_id,
    requires_delivery
  ) values (
    (created_order->>'order_id')::uuid,
    requested_delivery
  );

  return created_order;
end;
$$;

revoke all on function public.create_order_request_with_delivery(jsonb)
from public, authenticated;
grant execute on function public.create_order_request_with_delivery(jsonb)
to anon;

comment on table public.order_customer_delivery_preferences is
  'Customer delivery preference captured at request time. It does not confirm shipping cost or fulfillment.';

commit;
