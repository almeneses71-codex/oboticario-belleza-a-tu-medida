create table public.order_contact_events (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  channel text not null check (channel in ('whatsapp')),
  actor_user_id uuid not null references auth.users(id),
  actor_role public.staff_role not null,
  actor_display_name text not null,
  created_at timestamptz not null default now()
);

create index order_contact_events_order_idx
  on public.order_contact_events(order_id, created_at desc);

alter table public.order_contact_events enable row level security;

create policy "staff can view permitted contact events"
on public.order_contact_events for select to authenticated
using (public.can_access_order(order_id));

grant select on public.order_contact_events to authenticated;

create or replace function public.log_order_contact(
  target_order_id uuid,
  contact_channel text default 'whatsapp'
)
returns uuid language plpgsql security definer
set search_path = public, pg_temp as $$
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

revoke all on function public.log_order_contact(uuid, text) from public;
grant execute on function public.log_order_contact(uuid, text) to authenticated;
