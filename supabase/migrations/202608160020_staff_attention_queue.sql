drop function public.search_staff_order_ids(
  text, public.order_status, text, timestamptz, integer, integer
);

create or replace function public.search_staff_order_ids(
  search_text text default null,
  filter_status public.order_status default null,
  filter_seller_name text default null,
  created_after timestamptz default null,
  filter_attention text default null,
  page_offset integer default 0,
  page_limit integer default 25
)
returns table(order_id uuid, total_count bigint)
language sql stable security invoker
set search_path = public, pg_temp as $$
  with visible as (
    select o.*, min(f.due_at) filter (where f.status = 'open') as next_due_at
    from public.orders o
    left join public.order_followups f on f.order_id = o.id
    group by o.id
  )
  select o.id, count(*) over ()
  from visible o
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
  and (
    nullif(trim(filter_attention), '') is null
    or (filter_attention = 'overdue' and o.next_due_at < now())
    or (
      filter_attention = 'today'
      and o.next_due_at >= now()
      and (o.next_due_at at time zone 'America/Bogota')::date
        = (now() at time zone 'America/Bogota')::date
    )
    or (
      filter_attention = 'upcoming'
      and (o.next_due_at at time zone 'America/Bogota')::date
        > (now() at time zone 'America/Bogota')::date
    )
    or (filter_attention = 'none' and o.next_due_at is null)
  )
  order by
    case when o.next_due_at < now() then 0
         when o.next_due_at is not null then 1 else 2 end,
    o.next_due_at nulls last,
    o.created_at desc, o.id desc
  offset greatest(page_offset, 0)
  limit least(greatest(page_limit, 1), 100);
$$;
revoke all on function public.search_staff_order_ids(
  text, public.order_status, text, timestamptz, text, integer, integer
) from public;
grant execute on function public.search_staff_order_ids(
  text, public.order_status, text, timestamptz, text, integer, integer
) to authenticated;

create or replace function public.staff_attention_counts()
returns table(attention text, total_count bigint)
language sql stable security invoker
set search_path = public, pg_temp as $$
  with visible as (
    select o.id, min(f.due_at) filter (where f.status = 'open') as next_due_at
    from public.orders o
    left join public.order_followups f on f.order_id = o.id
    group by o.id
  ), classified as (
    select case
      when next_due_at < now() then 'overdue'
      when (next_due_at at time zone 'America/Bogota')::date
        = (now() at time zone 'America/Bogota')::date then 'today'
      when next_due_at is not null then 'upcoming'
      else 'none'
    end as attention
    from visible
  )
  select attention, count(*) from classified group by attention
  order by attention;
$$;
revoke all on function public.staff_attention_counts() from public;
grant execute on function public.staff_attention_counts() to authenticated;
