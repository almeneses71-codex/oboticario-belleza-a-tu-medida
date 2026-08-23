create type public.commission_status as enum ('pending', 'earned', 'reversed');

create table public.commission_rules (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid references public.sellers(id),
  item_type public.order_item_type not null,
  rate_basis_points integer not null check (rate_basis_points between 0 and 10000),
  priority smallint not null default 1 check (priority between 1 and 100),
  active boolean not null default true,
  starts_at timestamptz,
  ends_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or starts_at is null or ends_at >= starts_at)
);

create index commission_rules_resolution_idx
  on public.commission_rules(seller_id, item_type, active, priority desc);

create table public.order_item_commissions (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id),
  order_item_id uuid not null unique references public.order_items(id),
  seller_id uuid not null references public.sellers(id),
  commission_rule_id uuid not null references public.commission_rules(id),
  base_cop integer not null check (base_cop >= 0),
  rate_basis_points integer not null check (rate_basis_points between 0 and 10000),
  commission_cop integer generated always as
    (round(base_cop::numeric * rate_basis_points / 10000)) stored,
  status public.commission_status not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index order_item_commissions_seller_idx
  on public.order_item_commissions(seller_id, status, created_at desc);
create index order_item_commissions_order_idx
  on public.order_item_commissions(order_id);

alter table public.commission_rules enable row level security;
alter table public.order_item_commissions enable row level security;

create policy "admins can view commission rules"
on public.commission_rules for select to authenticated
using (public.is_admin());

create policy "staff can view permitted commissions"
on public.order_item_commissions for select to authenticated
using (
  public.is_admin() or seller_id = (
    select seller_id from public.staff_profiles
    where user_id = (select auth.uid()) and active
  )
);

grant select on public.commission_rules, public.order_item_commissions
  to authenticated;

create or replace function public.sync_order_commissions()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
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

revoke all on function public.sync_order_commissions() from public;

create trigger orders_sync_commissions
after update of status on public.orders
for each row execute function public.sync_order_commissions();

create or replace function public.admin_upsert_commission_rule(
  target_rule_id uuid,
  target_seller_code text,
  target_item_type public.order_item_type,
  target_rate_basis_points integer,
  target_priority smallint,
  target_active boolean,
  target_starts_at timestamptz default null,
  target_ends_at timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
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

revoke all on function public.admin_upsert_commission_rule(
  uuid, text, public.order_item_type, integer, smallint, boolean,
  timestamptz, timestamptz
) from public;
grant execute on function public.admin_upsert_commission_rule(
  uuid, text, public.order_item_type, integer, smallint, boolean,
  timestamptz, timestamptz
) to authenticated;
