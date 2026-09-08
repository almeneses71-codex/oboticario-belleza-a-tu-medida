begin;

create type public.pilot_funnel_event_type as enum (
  'app_open',
  'diagnosis_started',
  'diagnosis_completed',
  'recommendation_viewed',
  'product_selected',
  'request_started'
);

create table public.pilot_funnel_events (
  id uuid primary key default gen_random_uuid(),
  journey_id text not null check (journey_id ~ '^[a-f0-9]{32}$'),
  event_type public.pilot_funnel_event_type not null,
  seller_id uuid references public.sellers(id),
  channel_id uuid references public.channels(id),
  campaign_id uuid references public.campaigns(id),
  source text not null default 'directo'
    check (source ~ '^[a-z0-9_-]{1,50}$'),
  product_id text references public.products(id),
  product_code text references public.products(code),
  created_at timestamptz not null default now(),
  check ((product_id is null) = (product_code is null)),
  check (
    event_type not in ('recommendation_viewed', 'product_selected', 'request_started')
    or product_id is not null
  )
);

create index pilot_funnel_events_created_idx
  on public.pilot_funnel_events(created_at desc);
create index pilot_funnel_events_attribution_idx
  on public.pilot_funnel_events(seller_id, channel_id, campaign_id, created_at desc);
create unique index pilot_funnel_events_unique_milestone_idx
  on public.pilot_funnel_events(journey_id, event_type)
  where event_type <> 'product_selected';
create unique index pilot_funnel_events_unique_product_selection_idx
  on public.pilot_funnel_events(journey_id, event_type, product_id)
  where event_type = 'product_selected';

alter table public.pilot_funnel_events enable row level security;
revoke all on table public.pilot_funnel_events from public, anon, authenticated;

create or replace function public.record_pilot_funnel_event(payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  requested_journey text := payload->>'journeyId';
  requested_event public.pilot_funnel_event_type;
  requested_seller_code text := upper(nullif(trim(payload->'attribution'->>'sellerId'), ''));
  requested_channel_code text := lower(nullif(trim(payload->'attribution'->>'channelId'), ''));
  requested_campaign_code text := upper(nullif(trim(payload->'attribution'->>'campaignId'), ''));
  requested_source text := lower(coalesce(nullif(trim(payload->'attribution'->>'source'), ''), 'directo'));
  requested_product_id text := nullif(trim(payload->>'productId'), '');
  requested_product_code text := nullif(trim(payload->>'productCode'), '');
  resolved_seller_id uuid;
  resolved_channel_id uuid;
  resolved_campaign_id uuid;
  resolved_product_id text;
  resolved_product_code text;
  inserted_id uuid;
begin
  if payload is null or jsonb_typeof(payload) <> 'object' then
    raise exception 'invalid_funnel_payload';
  end if;
  if payload ?| array['name', 'whatsapp', 'address', 'customer', 'answers', 'deliveryDetails'] then
    raise exception 'personal_data_not_allowed';
  end if;
  if coalesce(requested_journey, '') !~ '^[a-f0-9]{32}$' then
    raise exception 'invalid_journey_id';
  end if;
  begin
    requested_event := (payload->>'eventType')::public.pilot_funnel_event_type;
  exception when others then
    raise exception 'invalid_funnel_event';
  end;
  if requested_source !~ '^[a-z0-9_-]{1,50}$' then
    raise exception 'invalid_source';
  end if;

  if requested_seller_code is not null then
    if requested_seller_code not in ('DAR', 'ANA') then
      raise exception 'invalid_pilot_seller';
    end if;
    select seller.id into resolved_seller_id
    from public.sellers seller
    where seller.code = requested_seller_code and seller.active;
    if resolved_seller_id is null then raise exception 'inactive_pilot_seller'; end if;
  end if;

  if requested_channel_code is not null then
    if requested_channel_code <> 'whatsapp' then raise exception 'invalid_pilot_channel'; end if;
    select channel.id into resolved_channel_id
    from public.channels channel
    where channel.code = requested_channel_code and channel.active;
    if resolved_channel_id is null then raise exception 'inactive_pilot_channel'; end if;
  end if;

  if requested_campaign_code is not null then
    if requested_campaign_code <> 'AMOR_AMISTAD_2026' then
      raise exception 'invalid_pilot_campaign';
    end if;
    select campaign.id into resolved_campaign_id
    from public.campaigns campaign
    where campaign.code = requested_campaign_code and campaign.active;
    if resolved_campaign_id is null then raise exception 'inactive_pilot_campaign'; end if;
  end if;

  if requested_product_id is not null or requested_product_code is not null then
    select product.id, product.code
      into resolved_product_id, resolved_product_code
    from public.products product
    where (requested_product_id is null or product.id = requested_product_id)
      and (requested_product_code is null or product.code = requested_product_code)
      and product.active
    limit 1;
    if resolved_product_id is null then raise exception 'invalid_funnel_product'; end if;
  end if;

  if requested_event in ('recommendation_viewed', 'product_selected', 'request_started')
      and resolved_product_id is null then
    raise exception 'funnel_product_required';
  end if;

  insert into public.pilot_funnel_events(
    journey_id, event_type, seller_id, channel_id, campaign_id, source,
    product_id, product_code
  ) values (
    requested_journey, requested_event, resolved_seller_id, resolved_channel_id,
    resolved_campaign_id, requested_source, resolved_product_id, resolved_product_code
  )
  on conflict do nothing
  returning id into inserted_id;

  if inserted_id is null then
    select event.id into inserted_id
    from public.pilot_funnel_events event
    where event.journey_id = requested_journey
      and event.event_type = requested_event
      and (
        requested_event <> 'product_selected'
        or event.product_id = resolved_product_id
      )
    limit 1;
  end if;
  return inserted_id;
end;
$$;

revoke all on function public.record_pilot_funnel_event(jsonb) from public;
grant execute on function public.record_pilot_funnel_event(jsonb) to anon, authenticated;

commit;
