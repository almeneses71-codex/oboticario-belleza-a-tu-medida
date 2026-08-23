begin;
create extension if not exists pgtap with schema extensions;
select plan(41);

select has_table('public', 'products', 'products table exists');
select has_table('public', 'orders', 'orders table exists');
select has_table('public', 'order_items', 'order items table exists');
select has_table('public', 'cross_sell_relations', 'cross-sell table exists');
select has_table('public', 'staff_profiles', 'staff profiles table exists');
select has_table('public', 'commission_rules', 'commission rules table exists');
select has_table('public', 'order_item_commissions', 'commission ledger exists');
select has_table('public', 'commercial_kits', 'commercial kits table exists');
select has_column('public', 'orders', 'journey_id', 'orders keep anonymous journey');
select has_column('public', 'orders', 'shipping_cop', 'shipping stays separate');
select has_column('public', 'order_items', 'item_type', 'item type is traceable');
select has_column('public', 'products', 'catalog_characteristics', 'catalog stores five official characteristics');
select has_column('public', 'products', 'official_url', 'catalog stores official product URL');
select has_column('public', 'products', 'catalog_status', 'catalog stores monthly status');
select has_trigger(
  'public',
  'customers',
  'customers_normalize_colombian_mobile',
  'customer mobile validation is enforced in PostgreSQL'
);
select results_eq(
  $$select count(*)::bigint
    from pg_enum enum_value
    join pg_type enum_type on enum_type.oid = enum_value.enumtypid
    where enum_type.typname = 'order_item_type'
      and enum_value.enumlabel = 'other'$$,
  array[1::bigint],
  'order items support a separate other product type'
);

select results_eq(
  'select count(*)::bigint from public.products',
  array[491::bigint],
  'operational catalog has 466 August products plus preserved legacy records'
);
select results_eq(
  $$select count(*)::bigint from public.products
    where catalog_month = 'Agosto' and catalog_year = 2026$$,
  array[466::bigint],
  'August snapshot contains every official master product'
);
select results_eq(
  $$select count(*)::bigint from public.products
    where catalog_month = 'Agosto' and catalog_year = 2026 and available$$,
  array[412::bigint],
  'only 412 August products are currently available'
);
select results_eq(
  $$select count(*)::bigint from public.products
    where id like 'CAT-%' and eligible$$,
  array[0::bigint],
  'new catalog products cannot enter recommendations before classification'
);
select results_eq(
  'select count(*)::bigint from public.cross_sell_relations',
  array[32::bigint],
  'cross-sell matrix has 32 verified relations'
);
select results_eq(
  'select count(*)::bigint from public.sellers where code in (''DAR'', ''ANA'')',
  array[2::bigint],
  'test seller identities exist'
);
select results_eq(
  'select count(*)::bigint from public.commission_rules',
  array[0::bigint],
  'no commission percentage is invented'
);
select ok(
  has_table_privilege('service_role', 'public.sellers', 'select'),
  'service role can resolve sellers during controlled bootstrap'
);
select ok(
  has_table_privilege('service_role', 'public.staff_profiles', 'insert, update'),
  'service role can create local staff profiles'
);
select ok(
  has_table_privilege('authenticated', 'public.staff_profiles', 'select'),
  'authenticated staff can read profiles subject to RLS'
);
select results_eq(
  $$
    select count(*)::bigint
    from pg_proc
    where oid = 'public.create_order_request(jsonb)'::regprocedure
      and array_to_string(proconfig, ',') ilike '%timezone=America/Bogota%'
  $$,
  array[1::bigint],
  'order numbering uses the Colombia business date'
);
select has_column('public', 'order_status_history', 'previous_status', 'history stores previous status');
select has_column('public', 'order_status_history', 'actor_role', 'history snapshots actor role');
select has_column('public', 'order_status_history', 'actor_display_name', 'history snapshots actor name');
select has_column('public', 'orders', 'assigned_seller_id', 'orders separate operational responsibility');
select has_table('public', 'order_assignment_history', 'assignment history exists');
select has_table('public', 'order_followups', 'operational followups exist');
select results_eq(
  $$select count(*)::bigint from unnest(enum_range(null::public.staff_role)) role where role::text in ('admin','owner','manager','seller')$$,
  array[4::bigint],
  'all four staff roles exist'
);
select results_eq(
  $$select count(*)::bigint from pg_proc where proname = 'search_staff_order_ids' and pronamespace = 'public'::regnamespace$$,
  array[1::bigint],
  'staff order search is installed once'
);
select results_eq(
  $$select count(*)::bigint from pg_proc where proname = 'staff_order_status_counts' and pronamespace = 'public'::regnamespace$$,
  array[1::bigint],
  'staff status count is installed once'
);
select results_eq(
  $$select count(*)::bigint from pg_proc where proname = 'staff_attention_counts' and pronamespace = 'public'::regnamespace$$,
  array[1::bigint],
  'staff attention counts are installed once'
);
select results_eq(
  $$select count(*)::bigint from pg_proc where proname = 'assign_order_responsible' and pronamespace = 'public'::regnamespace$$,
  array[1::bigint],
  'controlled assignment function is installed once'
);
select results_eq(
  $$select count(*)::bigint from pg_proc where proname = 'list_assignable_sellers' and pronamespace = 'public'::regnamespace$$,
  array[1::bigint],
  'assignable seller function is installed once'
);
select results_eq(
  $$select count(*)::bigint from pg_proc where proname = 'create_order_followup' and pronamespace = 'public'::regnamespace$$,
  array[1::bigint],
  'controlled followup creation is installed once'
);
select results_eq(
  $$select count(*)::bigint from pg_proc where proname = 'complete_order_followup' and pronamespace = 'public'::regnamespace$$,
  array[1::bigint],
  'controlled followup completion is installed once'
);

select * from finish();
rollback;
