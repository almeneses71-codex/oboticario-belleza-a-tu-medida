alter table public.orders
  add column assigned_seller_id uuid references public.sellers(id);

update public.orders set assigned_seller_id = seller_id
where assigned_seller_id is null;
alter table public.orders alter column assigned_seller_id set not null;
create index orders_assigned_seller_idx
  on public.orders(assigned_seller_id, created_at desc);

create table public.order_assignment_history (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  previous_seller_id uuid references public.sellers(id),
  new_seller_id uuid not null references public.sellers(id),
  previous_seller_name text,
  new_seller_name text not null,
  changed_by uuid references auth.users(id),
  actor_role public.staff_role,
  actor_display_name text,
  reason text not null check (length(trim(reason)) >= 5),
  created_at timestamptz not null default now()
);
create index order_assignment_history_order_idx
  on public.order_assignment_history(order_id, created_at);
alter table public.order_assignment_history enable row level security;

insert into public.order_assignment_history(
  order_id, new_seller_id, new_seller_name, reason
)
select o.id, o.assigned_seller_id, s.display_name, 'Asignación inicial del pedido.'
from public.orders o
join public.sellers s on s.id = o.assigned_seller_id;

create or replace function public.set_initial_order_assignment()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $$
begin
  new.assigned_seller_id := coalesce(new.assigned_seller_id, new.seller_id);
  return new;
end;
$$;
create trigger set_initial_order_assignment
before insert on public.orders
for each row execute function public.set_initial_order_assignment();

create or replace function public.log_initial_order_assignment()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $$
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
create trigger log_initial_order_assignment
after insert on public.orders
for each row execute function public.log_initial_order_assignment();

drop policy "staff can view permitted orders" on public.orders;
create policy "staff can view permitted orders" on public.orders
for select to authenticated using (
  public.can_view_all_orders() or assigned_seller_id = (
    select seller_id from public.staff_profiles
    where user_id = (select auth.uid()) and active
  )
);

drop policy "staff can view related customers" on public.customers;
create policy "staff can view related customers" on public.customers
for select to authenticated using (
  public.can_view_all_orders() or exists (
    select 1 from public.orders orders
    join public.staff_profiles staff
      on staff.seller_id = orders.assigned_seller_id
    where orders.customer_id = customers.id
      and staff.user_id = (select auth.uid()) and staff.active
  )
);

drop policy "staff can view related consents" on public.customer_consents;
create policy "staff can view related consents" on public.customer_consents
for select to authenticated using (
  public.can_view_all_orders() or exists (
    select 1 from public.orders orders
    join public.staff_profiles staff
      on staff.seller_id = orders.assigned_seller_id
    where orders.customer_id = customer_consents.customer_id
      and staff.user_id = (select auth.uid()) and staff.active
  )
);

create or replace function public.can_access_order(target_order_id uuid)
returns boolean language sql stable security definer
set search_path = public, pg_temp as $$
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

create policy "staff can view permitted assignments"
on public.order_assignment_history for select to authenticated
using (public.can_access_order(order_id));
grant select on public.order_assignment_history to authenticated;

create or replace function public.assign_order_responsible(
  target_order_id uuid,
  target_seller_id uuid,
  assignment_reason text
)
returns uuid language plpgsql security definer
set search_path = public, pg_temp as $$
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
revoke all on function public.assign_order_responsible(uuid, uuid, text) from public;
grant execute on function public.assign_order_responsible(uuid, uuid, text)
  to authenticated;

create or replace function public.list_assignable_sellers()
returns table(id uuid, code text, display_name text)
language plpgsql stable security definer
set search_path = public, pg_temp as $$
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
revoke all on function public.list_assignable_sellers() from public;
grant execute on function public.list_assignable_sellers() to authenticated;

create or replace function public.search_staff_order_ids(
  search_text text default null,
  filter_status public.order_status default null,
  filter_seller_name text default null,
  created_after timestamptz default null,
  page_offset integer default 0,
  page_limit integer default 25
)
returns table(order_id uuid, total_count bigint)
language sql stable security invoker
set search_path = public, pg_temp as $$
  select o.id, count(*) over ()
  from public.orders o
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
  order by o.created_at desc, o.id desc
  offset greatest(page_offset, 0)
  limit least(greatest(page_limit, 1), 100);
$$;
