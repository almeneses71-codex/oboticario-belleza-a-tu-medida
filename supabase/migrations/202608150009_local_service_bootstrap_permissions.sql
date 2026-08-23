-- PostgREST still requires explicit table privileges even though service_role
-- bypasses row-level security. Keep these grants limited to local/bootstrap work.
grant select on table public.sellers to service_role;
grant select, insert, update on table public.staff_profiles to service_role;
grant select on table public.staff_profiles to authenticated;
