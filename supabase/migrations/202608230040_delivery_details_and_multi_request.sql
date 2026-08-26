begin;

alter table public.order_customer_delivery_preferences
  add column if not exists delivery_method text,
  add column if not exists city text,
  add column if not exists address text,
  add column if not exists neighborhood text,
  add column if not exists recipient_name text,
  add column if not exists directions text;

update public.order_customer_delivery_preferences
set delivery_method = case
  when requires_delivery then 'home_delivery'
  else 'advisor_arrangement'
end
where delivery_method is null;

alter table public.order_customer_delivery_preferences
  alter column delivery_method set not null,
  add constraint order_delivery_method_valid check (
    delivery_method in ('home_delivery', 'advisor_arrangement')
  );

create or replace function public.create_order_request_with_delivery(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  created_order jsonb;
  requested_delivery boolean;
  requested_method text;
  details jsonb;
begin
  if jsonb_typeof(payload->'requiresDelivery') <> 'boolean' then
    raise exception 'delivery_preference_required';
  end if;

  requested_delivery := (payload->>'requiresDelivery')::boolean;
  requested_method := case payload->>'deliveryMethod'
    when 'homeDelivery' then 'home_delivery'
    when 'advisorArrangement' then 'advisor_arrangement'
    else null
  end;
  if requested_method is null
     or requested_delivery <> (requested_method = 'home_delivery') then
    raise exception 'invalid_delivery_method';
  end if;

  details := payload->'deliveryDetails';
  if requested_delivery and (
    jsonb_typeof(details) <> 'object'
    or length(trim(coalesce(details->>'city', ''))) = 0
    or length(trim(coalesce(details->>'address', ''))) = 0
    or length(trim(coalesce(details->>'neighborhood', ''))) = 0
    or length(trim(coalesce(details->>'recipientName', ''))) = 0
  ) then
    raise exception 'delivery_details_required';
  end if;

  created_order := public.create_order_request(payload);

  insert into public.order_customer_delivery_preferences(
    order_id, requires_delivery, delivery_method, city, address,
    neighborhood, recipient_name, directions
  ) values (
    (created_order->>'order_id')::uuid,
    requested_delivery,
    requested_method,
    case when requested_delivery then trim(details->>'city') end,
    case when requested_delivery then trim(details->>'address') end,
    case when requested_delivery then trim(details->>'neighborhood') end,
    case when requested_delivery then trim(details->>'recipientName') end,
    case when requested_delivery then nullif(trim(details->>'directions'), '') end
  );

  return created_order;
end;
$$;

revoke all on function public.create_order_request_with_delivery(jsonb)
from public, authenticated;
grant execute on function public.create_order_request_with_delivery(jsonb)
to anon;

commit;
