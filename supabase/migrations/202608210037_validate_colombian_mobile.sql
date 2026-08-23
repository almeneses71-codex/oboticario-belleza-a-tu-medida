create or replace function public.normalize_customer_colombian_mobile()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  digits text;
begin
  digits := regexp_replace(coalesce(new.whatsapp, ''), '[^0-9]', '', 'g');
  if digits ~ '^3[0-9]{9}$' then
    digits := '57' || digits;
  end if;
  if digits !~ '^573[0-9]{9}$' then
    raise exception 'invalid_colombian_mobile';
  end if;
  new.whatsapp := digits;
  return new;
end;
$$;

drop trigger if exists customers_normalize_colombian_mobile
on public.customers;
create trigger customers_normalize_colombian_mobile
before insert or update of whatsapp on public.customers
for each row execute function public.normalize_customer_colombian_mobile();

alter table public.customers
  add constraint customers_colombian_mobile_format
  check (whatsapp ~ '^573[0-9]{9}$') not valid;

comment on column public.customers.whatsapp is
  'Colombian mobile number normalized as 57 + ten national digits. Structural validation does not prove an active WhatsApp account.';
