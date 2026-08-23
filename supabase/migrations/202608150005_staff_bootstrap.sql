insert into public.sellers(code, display_name, active) values
  ('DAR', 'Dario', true),
  ('ANA', 'Ana', true)
on conflict (code) do update set
  display_name = excluded.display_name,
  active = excluded.active;

grant select on public.sellers, public.channels, public.campaigns
  to authenticated;

create policy "authenticated staff can view sellers"
on public.sellers for select to authenticated
using (exists (
  select 1 from public.staff_profiles
  where user_id = (select auth.uid()) and active
));

create policy "authenticated staff can view channels"
on public.channels for select to authenticated
using (exists (
  select 1 from public.staff_profiles
  where user_id = (select auth.uid()) and active
));

create policy "authenticated staff can view campaigns"
on public.campaigns for select to authenticated
using (exists (
  select 1 from public.staff_profiles
  where user_id = (select auth.uid()) and active
));

create policy "staff can view own profile and admins can view all"
on public.staff_profiles for select to authenticated
using (user_id = (select auth.uid()) or public.is_admin());

create or replace function public.bootstrap_first_admin(
  target_user_id uuid,
  target_display_name text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
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

revoke all on function public.bootstrap_first_admin(uuid, text) from public;
grant execute on function public.bootstrap_first_admin(uuid, text)
  to service_role;

create or replace function public.admin_upsert_staff_member(
  target_user_id uuid,
  target_role public.staff_role,
  target_seller_code text,
  target_display_name text,
  target_active boolean default true
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
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

  if target_role = 'seller' then
    select id into resolved_seller_id from public.sellers
      where code = upper(target_seller_code) and active;
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

revoke all on function public.admin_upsert_staff_member(
  uuid, public.staff_role, text, text, boolean
) from public;
grant execute on function public.admin_upsert_staff_member(
  uuid, public.staff_role, text, text, boolean
) to authenticated;
