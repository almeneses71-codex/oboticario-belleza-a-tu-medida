create type public.availability_result as enum (
  'available', 'partial', 'unavailable'
);

create table public.order_item_availability_checks (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  order_item_id uuid not null references public.order_items(id) on delete cascade,
  result public.availability_result not null,
  note text check (note is null or length(trim(note)) between 5 and 500),
  checked_by uuid not null references auth.users(id),
  checker_role public.staff_role not null,
  checker_display_name text not null,
  checked_at timestamptz not null default now()
);

create index order_item_availability_checks_latest_idx
  on public.order_item_availability_checks(order_item_id, checked_at desc);

alter table public.order_item_availability_checks enable row level security;
create policy "staff can view permitted availability checks"
on public.order_item_availability_checks for select to authenticated
using (public.can_access_order(order_id));
grant select on public.order_item_availability_checks to authenticated;

create or replace function public.verify_order_availability(
  target_order_id uuid,
  item_results jsonb,
  verification_note text default null
)
returns integer language plpgsql security definer
set search_path = public, pg_temp as $$
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
revoke all on function public.verify_order_availability(uuid, jsonb, text) from public;
grant execute on function public.verify_order_availability(uuid, jsonb, text)
  to authenticated;

create or replace function public.order_has_verified_availability(target_order_id uuid)
returns boolean language sql stable security definer
set search_path = public, pg_temp as $$
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
revoke all on function public.order_has_verified_availability(uuid) from public;
grant execute on function public.order_has_verified_availability(uuid) to authenticated;

create or replace function public.guard_verified_availability_transition()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $$
begin
  if new.status = 'availability_verified'
     and old.status is distinct from new.status
     and not public.order_has_verified_availability(new.id) then
    raise exception 'availability_verification_required';
  end if;
  return new;
end;
$$;

create trigger orders_require_verified_availability
before update of status on public.orders
for each row execute function public.guard_verified_availability_transition();
