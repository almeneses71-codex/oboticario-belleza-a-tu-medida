create table public.feature_flags (
  key text primary key,
  enabled boolean not null default false,
  description text not null,
  updated_at timestamptz not null default now()
);

alter table public.feature_flags enable row level security;

insert into public.feature_flags(key, enabled, description) values (
  'payments', false,
  'Payment verification and payment-state transitions are disabled until a reviewed payment module is deployed.'
);

create or replace function public.feature_enabled(feature_key text)
returns boolean language sql stable security definer
set search_path = public, pg_temp as $$
  select coalesce(
    (select enabled from public.feature_flags where key = feature_key),
    false
  );
$$;

revoke all on function public.feature_enabled(text) from public;

create or replace function public.guard_disabled_order_features()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $$
begin
  if new.status is distinct from old.status
     and new.status in ('pending_payment', 'payment_under_review', 'paid')
     and not public.feature_enabled('payments') then
    raise exception 'payments_feature_disabled';
  end if;
  return new;
end;
$$;

create trigger orders_guard_disabled_features
before update of status on public.orders
for each row execute function public.guard_disabled_order_features();

comment on table public.feature_flags is
  'Server-side release gates. No authenticated role receives direct write access.';

comment on function public.guard_disabled_order_features() is
  'Blocks payment lifecycle states until payments are enabled by a reviewed migration.';
