create type public.followup_status as enum ('open', 'completed', 'cancelled');

create table public.order_followups (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  note text not null check (length(trim(note)) between 5 and 500),
  due_at timestamptz not null,
  status public.followup_status not null default 'open',
  created_by uuid references auth.users(id),
  creator_role public.staff_role,
  creator_display_name text,
  created_at timestamptz not null default now(),
  completed_by uuid references auth.users(id),
  completed_by_name text,
  completed_at timestamptz,
  completion_note text check (
    completion_note is null or length(trim(completion_note)) between 5 and 500
  ),
  check (
    (status = 'completed' and completed_at is not null)
    or (status <> 'completed' and completed_at is null)
  )
);
create index order_followups_order_idx
  on public.order_followups(order_id, due_at desc);
create index order_followups_open_due_idx
  on public.order_followups(due_at) where status = 'open';
alter table public.order_followups enable row level security;

create policy "staff can view permitted followups"
on public.order_followups for select to authenticated
using (public.can_access_order(order_id));
grant select on public.order_followups to authenticated;

create or replace function public.create_order_followup(
  target_order_id uuid,
  followup_note text,
  followup_due_at timestamptz
)
returns uuid language plpgsql security definer
set search_path = public, pg_temp as $$
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
revoke all on function public.create_order_followup(uuid, text, timestamptz) from public;
grant execute on function public.create_order_followup(uuid, text, timestamptz)
  to authenticated;

create or replace function public.complete_order_followup(
  target_followup_id uuid,
  result_note text
)
returns uuid language plpgsql security definer
set search_path = public, pg_temp as $$
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
revoke all on function public.complete_order_followup(uuid, text) from public;
grant execute on function public.complete_order_followup(uuid, text)
  to authenticated;
