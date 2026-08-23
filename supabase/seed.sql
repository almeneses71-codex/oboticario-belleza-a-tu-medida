-- Datos exclusivamente locales. No usar --include-seed en producción.
insert into public.campaigns(
  code, display_name, starts_at, ends_at, active
) values (
  'local_validation',
  'Validación Supabase Local',
  '2026-01-01T00:00:00Z',
  '2027-12-31T23:59:59Z',
  true
)
on conflict (code) do update set
  display_name = excluded.display_name,
  starts_at = excluded.starts_at,
  ends_at = excluded.ends_at,
  active = excluded.active;

-- Las reglas de comisión permanecen vacías hasta que el propietario defina
-- porcentajes reales. El sistema nunca asume una comisión predeterminada.

insert into public.sellers(code, display_name, active)
values ('VEN', 'Vendedor de prueba', true)
on conflict (code) do update set display_name = excluded.display_name, active = true;
