-- =====================================================================
-- Migration: Platform Configuration & Support Contact Table
-- Stores support phone, telegram handle, and default bot token
-- =====================================================================

create table if not exists public.platform_config (
  key text primary key,
  value text not null,
  updated_at timestamptz default now()
);

-- Prepopulate defaults
insert into public.platform_config (key, value) values
  ('support_phone', '0996246990'),
  ('support_telegram', '@jonas_wjohn'),
  ('platform_bot_token', '')
on conflict (key) do nothing;

-- RLS: Authenticated users can read support info, only super admins can update
alter table public.platform_config enable row level security;

drop policy if exists config_read on public.platform_config;
create policy config_read on public.platform_config 
  for select to authenticated 
  using (true);

drop policy if exists config_admin on public.platform_config;
create policy config_admin on public.platform_config 
  for all to authenticated 
  using (is_super_admin()) 
  with check (is_super_admin());
