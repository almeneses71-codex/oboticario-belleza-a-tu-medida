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
set search_path = public, pg_temp
as $$
  select o.id, count(*) over ()
  from public.orders o
  join public.customers c on c.id = o.customer_id
  join public.sellers s on s.id = o.seller_id
  where (
    nullif(trim(search_text), '') is null
    or o.order_number ilike '%' || trim(search_text) || '%'
    or c.name ilike '%' || trim(search_text) || '%'
    or s.display_name ilike '%' || trim(search_text) || '%'
  )
  and (filter_status is null or o.status = filter_status)
  and (
    nullif(trim(filter_seller_name), '') is null
    or s.display_name = trim(filter_seller_name)
  )
  and (created_after is null or o.created_at >= created_after)
  order by o.created_at desc, o.id desc
  offset greatest(page_offset, 0)
  limit least(greatest(page_limit, 1), 100);
$$;

revoke all on function public.search_staff_order_ids(
  text, public.order_status, text, timestamptz, integer, integer
) from public;
grant execute on function public.search_staff_order_ids(
  text, public.order_status, text, timestamptz, integer, integer
) to authenticated;
