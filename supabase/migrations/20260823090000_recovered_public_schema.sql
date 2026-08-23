--
-- PostgreSQL database dump
--

\restrict EdQNURiObA2qEt5cVuZZIx4qgqde2rzAJRNmtWYODxIdUxPtlj5Q0kF8ulkwrCG

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: availability_result; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.availability_result AS ENUM (
    'available',
    'partial',
    'unavailable'
);


--
-- Name: commercial_event_name; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.commercial_event_name AS ENUM (
    'cross_sell_shown',
    'complementary_added',
    'complementary_removed'
);


--
-- Name: commission_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.commission_status AS ENUM (
    'pending',
    'earned',
    'reversed'
);


--
-- Name: customer_acceptance_channel; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.customer_acceptance_channel AS ENUM (
    'whatsapp',
    'phone'
);


--
-- Name: followup_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.followup_status AS ENUM (
    'open',
    'completed',
    'cancelled'
);


--
-- Name: order_item_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.order_item_type AS ENUM (
    'primary',
    'complementary',
    'kit',
    'other'
);


--
-- Name: order_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.order_status AS ENUM (
    'requested',
    'contacted',
    'availability_verified',
    'confirmed',
    'pending_payment',
    'payment_under_review',
    'paid',
    'preparing',
    'shipped',
    'delivered',
    'cancelled',
    'returned',
    'refunded'
);


--
-- Name: shipping_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.shipping_status AS ENUM (
    'pending_quote',
    'manually_confirmed',
    'promotional',
    'not_required'
);


--
-- Name: staff_role; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.staff_role AS ENUM (
    'seller',
    'admin',
    'owner',
    'manager'
);


--
-- Name: store_purchase_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.store_purchase_status AS ENUM (
    'awaiting_payment_verification',
    'ready_to_purchase',
    'purchased',
    'cancelled'
);


