begin;

update public.campaigns
set
  starts_at = '2026-08-22 00:00:00 America/Bogota'::timestamptz,
  ends_at = '2026-09-20 00:00:00 America/Bogota'::timestamptz,
  active = true
where code = 'AMOR_AMISTAD_2026';

commit;
