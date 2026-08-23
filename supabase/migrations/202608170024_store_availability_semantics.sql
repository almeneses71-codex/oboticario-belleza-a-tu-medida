alter table public.order_item_availability_checks
  add column verification_method text not null default 'manual_store_check'
  check (verification_method = 'manual_store_check');

comment on table public.order_item_availability_checks is
  'Manual checks of availability for purchase from the external store. '
  'This table does not represent owned inventory or physical stock.';

comment on column public.order_item_availability_checks.result is
  'Latest availability reported for purchasing the requested quantity from the store.';

comment on column public.order_items.quantity is
  'Quantity requested by the customer; never an owned-stock balance.';

comment on column public.products.available is
  'Catalog eligibility for recommendation, not physical inventory owned by the seller.';
