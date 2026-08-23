create or replace function public.staff_order_status_counts()
returns table(status public.order_status, total_count bigint)
language sql stable security invoker
set search_path = public, pg_temp
as $$
  select o.status, count(*)
  from public.orders o
  group by o.status
  order by o.status;
$$;

revoke all on function public.staff_order_status_counts() from public;
grant execute on function public.staff_order_status_counts() to authenticated;
