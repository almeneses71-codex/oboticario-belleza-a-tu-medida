begin;

insert into public.sellers(code, display_name, active)
values ('WEB', 'Canal web · por asignar', true)
on conflict (code) do update set
  display_name = excluded.display_name,
  active = excluded.active;

create or replace function public.set_initial_order_assignment()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
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

comment on function public.set_initial_order_assignment() is
  'Keeps origin seller separate from operational assignment. Direct public orders enter the WEB queue for later assignment.';

commit;
