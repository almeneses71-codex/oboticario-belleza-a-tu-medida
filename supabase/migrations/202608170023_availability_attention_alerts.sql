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
  with latest_checks as (
    select distinct on (check_row.order_item_id)
      check_row.order_id, check_row.order_item_id, check_row.result
    from public.order_item_availability_checks check_row
    order by check_row.order_item_id, check_row.checked_at desc
  ), availability as (
    select order_id, bool_or(result <> 'available') as has_issue
    from latest_checks group by order_id
  ), visible as (
    select o.*, min(f.due_at) filter (where f.status = 'open') as next_due_at,
      coalesce(a.has_issue, false) as has_availability_issue
    from public.orders o
    left join public.order_followups f on f.order_id = o.id
    left join availability a on a.order_id = o.id
    group by o.id, a.has_issue
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
    or (filter_attention = 'availability_issue' and o.has_availability_issue)
    or (filter_attention = 'overdue' and o.next_due_at < now())
    or (
      filter_attention = 'today' and o.next_due_at >= now()
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
    case when o.has_availability_issue then 0
         when o.next_due_at < now() then 1
         when o.next_due_at is not null then 2 else 3 end,
    o.next_due_at nulls last, o.created_at desc, o.id desc
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
  with latest_checks as (
    select distinct on (check_row.order_item_id)
      check_row.order_id, check_row.order_item_id, check_row.result
    from public.order_item_availability_checks check_row
    order by check_row.order_item_id, check_row.checked_at desc
  ), availability as (
    select order_id, bool_or(result <> 'available') as has_issue
    from latest_checks group by order_id
  ), visible as (
    select o.id, min(f.due_at) filter (where f.status = 'open') as next_due_at,
      coalesce(a.has_issue, false) as has_availability_issue
    from public.orders o
    left join public.order_followups f on f.order_id = o.id
    left join availability a on a.order_id = o.id
    group by o.id, a.has_issue
  ), classified as (
    select case
      when next_due_at < now() then 'overdue'
      when (next_due_at at time zone 'America/Bogota')::date
        = (now() at time zone 'America/Bogota')::date then 'today'
      when next_due_at is not null then 'upcoming'
      else 'none'
    end as attention from visible
    union all
    select 'availability_issue' from visible where has_availability_issue
  )
  select attention, count(*) from classified group by attention
  order by attention;
$$;

revoke all on function public.staff_attention_counts() from public;
grant execute on function public.staff_attention_counts() to authenticated;
