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
    select order_id, count(*) as checked_items,
      bool_and(result = 'available') as all_available
    from latest_checks group by order_id
  ), item_totals as (
    select order_id, count(*) as item_count
    from public.order_items group by order_id
  ), visible as (
    select o.*, min(f.due_at) filter (where f.status = 'open') as next_due_at,
      coalesce(a.checked_items, 0) > 0
        and not coalesce(a.all_available, false) as has_availability_issue,
      coalesce(i.item_count, 0) > 0
        and coalesce(a.checked_items, 0) = coalesce(i.item_count, 0)
        and coalesce(a.all_available, false) as has_complete_availability,
      exists (
        select 1 from public.customer_order_acceptances acceptance
        where acceptance.order_id = o.id
          and acceptance.accepted_total_cop = o.total_cop
      ) as has_current_acceptance
    from public.orders o
    left join public.order_followups f on f.order_id = o.id
    left join availability a on a.order_id = o.id
    left join item_totals i on i.order_id = o.id
    group by o.id, a.checked_items, a.all_available, i.item_count
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
    or (filter_attention = 'contact_pending' and o.status = 'requested')
    or (
      filter_attention = 'availability_pending'
      and o.status = 'contacted'
      and not o.has_complete_availability
    )
    or (
      filter_attention = 'delivery_pending'
      and o.status = 'availability_verified'
      and o.shipping_status = 'pending_quote'
    )
    or (filter_attention = 'availability_issue' and o.has_availability_issue)
    or (
      filter_attention = 'customer_acceptance'
      and o.status = 'availability_verified'
      and o.shipping_status <> 'pending_quote'
      and not o.has_current_acceptance
    )
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
         when o.status = 'requested' then 1
         when o.status = 'contacted' and not o.has_complete_availability then 2
         when o.status = 'availability_verified'
           and o.shipping_status = 'pending_quote' then 3
         when o.status = 'availability_verified'
           and not o.has_current_acceptance then 4
         when o.next_due_at < now() then 5
         when o.next_due_at is not null then 6 else 7 end,
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
    select order_id, count(*) as checked_items,
      bool_and(result = 'available') as all_available
    from latest_checks group by order_id
  ), item_totals as (
    select order_id, count(*) as item_count
    from public.order_items group by order_id
  ), visible as (
    select o.id, o.status, o.shipping_status, o.total_cop,
      min(f.due_at) filter (where f.status = 'open') as next_due_at,
      coalesce(a.checked_items, 0) > 0
        and not coalesce(a.all_available, false) as has_availability_issue,
      coalesce(i.item_count, 0) > 0
        and coalesce(a.checked_items, 0) = coalesce(i.item_count, 0)
        and coalesce(a.all_available, false) as has_complete_availability,
      exists (
        select 1 from public.customer_order_acceptances acceptance
        where acceptance.order_id = o.id
          and acceptance.accepted_total_cop = o.total_cop
      ) as has_current_acceptance
    from public.orders o
    left join public.order_followups f on f.order_id = o.id
    left join availability a on a.order_id = o.id
    left join item_totals i on i.order_id = o.id
    group by o.id, a.checked_items, a.all_available, i.item_count
  ), classified as (
    select case
      when next_due_at < now() then 'overdue'
      when (next_due_at at time zone 'America/Bogota')::date
        = (now() at time zone 'America/Bogota')::date then 'today'
      when next_due_at is not null then 'upcoming'
      else 'none'
    end as attention from visible
    union all select 'contact_pending' from visible where status = 'requested'
    union all select 'availability_pending' from visible
      where status = 'contacted' and not has_complete_availability
    union all select 'delivery_pending' from visible
      where status = 'availability_verified' and shipping_status = 'pending_quote'
    union all select 'availability_issue' from visible where has_availability_issue
    union all select 'customer_acceptance' from visible
      where status = 'availability_verified'
        and shipping_status <> 'pending_quote'
        and not has_current_acceptance
  )
  select attention, count(*) from classified group by attention
  order by attention;
$$;

revoke all on function public.staff_attention_counts() from public;
grant execute on function public.staff_attention_counts() to authenticated;
