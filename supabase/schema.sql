-- =====================================================================
-- SwiftReceipt - Supabase schema (run once in the SQL editor)
-- =====================================================================
create extension if not exists pgcrypto;

-- 1. Organizations -----------------------------------------------------
create table if not exists organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  join_code text unique not null default upper(substr(md5(random()::text), 1, 6)),
  created_at timestamptz default now()
);

-- 2. Staff profiles (1:1 with Supabase Auth users) ---------------------
create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  org_id uuid not null references organizations(id) on delete cascade,
  full_name text not null,
  role text not null default 'waiter' check (role in ('waiter','cashier','manager','owner')),
  created_at timestamptz default now()
);

-- 3. Transactions ------------------------------------------------------
-- NOTE: the reference index is intentionally NOT unique. The blueprint wants
-- duplicates to be accepted and flagged (is_flagged), not rejected.
create table if not exists transactions (
  id uuid primary key default gen_random_uuid(),
  local_id text not null,
  org_id uuid not null references organizations(id) on delete cascade,
  waiter_id uuid not null references profiles(id),
  table_number text,
  amount numeric(12,2) not null check (amount > 0),
  reference_number text not null,
  payment_provider text,
  sender_name text,
  image_url text,                       -- storage path, or 'PURGED_AFTER_AUDIT'
  sync_status text default 'synced',
  is_flagged boolean not null default false,
  flag_resolved boolean not null default false,
  created_at timestamptz default now(),
  unique (org_id, local_id)             -- makes offline retries idempotent
);
create index if not exists idx_tx_ref on transactions (org_id, reference_number);
create index if not exists idx_tx_shift on transactions (waiter_id, created_at);
create index if not exists idx_tx_org_time on transactions (org_id, created_at desc);

-- 4. End-of-day audits -------------------------------------------------
create table if not exists audits (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  closed_by uuid not null references profiles(id),
  business_date date not null,
  digital_total numeric(12,2) not null,
  pos_total numeric(12,2) not null,
  cash_total numeric(12,2) not null,
  difference numeric(12,2) not null,
  note text,
  created_at timestamptz default now()
);

-- Helper functions -----------------------------------------------------
create or replace function my_org() returns uuid
language sql stable security definer set search_path = public as
$$ select org_id from profiles where id = auth.uid() $$;

create or replace function is_manager() returns boolean
language sql stable security definer set search_path = public as
$$ select coalesce((select role in ('manager','owner') from profiles where id = auth.uid()), false) $$;

-- Sign-up hook: creates the organization (owner) or joins one via code ---
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_org uuid;
  v_name text := coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'), ''), split_part(new.email, '@', 1));
begin
  if coalesce(new.raw_user_meta_data->>'org_name', '') <> '' then
    insert into organizations(name) values (new.raw_user_meta_data->>'org_name') returning id into v_org;
    insert into profiles(id, org_id, full_name, role) values (new.id, v_org, v_name, 'owner');
  elsif coalesce(new.raw_user_meta_data->>'join_code', '') <> '' then
    select id into v_org from organizations
      where join_code = upper(trim(new.raw_user_meta_data->>'join_code'));
    if v_org is null then raise exception 'Invalid join code'; end if;
    insert into profiles(id, org_id, full_name, role) values (new.id, v_org, v_name, 'waiter');
  else
    raise exception 'Missing org_name or join_code';
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

create or replace function org_name_for_code(code text) returns text
language sql stable security definer set search_path = public as
$$ select name from organizations where join_code = upper(trim(code)) $$;
grant execute on function org_name_for_code(text) to anon, authenticated;

create or replace function set_staff_role(target uuid, new_role text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from profiles where id = auth.uid() and role = 'owner') then
    raise exception 'Only the owner can change roles';
  end if;
  if new_role not in ('waiter','cashier','manager') then raise exception 'Invalid role'; end if;
  update profiles set role = new_role where id = target and org_id = my_org() and role <> 'owner';
end;
$$;

-- Duplicate-reference flagging engine ------------------------------------
create or replace function tx_before() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.reference_number := upper(trim(new.reference_number));
  if tg_op = 'UPDATE' then
    new.is_flagged := old.is_flagged;
    new.org_id := old.org_id;
    new.waiter_id := old.waiter_id;
    if not is_manager() then new.flag_resolved := old.flag_resolved; end if;
  end if;
  if exists (select 1 from transactions t
             where t.org_id = new.org_id
               and t.reference_number = new.reference_number
               and t.id <> new.id) then
    new.is_flagged := true;
  end if;
  return new;
end;
$$;

create or replace function tx_after() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- flag the earlier row(s) too so the manager sees both sides of the duplicate
  update transactions set is_flagged = true
   where org_id = new.org_id and reference_number = new.reference_number
     and id <> new.id and not is_flagged;
  return null;
end;
$$;

drop trigger if exists trg_tx_before on transactions;
create trigger trg_tx_before before insert or update on transactions
  for each row execute function tx_before();
drop trigger if exists trg_tx_after on transactions;
create trigger trg_tx_after after insert on transactions
  for each row execute function tx_after();

-- Row level security ---------------------------------------------------
alter table organizations enable row level security;
alter table profiles enable row level security;
alter table transactions enable row level security;
alter table audits enable row level security;

create policy org_read on organizations for select to authenticated using (id = my_org());
create policy profiles_read on profiles for select to authenticated using (org_id = my_org());

create policy tx_read on transactions for select to authenticated
  using (org_id = my_org() and (is_manager() or waiter_id = auth.uid()));
create policy tx_insert on transactions for insert to authenticated
  with check (org_id = my_org() and waiter_id = auth.uid());
create policy tx_update on transactions for update to authenticated
  using (org_id = my_org() and (is_manager() or waiter_id = auth.uid()))
  with check (org_id = my_org());

create policy audits_read on audits for select to authenticated
  using (org_id = my_org() and is_manager());
create policy audits_insert on audits for insert to authenticated
  with check (org_id = my_org() and is_manager() and closed_by = auth.uid());

-- Realtime ---------------------------------------------------------------
alter publication supabase_realtime add table transactions;

-- Storage (private bucket, first folder = org id) --------------------------
insert into storage.buckets (id, name, public) values ('receipts', 'receipts', false)
  on conflict (id) do nothing;

create policy receipts_select on storage.objects for select to authenticated
  using (bucket_id = 'receipts' and (storage.foldername(name))[1] = my_org()::text);
create policy receipts_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'receipts' and (storage.foldername(name))[1] = my_org()::text);
create policy receipts_update on storage.objects for update to authenticated
  using (bucket_id = 'receipts' and (storage.foldername(name))[1] = my_org()::text)
  with check (bucket_id = 'receipts' and (storage.foldername(name))[1] = my_org()::text);

-- 7-day image retention ----------------------------------------------------
create or replace function purge_expired_receipt_assets() returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from storage.objects
   where bucket_id = 'receipts'
     and name in (select image_url from transactions
                   where created_at < now() - interval '7 days'
                     and image_url is not null and image_url <> 'PURGED_AFTER_AUDIT');
  update transactions set image_url = 'PURGED_AFTER_AUDIT'
   where created_at < now() - interval '7 days'
     and image_url is not null and image_url <> 'PURGED_AFTER_AUDIT';
end;
$$;

-- Enable pg_cron first: Dashboard > Database > Extensions
create extension if not exists pg_cron;
select cron.schedule('purge_receipts_daily', '0 2 * * *', 'select public.purge_expired_receipt_assets()');
