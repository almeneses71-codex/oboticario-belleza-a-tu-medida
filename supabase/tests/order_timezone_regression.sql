begin;

create temporary table order_timezone_results (
  test text,
  actual text,
  expected text,
  passed boolean
) on commit drop;

insert into order_timezone_results
select
  'function timezone',
  coalesce(array_to_string(proconfig, ','), ''),
  'TimeZone=America/Bogota',
  coalesce(array_to_string(proconfig, ','), '') like '%TimeZone=America/Bogota%'
from pg_proc
where oid = 'public.create_order_request(jsonb)'::regprocedure;

insert into order_timezone_results
select
  'order number uses current_date',
  case when pg_get_functiondef('public.create_order_request(jsonb)'::regprocedure)
    like '%to_char(current_date, ''YYMMDD'')%' then 'present' else 'missing' end,
  'present',
  pg_get_functiondef('public.create_order_request(jsonb)'::regprocedure)
    like '%to_char(current_date, ''YYMMDD'')%';

insert into order_timezone_results
select
  'daily counter uses current_date',
  case when pg_get_functiondef('public.create_order_request(jsonb)'::regprocedure)
    like '%values (current_date, 1)%' then 'present' else 'missing' end,
  'present',
  pg_get_functiondef('public.create_order_request(jsonb)'::regprocedure)
    like '%values (current_date, 1)%';

insert into order_timezone_results
select
  'orders.created_at type and default',
  format_type(a.atttypid, a.atttypmod) || ' / ' || pg_get_expr(d.adbin, d.adrelid),
  'timestamp with time zone / now()',
  format_type(a.atttypid, a.atttypmod) = 'timestamp with time zone'
    and pg_get_expr(d.adbin, d.adrelid) = 'now()'
from pg_attribute a
join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
where a.attrelid = 'public.orders'::regclass and a.attname = 'created_at';

insert into order_timezone_results
select description, actual, expected, actual = expected
from (
  values
    ('Colombia 2026-09-07 23:59',
      to_char('2026-09-08 04:59:00+00'::timestamptz at time zone 'America/Bogota', 'YYYY-MM-DD HH24:MI'),
      '2026-09-07 23:59'),
    ('Colombia 2026-09-08 00:01',
      to_char('2026-09-08 05:01:00+00'::timestamptz at time zone 'America/Bogota', 'YYYY-MM-DD HH24:MI'),
      '2026-09-08 00:01'),
    ('UTC next day remains prior Colombia date',
      to_char('2026-09-08 03:00:00+00'::timestamptz at time zone 'America/Bogota', 'YYYY-MM-DD HH24:MI'),
      '2026-09-07 22:00'),
    ('order suffix at 03:00 UTC',
      to_char('2026-09-08 03:00:00+00'::timestamptz at time zone 'America/Bogota', 'YYMMDD'),
      '260907')
) cases(description, actual, expected);

do $test$
begin
  if exists (
    select 1 from order_timezone_results where passed is distinct from true
  ) then
    raise exception 'Order timezone regression failed: %',
      (select jsonb_agg(to_jsonb(result))
       from order_timezone_results result
       where passed is distinct from true);
  end if;
end
$test$;

select * from order_timezone_results;
rollback;
