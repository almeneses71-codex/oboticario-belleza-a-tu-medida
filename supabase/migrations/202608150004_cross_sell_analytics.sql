create type public.commercial_event_name as enum (
  'cross_sell_shown', 'complementary_added', 'complementary_removed'
);

create table public.commercial_events (
  id uuid primary key default gen_random_uuid(),
  journey_id text not null check (journey_id ~ '^[a-f0-9]{32}$'),
  event_name public.commercial_event_name not null,
  primary_product_id text not null references public.products(id),
  complementary_product_id text not null references public.products(id),
  cross_sell_relation_id text not null references public.cross_sell_relations(id),
  seller_id uuid references public.sellers(id),
  channel_id uuid references public.channels(id),
  campaign_id uuid references public.campaigns(id),
  source text not null default 'directo',
  created_at timestamptz not null default now()
);

create index commercial_events_created_idx
  on public.commercial_events(created_at desc);
create index commercial_events_relation_idx
  on public.commercial_events(cross_sell_relation_id, event_name, journey_id);
create index commercial_events_attribution_idx
  on public.commercial_events(seller_id, channel_id, campaign_id);
create unique index commercial_events_one_show_per_journey_relation
  on public.commercial_events(journey_id, cross_sell_relation_id)
  where event_name = 'cross_sell_shown';

alter table public.commercial_events enable row level security;
create policy "staff can view permitted commercial events"
on public.commercial_events for select to authenticated
using (
  public.is_admin() or seller_id = (
    select seller_id from public.staff_profiles
    where user_id = (select auth.uid()) and active
  )
);
grant select on public.commercial_events to authenticated;

create or replace function public.record_commercial_event(payload jsonb)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  requested_event public.commercial_event_name;
  requested_journey text := payload->>'journeyId';
  requested_primary text := payload->>'primaryProductId';
  requested_complementary text := payload->>'complementaryProductId';
  requested_relation text := payload->>'relationId';
  resolved_seller_id uuid;
  resolved_channel_id uuid;
  resolved_campaign_id uuid;
begin
  if coalesce(requested_journey, '') !~ '^[a-f0-9]{32}$' then
    raise exception 'invalid_journey_id';
  end if;
  begin
    requested_event := (payload->>'eventName')::public.commercial_event_name;
  exception when others then
    raise exception 'invalid_commercial_event';
  end;

  if not exists (
    select 1 from public.cross_sell_relations relation
    join public.products primary_product
      on primary_product.id = relation.source_product_id
    join public.products complementary_product
      on complementary_product.id = relation.complementary_product_id
    where relation.id = requested_relation
      and relation.source_product_id = requested_primary
      and relation.complementary_product_id = requested_complementary
      and relation.active
      and (relation.starts_at is null or relation.starts_at <= now())
      and (relation.ends_at is null or relation.ends_at >= now())
      and primary_product.active and primary_product.available
      and primary_product.eligible and not primary_product.is_suggested_kit
      and complementary_product.active and complementary_product.available
      and complementary_product.eligible and not complementary_product.is_suggested_kit
  ) then
    raise exception 'invalid_cross_sell_relation';
  end if;

  select id into resolved_seller_id from public.sellers
    where code = upper(payload->'attribution'->>'sellerId') and active;
  select id into resolved_channel_id from public.channels
    where code = lower(payload->'attribution'->>'channelId') and active;
  select id into resolved_campaign_id from public.campaigns
    where code = payload->'attribution'->>'campaignId' and active
      and (starts_at is null or starts_at <= now())
      and (ends_at is null or ends_at >= now());

  insert into public.commercial_events(
    journey_id, event_name, primary_product_id, complementary_product_id,
    cross_sell_relation_id, seller_id, channel_id, campaign_id, source
  ) values (
    requested_journey, requested_event, requested_primary, requested_complementary,
    requested_relation, resolved_seller_id, resolved_channel_id,
    resolved_campaign_id,
    coalesce(nullif(lower(payload->'attribution'->>'source'), ''), 'directo')
  );
end;
$$;

revoke all on function public.record_commercial_event(jsonb) from public;
grant execute on function public.record_commercial_event(jsonb)
  to anon, authenticated;

create view public.commercial_order_metrics
with (security_invoker = true)
as
select
  orders.id as order_id,
  orders.order_number,
  orders.journey_id,
  orders.created_at,
  orders.status,
  orders.seller_id,
  orders.channel_id,
  orders.campaign_id,
  orders.primary_product_id,
  coalesce(sum(items.subtotal_cop), 0)::bigint as product_revenue_cop,
  (orders.subtotal_cop - orders.discount_cop)::bigint as net_product_revenue_cop,
  coalesce(sum(items.subtotal_cop) filter (
    where items.item_type = 'complementary'
  ), 0)::bigint as complementary_revenue_cop,
  count(*) filter (
    where items.item_type = 'complementary'
  )::integer as complementary_item_count,
  orders.shipping_cop
from public.orders
join public.order_items items on items.order_id = orders.id
group by orders.id;

revoke all on public.commercial_order_metrics from public;
grant select on public.commercial_order_metrics to authenticated;

create view public.cross_sell_event_metrics
with (security_invoker = true)
as
select
  cross_sell_relation_id,
  primary_product_id,
  complementary_product_id,
  seller_id,
  channel_id,
  campaign_id,
  count(distinct journey_id) filter (
    where event_name = 'cross_sell_shown'
  )::integer as journeys_shown,
  count(distinct journey_id) filter (
    where event_name = 'complementary_added'
  )::integer as journeys_with_add,
  count(distinct journey_id) filter (
    where event_name = 'complementary_removed'
  )::integer as journeys_with_remove
from public.commercial_events
group by
  cross_sell_relation_id, primary_product_id, complementary_product_id,
  seller_id, channel_id, campaign_id;

revoke all on public.cross_sell_event_metrics from public;
grant select on public.cross_sell_event_metrics to authenticated;
