create table public.commercial_kits (
  kit_product_id text primary key references public.products(id),
  official_sku boolean not null default false,
  active boolean not null default false,
  starts_at timestamptz,
  ends_at timestamptz,
  campaign_id uuid references public.campaigns(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (not active or official_sku),
  check (ends_at is null or starts_at is null or ends_at >= starts_at)
);

create table public.commercial_kit_components (
  kit_product_id text not null references public.commercial_kits(kit_product_id)
    on delete cascade,
  component_product_id text not null references public.products(id),
  quantity integer not null default 1 check (quantity between 1 and 20),
  primary key (kit_product_id, component_product_id),
  check (kit_product_id <> component_product_id)
);

alter table public.commercial_kits enable row level security;
alter table public.commercial_kit_components enable row level security;

create policy "current official kits are public"
on public.commercial_kits for select to anon, authenticated
using (
  official_sku and active
  and (starts_at is null or starts_at <= now())
  and (ends_at is null or ends_at >= now())
);

create policy "current official kit components are public"
on public.commercial_kit_components for select to anon, authenticated
using (exists (
  select 1 from public.commercial_kits kit
  where kit.kit_product_id = commercial_kit_components.kit_product_id
));

create policy "admins can view every kit definition"
on public.commercial_kits for select to authenticated
using (public.is_admin());

create policy "admins can view every kit component"
on public.commercial_kit_components for select to authenticated
using (public.is_admin());

grant select on public.commercial_kits, public.commercial_kit_components
  to anon, authenticated;

-- No kit is activated here. The four current KIT records remain suggestions,
-- not official SKUs. Activation requires verified component product IDs and
-- an explicit official SKU; the order RPC continues rejecting kits meanwhile.
