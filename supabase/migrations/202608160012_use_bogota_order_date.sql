-- Keep timestamps in timestamptz, but generate the commercial daily sequence
-- with Colombia's calendar date even when PostgreSQL runs in UTC.
alter function public.create_order_request(jsonb)
  set timezone to 'America/Bogota';