--
-- Name: admin_upsert_commission_rule(uuid, text, public.order_item_type, integer, smallint, boolean, timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_upsert_commission_rule(target_rule_id uuid, target_seller_code text, target_item_type public.order_item_type, target_rate_basis_points integer, target_priority smallint, target_active boolean, target_starts_at timestamp with time zone DEFAULT NULL::timestamp with time zone, target_ends_at timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare
  resolved_id uuid := coalesce(target_rule_id, gen_random_uuid());
  resolved_seller_id uuid;
begin
  if not public.is_admin() then raise exception 'admin_required'; end if;
  if target_rate_basis_points < 0 or target_rate_basis_points > 10000 then
    raise exception 'invalid_commission_rate';
  end if;
  if target_priority < 1 or target_priority > 100 then
    raise exception 'invalid_commission_priority';
  end if;
  if target_ends_at is not null and target_starts_at is not null
      and target_ends_at < target_starts_at then
    raise exception 'invalid_commission_dates';
  end if;
  if nullif(upper(trim(target_seller_code)), '') is not null then
    select id into resolved_seller_id from public.sellers
      where code = upper(trim(target_seller_code)) and active;
    if resolved_seller_id is null then raise exception 'seller_not_found'; end if;
  end if;

  insert into public.commission_rules(
    id, seller_id, item_type, rate_basis_points, priority,
    active, starts_at, ends_at
  ) values (
    resolved_id, resolved_seller_id, target_item_type,
    target_rate_basis_points, target_priority, target_active,
    target_starts_at, target_ends_at
  )
  on conflict (id) do update set
    seller_id = excluded.seller_id,
    item_type = excluded.item_type,
    rate_basis_points = excluded.rate_basis_points,
    priority = excluded.priority,
    active = excluded.active,
    starts_at = excluded.starts_at,
    ends_at = excluded.ends_at,
    updated_at = now();
  return resolved_id;
end;
$$;


--
-- Name: admin_upsert_staff_member(uuid, public.staff_role, text, text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_upsert_staff_member(target_user_id uuid, target_role public.staff_role, target_seller_code text, target_display_name text, target_active boolean DEFAULT true) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare
  resolved_seller_id uuid;
begin
  if not public.is_admin() then raise exception 'admin_required'; end if;
  if not exists (select 1 from auth.users where id = target_user_id) then
    raise exception 'auth_user_not_found';
  end if;
  if length(trim(target_display_name)) < 2 then
    raise exception 'invalid_display_name';
  end if;

  if target_role <> 'admin' then
    select id into resolved_seller_id
    from public.sellers
    where code = upper(trim(target_seller_code)) and active;
    if resolved_seller_id is null then raise exception 'seller_not_found'; end if;
  end if;

  insert into public.staff_profiles(
    user_id, role, seller_id, display_name, active
  ) values (
    target_user_id, target_role, resolved_seller_id,
    trim(target_display_name), target_active
  )
  on conflict (user_id) do update set
    role = excluded.role,
    seller_id = excluded.seller_id,
    display_name = excluded.display_name,
    active = excluded.active;
end;
$$;


--
-- Name: assign_order_responsible(uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assign_order_responsible(target_order_id uuid, target_seller_id uuid, assignment_reason text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare
  actor public.staff_profiles%rowtype;
  current_seller_id uuid;
  current_seller_name text;
  target_seller_name text;
  normalized_reason text := nullif(left(trim(assignment_reason), 500), '');
begin
  select * into actor from public.staff_profiles
  where user_id = (select auth.uid()) and active;
  if actor.role not in ('admin', 'owner', 'manager') then
    raise exception 'assignment_permission_denied';
  end if;
  if normalized_reason is null or length(normalized_reason) < 5 then
    raise exception 'assignment_reason_required';
  end if;
  select o.assigned_seller_id, s.display_name
    into current_seller_id, current_seller_name
  from public.orders o
  join public.sellers s on s.id = o.assigned_seller_id
  where o.id = target_order_id for update of o;
  if current_seller_id is null then raise exception 'order_not_found'; end if;
  select s.display_name into target_seller_name
  from public.sellers s
  where s.id = target_seller_id and s.active
    and exists (
      select 1 from public.staff_profiles sp
      where sp.seller_id = s.id and sp.active
    );
  if target_seller_name is null then raise exception 'seller_not_assignable'; end if;
  if current_seller_id = target_seller_id then
    raise exception 'seller_already_assigned';
  end if;
  update public.orders
  set assigned_seller_id = target_seller_id, updated_at = now()
  where id = target_order_id;
  insert into public.order_assignment_history(
    order_id, previous_seller_id, new_seller_id,
    previous_seller_name, new_seller_name,
    changed_by, actor_role, actor_display_name, reason
  ) values (
    target_order_id, current_seller_id, target_seller_id,
    current_seller_name, target_seller_name,
    (select auth.uid()), actor.role, actor.display_name, normalized_reason
  );
  return target_seller_id;
end;
$$;


--
-- Name: bootstrap_first_admin(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.bootstrap_first_admin(target_user_id uuid, target_display_name text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
begin
  if exists (select 1 from public.staff_profiles where role = 'admin') then
    raise exception 'admin_already_exists';
  end if;
  if not exists (select 1 from auth.users where id = target_user_id) then
    raise exception 'auth_user_not_found';
  end if;
  if length(trim(target_display_name)) < 2 then
    raise exception 'invalid_display_name';
  end if;

  insert into public.staff_profiles(user_id, role, display_name, active)
  values (target_user_id, 'admin', trim(target_display_name), true);
end;
$$;


--
-- Name: can_access_order(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_access_order(target_order_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  select exists (
    select 1 from public.orders orders
    join public.staff_profiles staff
      on staff.user_id = (select auth.uid()) and staff.active
    where orders.id = target_order_id
      and (
        staff.role in ('admin', 'owner', 'manager')
        or staff.seller_id = orders.assigned_seller_id
      )
  );
$$;


--
-- Name: can_view_all_orders(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_view_all_orders() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  select exists (
    select 1 from public.staff_profiles
    where user_id = (select auth.uid()) and active
      and role in ('admin', 'owner', 'manager')
  );
$$;


--
-- Name: complete_order_followup(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.complete_order_followup(target_followup_id uuid, result_note text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare
  actor public.staff_profiles%rowtype;
  target_order_id uuid;
  target_status public.followup_status;
  normalized_note text := nullif(left(trim(result_note), 500), '');
begin
  select * into actor from public.staff_profiles
  where user_id = (select auth.uid()) and active;
  select order_id, status into target_order_id, target_status
  from public.order_followups where id = target_followup_id for update;
  if actor.user_id is null or target_order_id is null
    or not public.can_access_order(target_order_id) then
    raise exception 'followup_permission_denied';
  end if;
  if target_status <> 'open' then raise exception 'followup_not_open'; end if;
  if normalized_note is null or length(normalized_note) < 5 then
    raise exception 'followup_result_required';
  end if;
  update public.order_followups set
    status = 'completed', completed_by = (select auth.uid()),
    completed_by_name = actor.display_name, completed_at = now(),
    completion_note = normalized_note
  where id = target_followup_id;
  return target_followup_id;
end;
$$;


--
-- Name: confirm_order_shipping(uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.confirm_order_shipping(target_order_id uuid, confirmed_shipping_cop integer) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
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


--
-- Name: create_order_followup(uuid, text, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_order_followup(target_order_id uuid, followup_note text, followup_due_at timestamp with time zone) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare
  actor public.staff_profiles%rowtype;
  normalized_note text := nullif(left(trim(followup_note), 500), '');
  new_id uuid;
begin
  select * into actor from public.staff_profiles
  where user_id = (select auth.uid()) and active;
  if actor.user_id is null or not public.can_access_order(target_order_id) then
    raise exception 'followup_permission_denied';
  end if;
  if normalized_note is null or length(normalized_note) < 5 then
    raise exception 'followup_note_required';
  end if;
  if followup_due_at is null then raise exception 'followup_due_at_required'; end if;
  insert into public.order_followups(
    order_id, note, due_at, created_by, creator_role, creator_display_name
  ) values (
    target_order_id, normalized_note, followup_due_at,
    (select auth.uid()), actor.role, actor.display_name
  ) returning id into new_id;
  return new_id;
end;
$$;


--
-- Name: create_order_request(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_order_request(payload jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    SET "TimeZone" TO 'America/Bogota'
    AS $_$
declare
  new_customer_id uuid; new_order_id uuid; new_order_number text;
  resolved_seller_id uuid; resolved_channel_id uuid; resolved_campaign_id uuid;
  seller_code text; sequence_value integer; item jsonb;
  product_row public.products%rowtype;
  relation_row public.cross_sell_relations%rowtype;
  item_quantity integer; item_kind public.order_item_type;
  primary_id text; primary_count integer := 0;
  complementary_count integer := 0; other_count integer := 0;
  computed_subtotal integer := 0; seen_codes text[] := '{}';
begin
  if coalesce((payload->'customer'->>'acceptsDataProcessing')::boolean, false) is not true then
    raise exception 'data_processing_consent_required';
  end if;
  if coalesce(payload->>'journeyId', '') !~ '^[a-f0-9]{32}$' then
    raise exception 'invalid_journey_id';
  end if;
  if length(trim(payload->'customer'->>'name')) < 2 then
    raise exception 'invalid_customer_name';
  end if;
  if coalesce(payload->'customer'->>'whatsapp', '') !~ '^\d{10,15}$' then
    raise exception 'invalid_whatsapp';
  end if;
  if jsonb_array_length(coalesce(payload->'items', '[]'::jsonb)) = 0 then
    raise exception 'order_requires_items';
  end if;

  for item in select value from jsonb_array_elements(payload->'items') loop
    begin
      item_kind := (item->>'itemType')::public.order_item_type;
    exception when others then
      raise exception 'invalid_item_type';
    end;
    if item_kind = 'primary' then
      primary_count := primary_count + 1;
      primary_id := item->>'productId';
    elsif item_kind = 'complementary' then
      complementary_count := complementary_count + 1;
    elsif item_kind = 'other' then
      other_count := other_count + 1;
    else
      raise exception 'kits_not_enabled';
    end if;
  end loop;
  if primary_count <> 1 then raise exception 'exactly_one_primary_required'; end if;
  if complementary_count > 2 then raise exception 'too_many_complementaries'; end if;
  if other_count > 3 then raise exception 'too_many_other_products'; end if;

  select id, code into resolved_seller_id, seller_code
  from public.sellers
  where code = upper(payload->'attribution'->>'sellerId') and active;
  seller_code := coalesce(seller_code, 'WEB');
  select id into resolved_channel_id
  from public.channels
  where code = lower(payload->'attribution'->>'channelId') and active;
  select id into resolved_campaign_id
  from public.campaigns
  where code = payload->'attribution'->>'campaignId' and active;

  for item in select value from jsonb_array_elements(payload->'items') loop
    item_quantity := coalesce((item->>'quantity')::integer, 0);
    item_kind := (item->>'itemType')::public.order_item_type;
    if item_quantity < 1 or item_quantity > 20 then
      raise exception 'invalid_quantity';
    end if;
    select * into product_row
    from public.products
    where (
        id = item->>'productId'
        or code = nullif(item->>'productCode', '')
      )
      and active and available and not is_suggested_kit
      and (item_kind = 'other' or eligible)
    order by (id = item->>'productId') desc
    limit 1;
    if not found then raise exception 'product_unavailable'; end if;
    if product_row.code = any(seen_codes) then
      raise exception 'duplicate_order_product';
    end if;
    seen_codes := array_append(seen_codes, product_row.code);
    if item_kind = 'other' and lower(coalesce(product_row.subcategory, '')) = 'kit' then
      raise exception 'kits_not_enabled';
    end if;
    if item_kind = 'complementary' then
      select * into relation_row
      from public.cross_sell_relations
      where id = nullif(item->>'crossSellRelationId', '')
        and source_product_id = primary_id
        and complementary_product_id = product_row.id
        and active
        and (starts_at is null or starts_at <= now())
        and (ends_at is null or ends_at >= now());
      if not found then raise exception 'invalid_cross_sell_relation'; end if;
    end if;
    computed_subtotal :=
      computed_subtotal + product_row.current_price_cop * item_quantity;
  end loop;

  insert into public.customers(name, whatsapp, city) values (
    trim(payload->'customer'->>'name'),
    payload->'customer'->>'whatsapp',
    nullif(trim(payload->'customer'->>'city'), '')
  ) on conflict (whatsapp) do update set
    name = excluded.name,
    city = coalesce(excluded.city, customers.city),
    updated_at = now()
  returning id into new_customer_id;

  insert into public.customer_consents(customer_id, consent_type, granted) values
    (new_customer_id, 'data_processing', true),
    (new_customer_id, 'promotions',
      coalesce((payload->'customer'->>'acceptsPromotions')::boolean, false));

  insert into public.daily_order_sequences(sequence_date, last_value)
  values (current_date, 1)
  on conflict (sequence_date) do update
    set last_value = daily_order_sequences.last_value + 1
  returning last_value into sequence_value;
  new_order_number := format(
    'OBM-%s-%s-%s',
    to_char(current_date, 'YYMMDD'),
    seller_code,
    lpad(sequence_value::text, 4, '0')
  );

  insert into public.orders(
    order_number, customer_id, seller_id, channel_id, campaign_id, source,
    journey_id, primary_product_id, subtotal_cop, discount_cop, shipping_cop,
    shipping_estimate_min_cop, shipping_estimate_max_cop
  ) values (
    new_order_number, new_customer_id, resolved_seller_id, resolved_channel_id,
    resolved_campaign_id,
    coalesce(nullif(payload->'attribution'->>'source', ''), 'directo'),
    payload->>'journeyId', primary_id, computed_subtotal, 0, 0, 10000, 15000
  ) returning id into new_order_id;

  for item in select value from jsonb_array_elements(payload->'items') loop
    item_quantity := (item->>'quantity')::integer;
    item_kind := (item->>'itemType')::public.order_item_type;
    select * into product_row
    from public.products
    where id = item->>'productId'
       or code = nullif(item->>'productCode', '')
    order by (id = item->>'productId') desc
    limit 1;
    insert into public.order_items(
      order_id, product_id, product_code, product_name, quantity, item_type,
      original_unit_price_cop, discount_cop, final_unit_price_cop,
      cross_sell_relation_id
    ) values (
      new_order_id, product_row.id, product_row.code, product_row.name,
      item_quantity, item_kind, product_row.current_price_cop, 0,
      product_row.current_price_cop,
      case when item_kind = 'complementary'
        then nullif(item->>'crossSellRelationId', '') else null end
    );
  end loop;

  insert into public.order_status_history(order_id, status, note)
  values (
    new_order_id,
    'requested',
    'Solicitud creada desde la aplicación pública.'
  );
  return jsonb_build_object(
    'order_id', new_order_id,
    'order_number', new_order_number,
    'status', 'requested'
  );
end;
$_$;


--
-- Name: create_order_request_with_delivery(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_order_request_with_delivery(payload jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
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


--
-- Name: create_store_purchase_after_confirmation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_store_purchase_after_confirmation() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare
  purchase_id uuid;
  actor public.staff_profiles%rowtype;
begin
  if new.status = 'confirmed' and old.status is distinct from new.status then
    insert into public.store_purchases(order_id)
    values (new.id)
    on conflict (order_id) do update set updated_at = excluded.updated_at
    returning id into purchase_id;

    select * into actor from public.staff_profiles
    where user_id = (select auth.uid()) and active;

    if not exists (
      select 1 from public.store_purchase_events event
      where event.store_purchase_id = purchase_id
        and event.status = 'awaiting_payment_verification'
    ) then
      insert into public.store_purchase_events(
        store_purchase_id, status, actor_user_id, actor_role,
        actor_display_name, note
      ) values (
        purchase_id, 'awaiting_payment_verification', (select auth.uid()),
        actor.role, actor.display_name,
        'Compra a tienda bloqueada hasta verificar el pago del cliente.'
      );
    end if;
  end if;
  return new;
end;
$$;


--
-- Name: feature_enabled(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.feature_enabled(feature_key text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  select coalesce(
    (select enabled from public.feature_flags where key = feature_key),
    false
  );
$$;


--
-- Name: guard_customer_acceptance_before_confirmation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.guard_customer_acceptance_before_confirmation() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
begin
  if new.status = 'confirmed' and old.status is distinct from new.status
     and not public.order_has_current_customer_acceptance(new.id) then
    raise exception 'current_customer_acceptance_required';
  end if;
  return new;
end;
$$;


--
-- Name: guard_disabled_order_features(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.guard_disabled_order_features() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
begin
  if new.status is distinct from old.status
     and new.status in ('pending_payment', 'payment_under_review', 'paid')
     and not public.feature_enabled('payments') then
    raise exception 'payments_feature_disabled';
  end if;
  return new;
end;
$$;


--
-- Name: FUNCTION guard_disabled_order_features(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.guard_disabled_order_features() IS 'Blocks payment lifecycle states until payments are enabled by a reviewed migration.';


--
-- Name: guard_verified_availability_transition(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.guard_verified_availability_transition() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
begin
  if new.status = 'availability_verified'
     and old.status is distinct from new.status
     and not public.order_has_verified_availability(new.id) then
    raise exception 'availability_verification_required';
  end if;
  return new;
end;
$$;


--
-- Name: is_admin(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_admin() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  select exists (
    select 1 from public.staff_profiles
    where user_id = (select auth.uid()) and role = 'admin' and active
  );
$$;


--
-- Name: list_assignable_sellers(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.list_assignable_sellers() RETURNS TABLE(id uuid, code text, display_name text)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
begin
  if not public.can_view_all_orders() then
    raise exception 'assignment_permission_denied';
  end if;
  return query
  select distinct s.id, s.code, s.display_name
  from public.sellers s
  join public.staff_profiles sp on sp.seller_id = s.id and sp.active
  where s.active
  order by s.display_name;
end;
$$;


--
-- Name: log_initial_order_assignment(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.log_initial_order_assignment() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
begin
  insert into public.order_assignment_history(
    order_id, new_seller_id, new_seller_name, reason
  )
  select new.id, new.assigned_seller_id, s.display_name,
    'Asignación inicial del pedido.'
  from public.sellers s where s.id = new.assigned_seller_id;
  return new;
end;
$$;


--
-- Name: log_order_contact(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.log_order_contact(target_order_id uuid, contact_channel text DEFAULT 'whatsapp'::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare
  actor public.staff_profiles%rowtype;
  new_id uuid;
begin
  select * into actor from public.staff_profiles
  where user_id = (select auth.uid()) and active;

  if actor.user_id is null or not public.can_access_order(target_order_id) then
    raise exception 'contact_permission_denied';
  end if;
  if contact_channel <> 'whatsapp' then
    raise exception 'contact_channel_not_allowed';
  end if;

  insert into public.order_contact_events(
    order_id, channel, actor_user_id, actor_role, actor_display_name
  ) values (
    target_order_id, contact_channel, (select auth.uid()),
    actor.role, actor.display_name
  ) returning id into new_id;

  return new_id;
end;
$$;


--
-- Name: normalize_customer_colombian_mobile(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.normalize_customer_colombian_mobile() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $_$
declare
  digits text;
begin
  digits := regexp_replace(coalesce(new.whatsapp, ''), '[^0-9]', '', 'g');
  if digits ~ '^3[0-9]{9}$' then
    digits := '57' || digits;
  end if;
  if digits !~ '^573[0-9]{9}$' then
    raise exception 'invalid_colombian_mobile';
  end if;
  new.whatsapp := digits;
  return new;
end;
$_$;


--
-- Name: order_has_current_customer_acceptance(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.order_has_current_customer_acceptance(target_order_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  select exists (
    select 1 from public.customer_order_acceptances acceptance
    join public.orders target on target.id = acceptance.order_id
    where acceptance.order_id = target_order_id
      and acceptance.accepted_total_cop = target.total_cop
  );
$$;


--
-- Name: order_has_verified_availability(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.order_has_verified_availability(target_order_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  with latest as (
    select distinct on (check_row.order_item_id)
      check_row.order_item_id, check_row.result
    from public.order_item_availability_checks check_row
    where check_row.order_id = target_order_id
    order by check_row.order_item_id, check_row.checked_at desc
  )
  select count(*) = (select count(*) from public.order_items where order_id = target_order_id)
    and count(*) > 0
    and bool_and(result = 'available')
  from latest;
$$;


--
-- Name: record_commercial_event(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.record_commercial_event(payload jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $_$
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
$_$;


--
-- Name: record_customer_order_acceptance(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.record_customer_order_acceptance(target_order_id uuid, acceptance_channel text, acceptance_note text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
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


--
-- Name: search_staff_order_ids(text, public.order_status, text, timestamp with time zone, text, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.search_staff_order_ids(search_text text DEFAULT NULL::text, filter_status public.order_status DEFAULT NULL::public.order_status, filter_seller_name text DEFAULT NULL::text, created_after timestamp with time zone DEFAULT NULL::timestamp with time zone, filter_attention text DEFAULT NULL::text, page_offset integer DEFAULT 0, page_limit integer DEFAULT 25) RETURNS TABLE(order_id uuid, total_count bigint)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
  with latest_checks as (
    select distinct on (check_row.order_item_id)
      check_row.order_id, check_row.order_item_id, check_row.result
    from public.order_item_availability_checks check_row
    order by check_row.order_item_id, check_row.checked_at desc
  ), availability as (
    select order_id, count(*) as checked_items,
      bool_and(result = 'available') as all_available
    from latest_checks group by order_id
  ), item_totals as (
    select order_id, count(*) as item_count
    from public.order_items group by order_id
  ), visible as (
    select o.*, min(f.due_at) filter (where f.status = 'open') as next_due_at,
      coalesce(a.checked_items, 0) > 0
        and not coalesce(a.all_available, false) as has_availability_issue,
      coalesce(i.item_count, 0) > 0
        and coalesce(a.checked_items, 0) = coalesce(i.item_count, 0)
        and coalesce(a.all_available, false) as has_complete_availability,
      exists (
        select 1 from public.customer_order_acceptances acceptance
        where acceptance.order_id = o.id
          and acceptance.accepted_total_cop = o.total_cop
      ) as has_current_acceptance
    from public.orders o
    left join public.order_followups f on f.order_id = o.id
    left join availability a on a.order_id = o.id
    left join item_totals i on i.order_id = o.id
    group by o.id, a.checked_items, a.all_available, i.item_count
  )
  select o.id, count(*) over ()
  from visible o
  join public.customers c on c.id = o.customer_id
  join public.sellers origin on origin.id = o.seller_id
  join public.sellers responsible on responsible.id = o.assigned_seller_id
  where (
    nullif(trim(search_text), '') is null
    or o.order_number ilike '%' || trim(search_text) || '%'
    or c.name ilike '%' || trim(search_text) || '%'
    or origin.display_name ilike '%' || trim(search_text) || '%'
    or responsible.display_name ilike '%' || trim(search_text) || '%'
  )
  and (filter_status is null or o.status = filter_status)
  and (
    nullif(trim(filter_seller_name), '') is null
    or responsible.display_name = trim(filter_seller_name)
  )
  and (created_after is null or o.created_at >= created_after)
  and (
    nullif(trim(filter_attention), '') is null
    or (filter_attention = 'contact_pending' and o.status = 'requested')
    or (
      filter_attention = 'availability_pending'
      and o.status = 'contacted'
      and not o.has_complete_availability
    )
    or (
      filter_attention = 'delivery_pending'
      and o.status = 'availability_verified'
      and o.shipping_status = 'pending_quote'
    )
    or (filter_attention = 'availability_issue' and o.has_availability_issue)
    or (
      filter_attention = 'customer_acceptance'
      and o.status = 'availability_verified'
      and o.shipping_status <> 'pending_quote'
      and not o.has_current_acceptance
    )
    or (filter_attention = 'overdue' and o.next_due_at < now())
    or (
      filter_attention = 'today' and o.next_due_at >= now()
      and (o.next_due_at at time zone 'America/Bogota')::date
        = (now() at time zone 'America/Bogota')::date
    )
    or (
      filter_attention = 'upcoming'
      and (o.next_due_at at time zone 'America/Bogota')::date
        > (now() at time zone 'America/Bogota')::date
    )
    or (filter_attention = 'none' and o.next_due_at is null)
  )
  order by
    case when o.has_availability_issue then 0
         when o.status = 'requested' then 1
         when o.status = 'contacted' and not o.has_complete_availability then 2
         when o.status = 'availability_verified'
           and o.shipping_status = 'pending_quote' then 3
         when o.status = 'availability_verified'
           and not o.has_current_acceptance then 4
         when o.next_due_at < now() then 5
         when o.next_due_at is not null then 6 else 7 end,
    o.next_due_at nulls last, o.created_at desc, o.id desc
  offset greatest(page_offset, 0)
  limit least(greatest(page_limit, 1), 100);
$$;


--
-- Name: set_initial_order_assignment(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_initial_order_assignment() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
begin
  new.assigned_seller_id := coalesce(
    new.assigned_seller_id,
    new.seller_id,
    (
      select id
      from public.sellers
      where code = 'WEB' and active
      limit 1
    )
  );

  if new.assigned_seller_id is null then
    raise exception 'initial_order_assignment_required';
  end if;

  return new;
end;
$$;


--
-- Name: FUNCTION set_initial_order_assignment(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.set_initial_order_assignment() IS 'Keeps origin seller separate from operational assignment. Direct public orders enter the WEB queue for later assignment.';


--
-- Name: staff_attention_counts(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.staff_attention_counts() RETURNS TABLE(attention text, total_count bigint)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
  with latest_checks as (
    select distinct on (check_row.order_item_id)
      check_row.order_id, check_row.order_item_id, check_row.result
    from public.order_item_availability_checks check_row
    order by check_row.order_item_id, check_row.checked_at desc
  ), availability as (
    select order_id, count(*) as checked_items,
      bool_and(result = 'available') as all_available
    from latest_checks group by order_id
  ), item_totals as (
    select order_id, count(*) as item_count
    from public.order_items group by order_id
  ), visible as (
    select o.id, o.status, o.shipping_status, o.total_cop,
      min(f.due_at) filter (where f.status = 'open') as next_due_at,
      coalesce(a.checked_items, 0) > 0
        and not coalesce(a.all_available, false) as has_availability_issue,
      coalesce(i.item_count, 0) > 0
        and coalesce(a.checked_items, 0) = coalesce(i.item_count, 0)
        and coalesce(a.all_available, false) as has_complete_availability,
      exists (
        select 1 from public.customer_order_acceptances acceptance
        where acceptance.order_id = o.id
          and acceptance.accepted_total_cop = o.total_cop
      ) as has_current_acceptance
    from public.orders o
    left join public.order_followups f on f.order_id = o.id
    left join availability a on a.order_id = o.id
    left join item_totals i on i.order_id = o.id
    group by o.id, a.checked_items, a.all_available, i.item_count
  ), classified as (
    select case
      when next_due_at < now() then 'overdue'
      when (next_due_at at time zone 'America/Bogota')::date
        = (now() at time zone 'America/Bogota')::date then 'today'
      when next_due_at is not null then 'upcoming'
      else 'none'
    end as attention from visible
    union all select 'contact_pending' from visible where status = 'requested'
    union all select 'availability_pending' from visible
      where status = 'contacted' and not has_complete_availability
    union all select 'delivery_pending' from visible
      where status = 'availability_verified' and shipping_status = 'pending_quote'
    union all select 'availability_issue' from visible where has_availability_issue
    union all select 'customer_acceptance' from visible
      where status = 'availability_verified'
        and shipping_status <> 'pending_quote'
        and not has_current_acceptance
  )
  select attention, count(*) from classified group by attention
  order by attention;
$$;


--
-- Name: staff_order_status_counts(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.staff_order_status_counts() RETURNS TABLE(status public.order_status, total_count bigint)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
  select o.status, count(*)
  from public.orders o
  group by o.status
  order by o.status;
$$;


--
-- Name: sync_order_commissions(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_order_commissions() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
begin
  if new.status = 'paid' and old.status <> 'paid' and new.seller_id is not null then
    insert into public.order_item_commissions(
      order_id, order_item_id, seller_id, commission_rule_id,
      base_cop, rate_basis_points, status
    )
    select
      new.id, item.id, new.seller_id, resolved_rule.id,
      item.subtotal_cop, resolved_rule.rate_basis_points, 'pending'
    from public.order_items item
    join lateral (
      select rule.id, rule.rate_basis_points
      from public.commission_rules rule
      where rule.active
        and rule.item_type = item.item_type
        and (rule.seller_id = new.seller_id or rule.seller_id is null)
        and (rule.starts_at is null or rule.starts_at <= now())
        and (rule.ends_at is null or rule.ends_at >= now())
      order by (rule.seller_id = new.seller_id) desc, rule.priority desc, rule.id
      limit 1
    ) resolved_rule on true
    where item.order_id = new.id
    on conflict (order_item_id) do nothing;
  elsif new.status = 'delivered' and old.status <> 'delivered' then
    update public.order_item_commissions
    set status = 'earned', updated_at = now()
    where order_id = new.id and status = 'pending';
  elsif new.status in ('returned', 'refunded', 'cancelled')
      and old.status <> new.status then
    update public.order_item_commissions
    set status = 'reversed', updated_at = now()
    where order_id = new.id and status <> 'reversed';
  end if;
  return new;
end;
$$;


--
-- Name: update_order_status(uuid, public.order_status, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_order_status(target_order_id uuid, target_status public.order_status, change_note text DEFAULT NULL::text) RETURNS public.order_status
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
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


--
-- Name: verify_order_availability(uuid, jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.verify_order_availability(target_order_id uuid, item_results jsonb, verification_note text DEFAULT NULL::text) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare
  actor public.staff_profiles%rowtype;
  current_status public.order_status;
  normalized_note text := nullif(left(trim(verification_note), 500), '');
  expected_count integer;
  supplied_count integer;
  entry jsonb;
  item_id uuid;
  item_result public.availability_result;
begin
  select * into actor from public.staff_profiles
  where user_id = (select auth.uid()) and active;
  if actor.user_id is null or not public.can_access_order(target_order_id) then
    raise exception 'availability_permission_denied';
  end if;

  select status into current_status from public.orders
  where id = target_order_id for update;
  if current_status not in ('requested', 'contacted') then
    raise exception 'availability_status_not_allowed';
  end if;

  select count(*) into expected_count from public.order_items
  where order_id = target_order_id;
  select count(distinct value->>'orderItemId') into supplied_count
  from jsonb_array_elements(coalesce(item_results, '[]'::jsonb));
  if expected_count = 0 or supplied_count <> expected_count then
    raise exception 'availability_all_items_required';
  end if;

  for entry in select value from jsonb_array_elements(item_results) loop
    item_id := (entry->>'orderItemId')::uuid;
    item_result := (entry->>'result')::public.availability_result;
    if not exists (
      select 1 from public.order_items
      where id = item_id and order_id = target_order_id
    ) then raise exception 'availability_invalid_item'; end if;
    if item_result <> 'available'
       and (normalized_note is null or length(normalized_note) < 5) then
      raise exception 'availability_note_required';
    end if;
    insert into public.order_item_availability_checks(
      order_id, order_item_id, result, note, checked_by,
      checker_role, checker_display_name
    ) values (
      target_order_id, item_id, item_result, normalized_note,
      (select auth.uid()), actor.role, actor.display_name
    );
  end loop;
  return expected_count;
end;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: campaigns; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.campaigns (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    code text NOT NULL,
    display_name text NOT NULL,
    starts_at timestamp with time zone,
    ends_at timestamp with time zone,
    active boolean DEFAULT true NOT NULL
);


--
-- Name: channels; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.channels (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    code text NOT NULL,
    display_name text NOT NULL,
    active boolean DEFAULT true NOT NULL
);


--
-- Name: commercial_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.commercial_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    journey_id text NOT NULL,
    event_name public.commercial_event_name NOT NULL,
    primary_product_id text NOT NULL,
    complementary_product_id text NOT NULL,
    cross_sell_relation_id text NOT NULL,
    seller_id uuid,
    channel_id uuid,
    campaign_id uuid,
    source text DEFAULT 'directo'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT commercial_events_journey_id_check CHECK ((journey_id ~ '^[a-f0-9]{32}$'::text))
);


--
-- Name: commercial_kit_components; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.commercial_kit_components (
    kit_product_id text NOT NULL,
    component_product_id text NOT NULL,
    quantity integer DEFAULT 1 NOT NULL,
    CONSTRAINT commercial_kit_components_check CHECK ((kit_product_id <> component_product_id)),
    CONSTRAINT commercial_kit_components_quantity_check CHECK (((quantity >= 1) AND (quantity <= 20)))
);


--
-- Name: commercial_kits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.commercial_kits (
    kit_product_id text NOT NULL,
    official_sku boolean DEFAULT false NOT NULL,
    active boolean DEFAULT false NOT NULL,
    starts_at timestamp with time zone,
    ends_at timestamp with time zone,
    campaign_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT commercial_kits_check CHECK (((NOT active) OR official_sku)),
    CONSTRAINT commercial_kits_check1 CHECK (((ends_at IS NULL) OR (starts_at IS NULL) OR (ends_at >= starts_at)))
);


--
-- Name: commercial_order_metrics; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.commercial_order_metrics AS
SELECT
    NULL::uuid AS order_id,
    NULL::text AS order_number,
    NULL::text AS journey_id,
    NULL::timestamp with time zone AS created_at,
    NULL::public.order_status AS status,
    NULL::uuid AS seller_id,
    NULL::uuid AS channel_id,
    NULL::uuid AS campaign_id,
    NULL::text AS primary_product_id,
    NULL::bigint AS product_revenue_cop,
    NULL::bigint AS net_product_revenue_cop,
    NULL::bigint AS complementary_revenue_cop,
    NULL::integer AS complementary_item_count,
    NULL::integer AS shipping_cop;


--
-- Name: commission_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.commission_rules (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    seller_id uuid,
    item_type public.order_item_type NOT NULL,
    rate_basis_points integer NOT NULL,
    priority smallint DEFAULT 1 NOT NULL,
    active boolean DEFAULT true NOT NULL,
    starts_at timestamp with time zone,
    ends_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT commission_rules_check CHECK (((ends_at IS NULL) OR (starts_at IS NULL) OR (ends_at >= starts_at))),
    CONSTRAINT commission_rules_priority_check CHECK (((priority >= 1) AND (priority <= 100))),
    CONSTRAINT commission_rules_rate_basis_points_check CHECK (((rate_basis_points >= 0) AND (rate_basis_points <= 10000)))
);


--
-- Name: cross_sell_event_metrics; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.cross_sell_event_metrics WITH (security_invoker='true') AS
 SELECT cross_sell_relation_id,
    primary_product_id,
    complementary_product_id,
    seller_id,
    channel_id,
    campaign_id,
    (count(DISTINCT journey_id) FILTER (WHERE (event_name = 'cross_sell_shown'::public.commercial_event_name)))::integer AS journeys_shown,
    (count(DISTINCT journey_id) FILTER (WHERE (event_name = 'complementary_added'::public.commercial_event_name)))::integer AS journeys_with_add,
    (count(DISTINCT journey_id) FILTER (WHERE (event_name = 'complementary_removed'::public.commercial_event_name)))::integer AS journeys_with_remove
   FROM public.commercial_events
  GROUP BY cross_sell_relation_id, primary_product_id, complementary_product_id, seller_id, channel_id, campaign_id;


--
-- Name: cross_sell_relations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cross_sell_relations (
    id text NOT NULL,
    source_product_id text NOT NULL,
    complementary_product_id text NOT NULL,
    relation_type text NOT NULL,
    priority smallint NOT NULL,
    benefit_text text NOT NULL,
    reason_text text NOT NULL,
    active boolean DEFAULT true NOT NULL,
    starts_at timestamp with time zone,
    ends_at timestamp with time zone,
    campaign_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT cross_sell_relations_benefit_text_check CHECK ((length(TRIM(BOTH FROM benefit_text)) > 0)),
    CONSTRAINT cross_sell_relations_check CHECK ((source_product_id <> complementary_product_id)),
    CONSTRAINT cross_sell_relations_check1 CHECK (((ends_at IS NULL) OR (starts_at IS NULL) OR (ends_at >= starts_at))),
    CONSTRAINT cross_sell_relations_id_check CHECK ((id ~ '^[a-z0-9][a-z0-9_-]{2,63}$'::text)),
    CONSTRAINT cross_sell_relations_priority_check CHECK (((priority >= 1) AND (priority <= 5))),
    CONSTRAINT cross_sell_relations_reason_text_check CHECK ((length(TRIM(BOTH FROM reason_text)) > 0)),
    CONSTRAINT cross_sell_relations_relation_type_check CHECK ((relation_type = ANY (ARRAY['same_line'::text, 'routine_step'::text, 'same_need'::text, 'compatible_care'::text, 'gift_upgrade'::text])))
);


--
-- Name: customer_consents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customer_consents (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    customer_id uuid NOT NULL,
    consent_type text NOT NULL,
    granted boolean NOT NULL,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT customer_consents_consent_type_check CHECK ((consent_type = ANY (ARRAY['data_processing'::text, 'promotions'::text])))
);


--
-- Name: customer_order_acceptances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customer_order_acceptances (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_id uuid NOT NULL,
    channel public.customer_acceptance_channel NOT NULL,
    order_snapshot jsonb NOT NULL,
    accepted_total_cop integer NOT NULL,
    note text NOT NULL,
    recorded_by uuid NOT NULL,
    recorder_role public.staff_role NOT NULL,
    recorder_display_name text NOT NULL,
    accepted_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT customer_order_acceptances_accepted_total_cop_check CHECK ((accepted_total_cop >= 0)),
    CONSTRAINT customer_order_acceptances_note_check CHECK (((length(TRIM(BOTH FROM note)) >= 5) AND (length(TRIM(BOTH FROM note)) <= 500)))
);


--
-- Name: TABLE customer_order_acceptances; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.customer_order_acceptances IS 'Audited customer acceptance of the commercial order and totals. This is not payment verification and does not authorize a store purchase.';


--
-- Name: customers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    whatsapp text NOT NULL,
    city text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT customers_whatsapp_check CHECK ((whatsapp ~ '^\d{10,15}$'::text))
);


--
-- Name: COLUMN customers.whatsapp; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.customers.whatsapp IS 'Colombian mobile number normalized as 57 + ten national digits. Structural validation does not prove an active WhatsApp account.';


--
-- Name: daily_order_sequences; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.daily_order_sequences (
    sequence_date date NOT NULL,
    last_value integer NOT NULL,
    CONSTRAINT daily_order_sequences_last_value_check CHECK ((last_value > 0))
);


--
-- Name: feature_flags; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.feature_flags (
    key text NOT NULL,
    enabled boolean DEFAULT false NOT NULL,
    description text NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE feature_flags; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.feature_flags IS 'Server-side release gates. No authenticated role receives direct write access.';


--
-- Name: order_assignment_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.order_assignment_history (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_id uuid NOT NULL,
    previous_seller_id uuid,
    new_seller_id uuid NOT NULL,
    previous_seller_name text,
    new_seller_name text NOT NULL,
    changed_by uuid,
    actor_role public.staff_role,
    actor_display_name text,
    reason text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT order_assignment_history_reason_check CHECK ((length(TRIM(BOTH FROM reason)) >= 5))
);


--
-- Name: order_contact_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.order_contact_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_id uuid NOT NULL,
    channel text NOT NULL,
    actor_user_id uuid NOT NULL,
    actor_role public.staff_role NOT NULL,
    actor_display_name text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT order_contact_events_channel_check CHECK ((channel = 'whatsapp'::text))
);


--
-- Name: order_customer_delivery_preferences; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.order_customer_delivery_preferences (
    order_id uuid NOT NULL,
    requires_delivery boolean NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE order_customer_delivery_preferences; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.order_customer_delivery_preferences IS 'Customer delivery preference captured at request time. It does not confirm shipping cost or fulfillment.';


--
-- Name: order_delivery_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.order_delivery_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_id uuid NOT NULL,
    previous_shipping_status public.shipping_status NOT NULL,
    previous_shipping_cop integer NOT NULL,
    shipping_status public.shipping_status NOT NULL,
    shipping_cop integer NOT NULL,
    actor_user_id uuid NOT NULL,
    actor_role public.staff_role NOT NULL,
    actor_display_name text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT order_delivery_events_previous_shipping_cop_check CHECK ((previous_shipping_cop >= 0)),
    CONSTRAINT order_delivery_events_shipping_cop_check CHECK ((shipping_cop >= 0))
);


--
-- Name: order_followups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.order_followups (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_id uuid NOT NULL,
    note text NOT NULL,
    due_at timestamp with time zone NOT NULL,
    status public.followup_status DEFAULT 'open'::public.followup_status NOT NULL,
    created_by uuid,
    creator_role public.staff_role,
    creator_display_name text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_by uuid,
    completed_by_name text,
    completed_at timestamp with time zone,
    completion_note text,
    CONSTRAINT order_followups_check CHECK ((((status = 'completed'::public.followup_status) AND (completed_at IS NOT NULL)) OR ((status <> 'completed'::public.followup_status) AND (completed_at IS NULL)))),
    CONSTRAINT order_followups_completion_note_check CHECK (((completion_note IS NULL) OR ((length(TRIM(BOTH FROM completion_note)) >= 5) AND (length(TRIM(BOTH FROM completion_note)) <= 500)))),
    CONSTRAINT order_followups_note_check CHECK (((length(TRIM(BOTH FROM note)) >= 5) AND (length(TRIM(BOTH FROM note)) <= 500)))
);


--
-- Name: order_item_availability_checks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.order_item_availability_checks (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_id uuid NOT NULL,
    order_item_id uuid NOT NULL,
    result public.availability_result NOT NULL,
    note text,
    checked_by uuid NOT NULL,
    checker_role public.staff_role NOT NULL,
    checker_display_name text NOT NULL,
    checked_at timestamp with time zone DEFAULT now() NOT NULL,
    verification_method text DEFAULT 'manual_store_check'::text NOT NULL,
    CONSTRAINT order_item_availability_checks_note_check CHECK (((note IS NULL) OR ((length(TRIM(BOTH FROM note)) >= 5) AND (length(TRIM(BOTH FROM note)) <= 500)))),
    CONSTRAINT order_item_availability_checks_verification_method_check CHECK ((verification_method = 'manual_store_check'::text))
);


--
-- Name: TABLE order_item_availability_checks; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.order_item_availability_checks IS 'Manual checks of availability for purchase from the external store. This table does not represent owned inventory or physical stock.';


--
-- Name: COLUMN order_item_availability_checks.result; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.order_item_availability_checks.result IS 'Latest availability reported for purchasing the requested quantity from the store.';


--
-- Name: order_item_commissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.order_item_commissions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_id uuid NOT NULL,
    order_item_id uuid NOT NULL,
    seller_id uuid NOT NULL,
    commission_rule_id uuid NOT NULL,
    base_cop integer NOT NULL,
    rate_basis_points integer NOT NULL,
    commission_cop integer GENERATED ALWAYS AS (round((((base_cop)::numeric * (rate_basis_points)::numeric) / (10000)::numeric))) STORED,
    status public.commission_status DEFAULT 'pending'::public.commission_status NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT order_item_commissions_base_cop_check CHECK ((base_cop >= 0)),
    CONSTRAINT order_item_commissions_rate_basis_points_check CHECK (((rate_basis_points >= 0) AND (rate_basis_points <= 10000)))
);


--
-- Name: order_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.order_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_id uuid NOT NULL,
    product_id text NOT NULL,
    product_code text NOT NULL,
    product_name text NOT NULL,
    quantity integer NOT NULL,
    final_unit_price_cop integer NOT NULL,
    subtotal_cop integer GENERATED ALWAYS AS ((quantity * final_unit_price_cop)) STORED,
    item_type public.order_item_type DEFAULT 'primary'::public.order_item_type NOT NULL,
    original_unit_price_cop integer NOT NULL,
    discount_cop integer DEFAULT 0 NOT NULL,
    cross_sell_relation_id text,
    CONSTRAINT order_item_discount_nonnegative CHECK ((discount_cop >= 0)),
    CONSTRAINT order_item_discount_valid CHECK ((discount_cop <= original_unit_price_cop)),
    CONSTRAINT order_items_quantity_check CHECK ((quantity > 0)),
    CONSTRAINT order_items_unit_price_cop_check CHECK ((final_unit_price_cop >= 0))
);


--
-- Name: COLUMN order_items.quantity; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.order_items.quantity IS 'Quantity requested by the customer; never an owned-stock balance.';


--
-- Name: order_status_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.order_status_history (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_id uuid NOT NULL,
    status public.order_status NOT NULL,
    changed_by uuid,
    note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    previous_status public.order_status,
    actor_role public.staff_role,
    actor_display_name text
);


--
-- Name: orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.orders (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_number text NOT NULL,
    customer_id uuid NOT NULL,
    seller_id uuid,
    channel_id uuid,
    campaign_id uuid,
    source text DEFAULT 'directo'::text NOT NULL,
    status public.order_status DEFAULT 'requested'::public.order_status NOT NULL,
    shipping_status public.shipping_status DEFAULT 'pending_quote'::public.shipping_status NOT NULL,
    subtotal_cop integer NOT NULL,
    discount_cop integer DEFAULT 0 NOT NULL,
    shipping_cop integer DEFAULT 0 NOT NULL,
    total_cop integer GENERATED ALWAYS AS (((subtotal_cop - discount_cop) + shipping_cop)) STORED,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    journey_id text,
    primary_product_id text,
    shipping_estimate_min_cop integer DEFAULT 10000 NOT NULL,
    shipping_estimate_max_cop integer DEFAULT 15000 NOT NULL,
    assigned_seller_id uuid NOT NULL,
    CONSTRAINT orders_check CHECK ((discount_cop <= subtotal_cop)),
    CONSTRAINT orders_check1 CHECK ((shipping_estimate_max_cop >= shipping_estimate_min_cop)),
    CONSTRAINT orders_discount_cop_check CHECK ((discount_cop >= 0)),
    CONSTRAINT orders_journey_id_check CHECK ((journey_id ~ '^[a-f0-9]{32}$'::text)),
    CONSTRAINT orders_shipping_cop_check CHECK ((shipping_cop >= 0)),
    CONSTRAINT orders_shipping_estimate_min_cop_check CHECK ((shipping_estimate_min_cop >= 0)),
    CONSTRAINT orders_subtotal_cop_check CHECK ((subtotal_cop >= 0))
);


--
-- Name: products; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.products (
    id text NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    current_price_cop integer NOT NULL,
    available boolean DEFAULT true NOT NULL,
    active boolean DEFAULT true NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    is_suggested_kit boolean DEFAULT false NOT NULL,
    eligible boolean DEFAULT true NOT NULL,
    category text,
    subcategory text,
    description text,
    catalog_characteristics jsonb DEFAULT '[]'::jsonb NOT NULL,
    currency text DEFAULT 'COP'::text NOT NULL,
    presentation text,
    official_url text,
    catalog_url text,
    catalog_month text,
    catalog_year integer,
    catalog_updated_on date,
    catalog_status text DEFAULT 'pending_review'::text NOT NULL,
    catalog_source text,
    CONSTRAINT products_current_price_cop_check CHECK ((current_price_cop >= 0))
);


--
-- Name: COLUMN products.available; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.products.available IS 'Catalog eligibility for recommendation, not physical inventory owned by the seller.';


--
-- Name: COLUMN products.eligible; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.products.eligible IS 'Only true after recommendation attributes and commercial suitability are verified.';


--
-- Name: COLUMN products.catalog_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.products.catalog_status IS 'Monthly source status; activo, retirado, or pending_review for preserved legacy records.';


--
-- Name: sellers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sellers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    code text NOT NULL,
    display_name text NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT sellers_code_check CHECK ((code ~ '^[A-Z0-9]{2,12}$'::text))
);


--
-- Name: staff_profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.staff_profiles (
    user_id uuid NOT NULL,
    role public.staff_role NOT NULL,
    seller_id uuid,
    display_name text NOT NULL,
    active boolean DEFAULT true NOT NULL,
    CONSTRAINT staff_profiles_check CHECK (((role = 'admin'::public.staff_role) OR (seller_id IS NOT NULL)))
);


--
-- Name: store_purchase_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.store_purchase_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_purchase_id uuid NOT NULL,
    status public.store_purchase_status NOT NULL,
    actor_user_id uuid,
    actor_role public.staff_role,
    actor_display_name text,
    note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: store_purchases; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.store_purchases (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_id uuid NOT NULL,
    status public.store_purchase_status DEFAULT 'awaiting_payment_verification'::public.store_purchase_status NOT NULL,
    external_reference text,
    purchased_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT store_purchases_check CHECK ((((status = 'purchased'::public.store_purchase_status) AND (purchased_at IS NOT NULL)) OR ((status <> 'purchased'::public.store_purchase_status) AND (purchased_at IS NULL))))
);


--
-- Name: TABLE store_purchases; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.store_purchases IS 'Purchase from the external store, separate from the customer order. No payment credentials or customer banking secrets may be stored here.';


--
-- Name: COLUMN store_purchases.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.store_purchases.status IS 'Initially locked awaiting customer payment verification. No mutation RPC is enabled in this phase.';


--
-- Name: campaigns campaigns_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaigns
    ADD CONSTRAINT campaigns_code_key UNIQUE (code);


--
-- Name: campaigns campaigns_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaigns
    ADD CONSTRAINT campaigns_pkey PRIMARY KEY (id);


--
-- Name: channels channels_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channels
    ADD CONSTRAINT channels_code_key UNIQUE (code);


--
-- Name: channels channels_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channels
    ADD CONSTRAINT channels_pkey PRIMARY KEY (id);


--
-- Name: commercial_events commercial_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commercial_events
    ADD CONSTRAINT commercial_events_pkey PRIMARY KEY (id);


--
-- Name: commercial_kit_components commercial_kit_components_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commercial_kit_components
    ADD CONSTRAINT commercial_kit_components_pkey PRIMARY KEY (kit_product_id, component_product_id);


--
-- Name: commercial_kits commercial_kits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commercial_kits
    ADD CONSTRAINT commercial_kits_pkey PRIMARY KEY (kit_product_id);


--
-- Name: commission_rules commission_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commission_rules
    ADD CONSTRAINT commission_rules_pkey PRIMARY KEY (id);


--
-- Name: cross_sell_relations cross_sell_relations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cross_sell_relations
    ADD CONSTRAINT cross_sell_relations_pkey PRIMARY KEY (id);


--
-- Name: cross_sell_relations cross_sell_relations_source_product_id_complementary_produc_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cross_sell_relations
    ADD CONSTRAINT cross_sell_relations_source_product_id_complementary_produc_key UNIQUE NULLS NOT DISTINCT (source_product_id, complementary_product_id, relation_type, campaign_id);


--
-- Name: customer_consents customer_consents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_consents
    ADD CONSTRAINT customer_consents_pkey PRIMARY KEY (id);


--
-- Name: customer_order_acceptances customer_order_acceptances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_order_acceptances
    ADD CONSTRAINT customer_order_acceptances_pkey PRIMARY KEY (id);


--
-- Name: customers customers_colombian_mobile_format; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.customers
    ADD CONSTRAINT customers_colombian_mobile_format CHECK ((whatsapp ~ '^573[0-9]{9}$'::text)) NOT VALID;


--
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (id);


--
-- Name: customers customers_whatsapp_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_whatsapp_key UNIQUE (whatsapp);


--
-- Name: daily_order_sequences daily_order_sequences_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_order_sequences
    ADD CONSTRAINT daily_order_sequences_pkey PRIMARY KEY (sequence_date);


--
-- Name: feature_flags feature_flags_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feature_flags
    ADD CONSTRAINT feature_flags_pkey PRIMARY KEY (key);


--
-- Name: order_assignment_history order_assignment_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_assignment_history
    ADD CONSTRAINT order_assignment_history_pkey PRIMARY KEY (id);


--
-- Name: order_contact_events order_contact_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_contact_events
    ADD CONSTRAINT order_contact_events_pkey PRIMARY KEY (id);


--
-- Name: order_customer_delivery_preferences order_customer_delivery_preferences_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_customer_delivery_preferences
    ADD CONSTRAINT order_customer_delivery_preferences_pkey PRIMARY KEY (order_id);


--
-- Name: order_delivery_events order_delivery_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_delivery_events
    ADD CONSTRAINT order_delivery_events_pkey PRIMARY KEY (id);


--
-- Name: order_followups order_followups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_followups
    ADD CONSTRAINT order_followups_pkey PRIMARY KEY (id);


--
-- Name: order_item_availability_checks order_item_availability_checks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_item_availability_checks
    ADD CONSTRAINT order_item_availability_checks_pkey PRIMARY KEY (id);


--
-- Name: order_item_commissions order_item_commissions_order_item_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_item_commissions
    ADD CONSTRAINT order_item_commissions_order_item_id_key UNIQUE (order_item_id);


--
-- Name: order_item_commissions order_item_commissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_item_commissions
    ADD CONSTRAINT order_item_commissions_pkey PRIMARY KEY (id);


--
-- Name: order_items order_items_one_product_per_order; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_one_product_per_order UNIQUE (order_id, product_id);


--
-- Name: order_items order_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_pkey PRIMARY KEY (id);


--
-- Name: order_status_history order_status_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_status_history
    ADD CONSTRAINT order_status_history_pkey PRIMARY KEY (id);


--
-- Name: orders orders_journey_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_journey_id_key UNIQUE (journey_id);


--
-- Name: orders orders_order_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_order_number_key UNIQUE (order_number);


--
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (id);


--
-- Name: products products_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_code_key UNIQUE (code);


--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


--
-- Name: sellers sellers_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sellers
    ADD CONSTRAINT sellers_code_key UNIQUE (code);


--
-- Name: sellers sellers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sellers
    ADD CONSTRAINT sellers_pkey PRIMARY KEY (id);


--
-- Name: staff_profiles staff_profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_profiles
    ADD CONSTRAINT staff_profiles_pkey PRIMARY KEY (user_id);


--
-- Name: store_purchase_events store_purchase_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store_purchase_events
    ADD CONSTRAINT store_purchase_events_pkey PRIMARY KEY (id);


--
-- Name: store_purchases store_purchases_order_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store_purchases
    ADD CONSTRAINT store_purchases_order_id_key UNIQUE (order_id);


--
-- Name: store_purchases store_purchases_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store_purchases
    ADD CONSTRAINT store_purchases_pkey PRIMARY KEY (id);


--
-- Name: commercial_events_attribution_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX commercial_events_attribution_idx ON public.commercial_events USING btree (seller_id, channel_id, campaign_id);


--
-- Name: commercial_events_created_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX commercial_events_created_idx ON public.commercial_events USING btree (created_at DESC);


--
-- Name: commercial_events_one_show_per_journey_relation; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX commercial_events_one_show_per_journey_relation ON public.commercial_events USING btree (journey_id, cross_sell_relation_id) WHERE (event_name = 'cross_sell_shown'::public.commercial_event_name);


--
-- Name: commercial_events_relation_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX commercial_events_relation_idx ON public.commercial_events USING btree (cross_sell_relation_id, event_name, journey_id);


--
-- Name: commission_rules_resolution_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX commission_rules_resolution_idx ON public.commission_rules USING btree (seller_id, item_type, active, priority DESC);


--
-- Name: cross_sell_source_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX cross_sell_source_idx ON public.cross_sell_relations USING btree (source_product_id, active, priority DESC);


--
-- Name: customer_order_acceptances_order_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX customer_order_acceptances_order_idx ON public.customer_order_acceptances USING btree (order_id, accepted_at DESC);


--
-- Name: order_assignment_history_order_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX order_assignment_history_order_idx ON public.order_assignment_history USING btree (order_id, created_at);


--
-- Name: order_contact_events_order_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX order_contact_events_order_idx ON public.order_contact_events USING btree (order_id, created_at DESC);


--
-- Name: order_delivery_events_order_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX order_delivery_events_order_idx ON public.order_delivery_events USING btree (order_id, created_at DESC);


--
-- Name: order_followups_open_due_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX order_followups_open_due_idx ON public.order_followups USING btree (due_at) WHERE (status = 'open'::public.followup_status);


--
-- Name: order_followups_order_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX order_followups_order_idx ON public.order_followups USING btree (order_id, due_at DESC);


--
-- Name: order_history_order_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX order_history_order_id_idx ON public.order_status_history USING btree (order_id);


--
-- Name: order_item_availability_checks_latest_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX order_item_availability_checks_latest_idx ON public.order_item_availability_checks USING btree (order_item_id, checked_at DESC);


--
-- Name: order_item_commissions_order_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX order_item_commissions_order_idx ON public.order_item_commissions USING btree (order_id);


--
-- Name: order_item_commissions_seller_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX order_item_commissions_seller_idx ON public.order_item_commissions USING btree (seller_id, status, created_at DESC);


--
-- Name: order_items_order_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX order_items_order_id_idx ON public.order_items USING btree (order_id);


--
-- Name: orders_assigned_seller_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orders_assigned_seller_idx ON public.orders USING btree (assigned_seller_id, created_at DESC);


--
-- Name: orders_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orders_created_at_idx ON public.orders USING btree (created_at DESC);


--
-- Name: orders_customer_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orders_customer_id_idx ON public.orders USING btree (customer_id);


--
-- Name: orders_seller_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orders_seller_id_idx ON public.orders USING btree (seller_id);


--
-- Name: store_purchase_events_purchase_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX store_purchase_events_purchase_idx ON public.store_purchase_events USING btree (store_purchase_id, created_at);


--
-- Name: commercial_order_metrics _RETURN; Type: RULE; Schema: public; Owner: -
--

CREATE OR REPLACE VIEW public.commercial_order_metrics WITH (security_invoker='true') AS
 SELECT orders.id AS order_id,
    orders.order_number,
    orders.journey_id,
    orders.created_at,
    orders.status,
    orders.seller_id,
    orders.channel_id,
    orders.campaign_id,
    orders.primary_product_id,
    COALESCE(sum(items.subtotal_cop), (0)::bigint) AS product_revenue_cop,
    ((orders.subtotal_cop - orders.discount_cop))::bigint AS net_product_revenue_cop,
    COALESCE(sum(items.subtotal_cop) FILTER (WHERE (items.item_type = 'complementary'::public.order_item_type)), (0)::bigint) AS complementary_revenue_cop,
    (count(*) FILTER (WHERE (items.item_type = 'complementary'::public.order_item_type)))::integer AS complementary_item_count,
    orders.shipping_cop
   FROM (public.orders
     JOIN public.order_items items ON ((items.order_id = orders.id)))
  GROUP BY orders.id;


--
-- Name: customers customers_normalize_colombian_mobile; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER customers_normalize_colombian_mobile BEFORE INSERT OR UPDATE OF whatsapp ON public.customers FOR EACH ROW EXECUTE FUNCTION public.normalize_customer_colombian_mobile();


--
-- Name: orders log_initial_order_assignment; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER log_initial_order_assignment AFTER INSERT ON public.orders FOR EACH ROW EXECUTE FUNCTION public.log_initial_order_assignment();


--
-- Name: orders orders_create_store_purchase; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER orders_create_store_purchase AFTER UPDATE OF status ON public.orders FOR EACH ROW EXECUTE FUNCTION public.create_store_purchase_after_confirmation();


--
-- Name: orders orders_guard_disabled_features; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER orders_guard_disabled_features BEFORE UPDATE OF status ON public.orders FOR EACH ROW EXECUTE FUNCTION public.guard_disabled_order_features();


--
-- Name: orders orders_require_customer_acceptance; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER orders_require_customer_acceptance BEFORE UPDATE OF status ON public.orders FOR EACH ROW EXECUTE FUNCTION public.guard_customer_acceptance_before_confirmation();


--
-- Name: orders orders_require_verified_availability; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER orders_require_verified_availability BEFORE UPDATE OF status ON public.orders FOR EACH ROW EXECUTE FUNCTION public.guard_verified_availability_transition();


--
-- Name: orders orders_sync_commissions; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER orders_sync_commissions AFTER UPDATE OF status ON public.orders FOR EACH ROW EXECUTE FUNCTION public.sync_order_commissions();


--
-- Name: orders set_initial_order_assignment; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_initial_order_assignment BEFORE INSERT ON public.orders FOR EACH ROW EXECUTE FUNCTION public.set_initial_order_assignment();


--
-- Name: commercial_events commercial_events_campaign_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commercial_events
    ADD CONSTRAINT commercial_events_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES public.campaigns(id);


--
-- Name: commercial_events commercial_events_channel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commercial_events
    ADD CONSTRAINT commercial_events_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES public.channels(id);


--
-- Name: commercial_events commercial_events_complementary_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commercial_events
    ADD CONSTRAINT commercial_events_complementary_product_id_fkey FOREIGN KEY (complementary_product_id) REFERENCES public.products(id);


--
-- Name: commercial_events commercial_events_cross_sell_relation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commercial_events
    ADD CONSTRAINT commercial_events_cross_sell_relation_id_fkey FOREIGN KEY (cross_sell_relation_id) REFERENCES public.cross_sell_relations(id);


--
-- Name: commercial_events commercial_events_primary_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commercial_events
    ADD CONSTRAINT commercial_events_primary_product_id_fkey FOREIGN KEY (primary_product_id) REFERENCES public.products(id);


--
-- Name: commercial_events commercial_events_seller_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commercial_events
    ADD CONSTRAINT commercial_events_seller_id_fkey FOREIGN KEY (seller_id) REFERENCES public.sellers(id);


--
-- Name: commercial_kit_components commercial_kit_components_component_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commercial_kit_components
    ADD CONSTRAINT commercial_kit_components_component_product_id_fkey FOREIGN KEY (component_product_id) REFERENCES public.products(id);


--
-- Name: commercial_kit_components commercial_kit_components_kit_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commercial_kit_components
    ADD CONSTRAINT commercial_kit_components_kit_product_id_fkey FOREIGN KEY (kit_product_id) REFERENCES public.commercial_kits(kit_product_id) ON DELETE CASCADE;


--
-- Name: commercial_kits commercial_kits_campaign_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commercial_kits
    ADD CONSTRAINT commercial_kits_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES public.campaigns(id);


--
-- Name: commercial_kits commercial_kits_kit_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commercial_kits
    ADD CONSTRAINT commercial_kits_kit_product_id_fkey FOREIGN KEY (kit_product_id) REFERENCES public.products(id);


--
-- Name: commission_rules commission_rules_seller_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commission_rules
    ADD CONSTRAINT commission_rules_seller_id_fkey FOREIGN KEY (seller_id) REFERENCES public.sellers(id);


--
-- Name: cross_sell_relations cross_sell_relations_campaign_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cross_sell_relations
    ADD CONSTRAINT cross_sell_relations_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES public.campaigns(id);


--
-- Name: cross_sell_relations cross_sell_relations_complementary_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cross_sell_relations
    ADD CONSTRAINT cross_sell_relations_complementary_product_id_fkey FOREIGN KEY (complementary_product_id) REFERENCES public.products(id);


--
-- Name: cross_sell_relations cross_sell_relations_source_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cross_sell_relations
    ADD CONSTRAINT cross_sell_relations_source_product_id_fkey FOREIGN KEY (source_product_id) REFERENCES public.products(id);


--
-- Name: customer_consents customer_consents_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_consents
    ADD CONSTRAINT customer_consents_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE CASCADE;


--
-- Name: customer_order_acceptances customer_order_acceptances_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_order_acceptances
    ADD CONSTRAINT customer_order_acceptances_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;


--
-- Name: customer_order_acceptances customer_order_acceptances_recorded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_order_acceptances
    ADD CONSTRAINT customer_order_acceptances_recorded_by_fkey FOREIGN KEY (recorded_by) REFERENCES auth.users(id);


--
-- Name: order_assignment_history order_assignment_history_changed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_assignment_history
    ADD CONSTRAINT order_assignment_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES auth.users(id);


--
-- Name: order_assignment_history order_assignment_history_new_seller_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_assignment_history
    ADD CONSTRAINT order_assignment_history_new_seller_id_fkey FOREIGN KEY (new_seller_id) REFERENCES public.sellers(id);


--
-- Name: order_assignment_history order_assignment_history_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_assignment_history
    ADD CONSTRAINT order_assignment_history_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;


--
-- Name: order_assignment_history order_assignment_history_previous_seller_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_assignment_history
    ADD CONSTRAINT order_assignment_history_previous_seller_id_fkey FOREIGN KEY (previous_seller_id) REFERENCES public.sellers(id);


--
-- Name: order_contact_events order_contact_events_actor_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_contact_events
    ADD CONSTRAINT order_contact_events_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id);


--
-- Name: order_contact_events order_contact_events_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_contact_events
    ADD CONSTRAINT order_contact_events_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;


--
-- Name: order_customer_delivery_preferences order_customer_delivery_preferences_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_customer_delivery_preferences
    ADD CONSTRAINT order_customer_delivery_preferences_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;


--
-- Name: order_delivery_events order_delivery_events_actor_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_delivery_events
    ADD CONSTRAINT order_delivery_events_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id);


--
-- Name: order_delivery_events order_delivery_events_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_delivery_events
    ADD CONSTRAINT order_delivery_events_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;


--
-- Name: order_followups order_followups_completed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_followups
    ADD CONSTRAINT order_followups_completed_by_fkey FOREIGN KEY (completed_by) REFERENCES auth.users(id);


--
-- Name: order_followups order_followups_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_followups
    ADD CONSTRAINT order_followups_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);


--
-- Name: order_followups order_followups_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_followups
    ADD CONSTRAINT order_followups_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;


--
-- Name: order_item_availability_checks order_item_availability_checks_checked_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_item_availability_checks
    ADD CONSTRAINT order_item_availability_checks_checked_by_fkey FOREIGN KEY (checked_by) REFERENCES auth.users(id);


--
-- Name: order_item_availability_checks order_item_availability_checks_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_item_availability_checks
    ADD CONSTRAINT order_item_availability_checks_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;


--
-- Name: order_item_availability_checks order_item_availability_checks_order_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_item_availability_checks
    ADD CONSTRAINT order_item_availability_checks_order_item_id_fkey FOREIGN KEY (order_item_id) REFERENCES public.order_items(id) ON DELETE CASCADE;


--
-- Name: order_item_commissions order_item_commissions_commission_rule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_item_commissions
    ADD CONSTRAINT order_item_commissions_commission_rule_id_fkey FOREIGN KEY (commission_rule_id) REFERENCES public.commission_rules(id);


--
-- Name: order_item_commissions order_item_commissions_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_item_commissions
    ADD CONSTRAINT order_item_commissions_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id);


--
-- Name: order_item_commissions order_item_commissions_order_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_item_commissions
    ADD CONSTRAINT order_item_commissions_order_item_id_fkey FOREIGN KEY (order_item_id) REFERENCES public.order_items(id);


--
-- Name: order_item_commissions order_item_commissions_seller_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_item_commissions
    ADD CONSTRAINT order_item_commissions_seller_id_fkey FOREIGN KEY (seller_id) REFERENCES public.sellers(id);


--
-- Name: order_items order_items_cross_sell_relation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_cross_sell_relation_id_fkey FOREIGN KEY (cross_sell_relation_id) REFERENCES public.cross_sell_relations(id);


--
-- Name: order_items order_items_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;


--
-- Name: order_items order_items_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);


--
-- Name: order_status_history order_status_history_changed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_status_history
    ADD CONSTRAINT order_status_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES auth.users(id);


--
-- Name: order_status_history order_status_history_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_status_history
    ADD CONSTRAINT order_status_history_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;


--
-- Name: orders orders_assigned_seller_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_assigned_seller_id_fkey FOREIGN KEY (assigned_seller_id) REFERENCES public.sellers(id);


--
-- Name: orders orders_campaign_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES public.campaigns(id);


--
-- Name: orders orders_channel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES public.channels(id);


--
-- Name: orders orders_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: orders orders_primary_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_primary_product_id_fkey FOREIGN KEY (primary_product_id) REFERENCES public.products(id);


--
-- Name: orders orders_seller_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_seller_id_fkey FOREIGN KEY (seller_id) REFERENCES public.sellers(id);


--
-- Name: staff_profiles staff_profiles_seller_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_profiles
    ADD CONSTRAINT staff_profiles_seller_id_fkey FOREIGN KEY (seller_id) REFERENCES public.sellers(id);


--
-- Name: staff_profiles staff_profiles_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_profiles
    ADD CONSTRAINT staff_profiles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: store_purchase_events store_purchase_events_actor_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store_purchase_events
    ADD CONSTRAINT store_purchase_events_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id);


--
-- Name: store_purchase_events store_purchase_events_store_purchase_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store_purchase_events
    ADD CONSTRAINT store_purchase_events_store_purchase_id_fkey FOREIGN KEY (store_purchase_id) REFERENCES public.store_purchases(id) ON DELETE CASCADE;


--
-- Name: store_purchases store_purchases_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store_purchases
    ADD CONSTRAINT store_purchases_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE RESTRICT;


--
-- Name: products active products are public; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "active products are public" ON public.products FOR SELECT TO authenticated, anon USING (active);


--
-- Name: commission_rules admins can view commission rules; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "admins can view commission rules" ON public.commission_rules FOR SELECT TO authenticated USING (public.is_admin());


--
-- Name: commercial_kit_components admins can view every kit component; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "admins can view every kit component" ON public.commercial_kit_components FOR SELECT TO authenticated USING (public.is_admin());


--
-- Name: commercial_kits admins can view every kit definition; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "admins can view every kit definition" ON public.commercial_kits FOR SELECT TO authenticated USING (public.is_admin());


--
-- Name: campaigns authenticated staff can view campaigns; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "authenticated staff can view campaigns" ON public.campaigns FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.staff_profiles
  WHERE ((staff_profiles.user_id = ( SELECT auth.uid() AS uid)) AND staff_profiles.active))));


--
-- Name: channels authenticated staff can view channels; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "authenticated staff can view channels" ON public.channels FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.staff_profiles
  WHERE ((staff_profiles.user_id = ( SELECT auth.uid() AS uid)) AND staff_profiles.active))));


--
-- Name: sellers authenticated staff can view sellers; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "authenticated staff can view sellers" ON public.sellers FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.staff_profiles
  WHERE ((staff_profiles.user_id = ( SELECT auth.uid() AS uid)) AND staff_profiles.active))));


--
-- Name: campaigns; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.campaigns ENABLE ROW LEVEL SECURITY;

--
-- Name: channels; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.channels ENABLE ROW LEVEL SECURITY;

--
-- Name: commercial_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.commercial_events ENABLE ROW LEVEL SECURITY;

--
-- Name: commercial_kit_components; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.commercial_kit_components ENABLE ROW LEVEL SECURITY;

--
-- Name: commercial_kits; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.commercial_kits ENABLE ROW LEVEL SECURITY;

--
-- Name: commission_rules; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.commission_rules ENABLE ROW LEVEL SECURITY;

--
-- Name: cross_sell_relations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.cross_sell_relations ENABLE ROW LEVEL SECURITY;

--
-- Name: cross_sell_relations current cross-sell relations are public; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "current cross-sell relations are public" ON public.cross_sell_relations FOR SELECT TO authenticated, anon USING ((active AND ((starts_at IS NULL) OR (starts_at <= now())) AND ((ends_at IS NULL) OR (ends_at >= now()))));


--
-- Name: commercial_kit_components current official kit components are public; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "current official kit components are public" ON public.commercial_kit_components FOR SELECT TO authenticated, anon USING ((EXISTS ( SELECT 1
   FROM public.commercial_kits kit
  WHERE (kit.kit_product_id = commercial_kit_components.kit_product_id))));


--
-- Name: commercial_kits current official kits are public; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "current official kits are public" ON public.commercial_kits FOR SELECT TO authenticated, anon USING ((official_sku AND active AND ((starts_at IS NULL) OR (starts_at <= now())) AND ((ends_at IS NULL) OR (ends_at >= now()))));


--
-- Name: customer_consents; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.customer_consents ENABLE ROW LEVEL SECURITY;

--
-- Name: customer_order_acceptances; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.customer_order_acceptances ENABLE ROW LEVEL SECURITY;

--
-- Name: customers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

--
-- Name: daily_order_sequences; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.daily_order_sequences ENABLE ROW LEVEL SECURITY;

--
-- Name: feature_flags; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.feature_flags ENABLE ROW LEVEL SECURITY;

--
-- Name: order_assignment_history; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.order_assignment_history ENABLE ROW LEVEL SECURITY;

--
-- Name: order_contact_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.order_contact_events ENABLE ROW LEVEL SECURITY;

--
-- Name: order_customer_delivery_preferences; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.order_customer_delivery_preferences ENABLE ROW LEVEL SECURITY;

--
-- Name: order_delivery_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.order_delivery_events ENABLE ROW LEVEL SECURITY;

--
-- Name: order_followups; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.order_followups ENABLE ROW LEVEL SECURITY;

--
-- Name: order_item_availability_checks; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.order_item_availability_checks ENABLE ROW LEVEL SECURITY;

--
-- Name: order_item_commissions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.order_item_commissions ENABLE ROW LEVEL SECURITY;

--
-- Name: order_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;

--
-- Name: order_status_history; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.order_status_history ENABLE ROW LEVEL SECURITY;

--
-- Name: orders; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

--
-- Name: products; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

--
-- Name: sellers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sellers ENABLE ROW LEVEL SECURITY;

--
-- Name: staff_profiles staff can view own profile and leadership can view all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "staff can view own profile and leadership can view all" ON public.staff_profiles FOR SELECT TO authenticated USING (((user_id = ( SELECT auth.uid() AS uid)) OR public.can_view_all_orders()));


--
-- Name: order_assignment_history staff can view permitted assignments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "staff can view permitted assignments" ON public.order_assignment_history FOR SELECT TO authenticated USING (public.can_access_order(order_id));


--
-- Name: order_item_availability_checks staff can view permitted availability checks; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "staff can view permitted availability checks" ON public.order_item_availability_checks FOR SELECT TO authenticated USING (public.can_access_order(order_id));


--
-- Name: commercial_events staff can view permitted commercial events; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "staff can view permitted commercial events" ON public.commercial_events FOR SELECT TO authenticated USING ((public.can_view_all_orders() OR (seller_id = ( SELECT staff_profiles.seller_id
   FROM public.staff_profiles
  WHERE ((staff_profiles.user_id = ( SELECT auth.uid() AS uid)) AND staff_profiles.active)))));


--
-- Name: order_item_commissions staff can view permitted commissions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "staff can view permitted commissions" ON public.order_item_commissions FOR SELECT TO authenticated USING ((public.can_view_all_orders() OR (seller_id = ( SELECT staff_profiles.seller_id
   FROM public.staff_profiles
  WHERE ((staff_profiles.user_id = ( SELECT auth.uid() AS uid)) AND staff_profiles.active)))));


--
-- Name: order_contact_events staff can view permitted contact events; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "staff can view permitted contact events" ON public.order_contact_events FOR SELECT TO authenticated USING (public.can_access_order(order_id));


--
-- Name: customer_order_acceptances staff can view permitted customer acceptances; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "staff can view permitted customer acceptances" ON public.customer_order_acceptances FOR SELECT TO authenticated USING (public.can_access_order(order_id));


--
-- Name: order_delivery_events staff can view permitted delivery events; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "staff can view permitted delivery events" ON public.order_delivery_events FOR SELECT TO authenticated USING (public.can_access_order(order_id));


--
-- Name: order_customer_delivery_preferences staff can view permitted delivery preferences; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "staff can view permitted delivery preferences" ON public.order_customer_delivery_preferences FOR SELECT TO authenticated USING (public.can_access_order(order_id));


--
-- Name: order_followups staff can view permitted followups; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "staff can view permitted followups" ON public.order_followups FOR SELECT TO authenticated USING (public.can_access_order(order_id));


--
-- Name: order_status_history staff can view permitted history; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "staff can view permitted history" ON public.order_status_history FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.orders o
  WHERE (o.id = order_status_history.order_id))));


--
-- Name: order_items staff can view permitted order items; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "staff can view permitted order items" ON public.order_items FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.orders o
  WHERE (o.id = order_items.order_id))));


--
-- Name: orders staff can view permitted orders; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "staff can view permitted orders" ON public.orders FOR SELECT TO authenticated USING ((public.can_view_all_orders() OR (assigned_seller_id = ( SELECT staff_profiles.seller_id
   FROM public.staff_profiles
  WHERE ((staff_profiles.user_id = ( SELECT auth.uid() AS uid)) AND staff_profiles.active)))));


--
-- Name: store_purchase_events staff can view permitted store purchase events; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "staff can view permitted store purchase events" ON public.store_purchase_events FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.store_purchases purchase
  WHERE ((purchase.id = store_purchase_events.store_purchase_id) AND public.can_access_order(purchase.order_id)))));


--
-- Name: store_purchases staff can view permitted store purchases; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "staff can view permitted store purchases" ON public.store_purchases FOR SELECT TO authenticated USING (public.can_access_order(order_id));


--
-- Name: customer_consents staff can view related consents; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "staff can view related consents" ON public.customer_consents FOR SELECT TO authenticated USING ((public.can_view_all_orders() OR (EXISTS ( SELECT 1
   FROM (public.orders orders
     JOIN public.staff_profiles staff ON ((staff.seller_id = orders.assigned_seller_id)))
  WHERE ((orders.customer_id = customer_consents.customer_id) AND (staff.user_id = ( SELECT auth.uid() AS uid)) AND staff.active)))));


--
-- Name: customers staff can view related customers; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "staff can view related customers" ON public.customers FOR SELECT TO authenticated USING ((public.can_view_all_orders() OR (EXISTS ( SELECT 1
   FROM (public.orders orders
     JOIN public.staff_profiles staff ON ((staff.seller_id = orders.assigned_seller_id)))
  WHERE ((orders.customer_id = customers.id) AND (staff.user_id = ( SELECT auth.uid() AS uid)) AND staff.active)))));


--
-- Name: staff_profiles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.staff_profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: store_purchase_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.store_purchase_events ENABLE ROW LEVEL SECURITY;

--
-- Name: store_purchases; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.store_purchases ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--

\unrestrict EdQNURiObA2qEt5cVuZZIx4qgqde2rzAJRNmtWYODxIdUxPtlj5Q0kF8ulkwrCG

