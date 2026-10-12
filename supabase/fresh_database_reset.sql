-- =====================================================================
-- Mela: COMPLETE FRESH START (Factory Reset & Setup Super Admin)
-- Run this in your Supabase SQL Editor.
-- =====================================================================

-- 1. PURGE ALL EXISTING DATA, USERS, PROFILES & BUSINESSES
truncate table public.bank_credits cascade;
truncate table public.audits cascade;
truncate table public.transactions cascade;
truncate table public.profiles cascade;
truncate table public.organizations cascade;

-- Delete ALL existing auth users to eliminate corrupted or mixed accounts
delete from auth.users;


-- 2. ENSURE EXTENSIONS & SCHEMA CONSTRAINTS ARE PRESENT
create extension if not exists pgcrypto schema extensions;

alter table public.organizations 
  add column if not exists status text not null default 'active' 
  check (status in ('active', 'suspended', 'trial', 'expired')),
  add column if not exists subscription_fee numeric(10,2) default 1000.00,
  add column if not exists billing_cycle text default 'monthly',
  add column if not exists expires_at timestamptz default (now() + interval '30 days'),
  add column if not exists contact_phone text,
  add column if not exists contact_person text,
  add column if not exists notes text;

alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check 
  check (role in ('waiter', 'cashier', 'manager', 'owner', 'super_admin'));


-- 3. CORE HELPER FUNCTIONS
create or replace function public.is_super_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select role = 'super_admin' from public.profiles where id = auth.uid()), false);
$$;

create or replace function public.is_org_active(p_org_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.organizations 
    where id = p_org_id 
      and status = 'active'
      and (expires_at is null or expires_at >= now())
  );
$$;

create or replace function public.my_org() returns uuid
language sql stable security definer set search_path = public as $$
  select org_id from public.profiles where id = auth.uid();
$$;

create or replace function public.is_manager() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select role in ('manager','owner','super_admin') from public.profiles where id = auth.uid()), false);
$$;


-- 4. CLEAN AUTH TRIGGER FOR REGISTRATION / STAFF JOIN
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_org uuid;
  v_name text := coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'), ''), split_part(new.email, '@', 1));
  v_role text := coalesce(nullif(trim(new.raw_user_meta_data->>'role'), ''), 'waiter');
begin
  -- If org_id is explicitly passed in metadata (e.g. provisioned by Super Admin)
  if coalesce(new.raw_user_meta_data->>'org_id', '') <> '' then
    v_org := (new.raw_user_meta_data->>'org_id')::uuid;
    insert into public.profiles(id, org_id, full_name, role)
    values (new.id, v_org, v_name, v_role)
    on conflict (id) do update set org_id = v_org, full_name = v_name, role = v_role;

  -- Staff joining using team join code
  elsif coalesce(new.raw_user_meta_data->>'join_code', '') <> '' then
    select id into v_org from public.organizations
      where join_code = upper(trim(new.raw_user_meta_data->>'join_code'));
    if v_org is null then raise exception 'Invalid join code'; end if;
    insert into public.profiles(id, org_id, full_name, role)
    values (new.id, v_org, v_name, 'waiter')
    on conflict (id) do update set org_id = v_org, full_name = v_name, role = 'waiter';

  -- If it is marked as super_admin
  elsif v_role = 'super_admin' then
    select id into v_org from public.organizations where name in ('Mela Master Admin', 'SwiftReceipt Master Admin') limit 1;
    insert into public.profiles(id, org_id, full_name, role)
    values (new.id, v_org, v_name, 'super_admin')
    on conflict (id) do update set role = 'super_admin';

  else
    -- Fallback
    select id into v_org from public.organizations limit 1;
    if v_org is not null then
      insert into public.profiles(id, org_id, full_name, role)
      values (new.id, v_org, v_name, v_role)
      on conflict (id) do nothing;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();


-- 5. DROP ALL PREVIOUS super_admin FUNCTION OVERLOADS (Eliminates ambiguity)
do $$
declare
  r record;
begin
  for r in (
    select p.oid::regprocedure as func_signature
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname like 'super_admin_%'
  ) loop
    execute 'drop function if exists ' || r.func_signature || ' cascade;';
  end loop;
end $$;

-- SUPER ADMIN RPC: PROVISION NEW BUSINESS & OWNER
create or replace function public.super_admin_create_business(
  p_business_name text,
  p_owner_email text,
  p_owner_name text,
  p_temporary_password text default 'Pass1234',
  p_contact_phone text default null,
  p_subscription_fee numeric default 1000.00,
  p_duration_days integer default 30,
  p_notes text default null,
  p_owner_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_org_id uuid;
  v_user_id uuid := p_owner_id;
  v_join_code text;
  v_expires_at timestamptz;
begin
  if not is_super_admin() then
    raise exception 'Access denied: Only Super Admin can register new businesses.';
  end if;

  v_expires_at := now() + (p_duration_days || ' days')::interval;

  -- 1. Create Organization (generates unique join_code automatically)
  insert into public.organizations (name, status, subscription_fee, expires_at, contact_phone, contact_person, notes)
  values (trim(p_business_name), 'active', p_subscription_fee, v_expires_at, p_contact_phone, p_owner_name, p_notes)
  returning id, join_code into v_org_id, v_join_code;

  -- 2. Resolve owner if already created via GoTrue Auth
  if v_user_id is null then
    select id into v_user_id from auth.users where email = lower(trim(p_owner_email)) limit 1;
  end if;

  if v_user_id is null then
    insert into auth.users (
      instance_id,
      id,
      aud,
      role,
      email,
      encrypted_password,
      email_confirmed_at,
      raw_app_meta_data,
      raw_user_meta_data,
      created_at,
      updated_at
    )
    values (
      '00000000-0000-0000-0000-000000000000',
      gen_random_uuid(),
      'authenticated',
      'authenticated',
      lower(trim(p_owner_email)),
      extensions.crypt(p_temporary_password, extensions.gen_salt('bf')),
      now(),
      '{"provider":"email","providers":["email"]}',
      jsonb_build_object(
        'full_name', p_owner_name,
        'org_id', v_org_id::text,
        'org_name', p_business_name,
        'role', 'owner'
      ),
      now(),
      now()
    )
    returning id into v_user_id;

    insert into auth.identities (
      id,
      user_id,
      identity_data,
      provider,
      provider_id,
      last_sign_in_at,
      created_at,
      updated_at
    )
    values (
      gen_random_uuid(),
      v_user_id,
      jsonb_build_object('sub', v_user_id::text, 'email', lower(trim(p_owner_email))),
      'email',
      lower(trim(p_owner_email)),
      now(),
      now(),
      now()
    )
    on conflict (provider, provider_id) do update set
      user_id = excluded.user_id,
      identity_data = excluded.identity_data,
      updated_at = now();
  end if;

  -- 3. Link profile to the organization
  insert into public.profiles (id, org_id, full_name, role)
  values (v_user_id, v_org_id, p_owner_name, 'owner')
  on conflict (id) do update set org_id = v_org_id, full_name = p_owner_name, role = 'owner';

  return jsonb_build_object(
    'success', true,
    'org_id', v_org_id,
    'business_name', p_business_name,
    'join_code', v_join_code,
    'owner_id', v_user_id,
    'owner_email', p_owner_email,
    'expires_at', v_expires_at
  );
end;
$$;


-- 6. SUPER ADMIN RPC: EDIT, DELETE, STATUS, OVERVIEW
create or replace function public.super_admin_edit_business(
  p_org_id uuid,
  p_business_name text,
  p_contact_person text default null,
  p_contact_phone text default null,
  p_subscription_fee numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_super_admin() then raise exception 'Access denied.'; end if;

  update public.organizations
  set name = coalesce(nullif(trim(p_business_name), ''), name),
      contact_person = coalesce(p_contact_person, contact_person),
      contact_phone = coalesce(p_contact_phone, contact_phone),
      subscription_fee = coalesce(p_subscription_fee, subscription_fee)
  where id = p_org_id;

  return jsonb_build_object('success', true, 'org_id', p_org_id);
end;
$$;

create or replace function public.super_admin_delete_business(p_org_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_owner_ids uuid[];
begin
  if not is_super_admin() then raise exception 'Access denied.'; end if;

  select array_agg(id) into v_owner_ids from public.profiles where org_id = p_org_id;
  delete from public.organizations where id = p_org_id;

  if v_owner_ids is not null and array_length(v_owner_ids, 1) > 0 then
    delete from auth.users where id = any(v_owner_ids);
  end if;

  return jsonb_build_object('success', true, 'deleted_org_id', p_org_id);
end;
$$;

create or replace function public.super_admin_set_business_status(
  p_org_id uuid,
  p_status text,
  p_extend_days integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_expiry timestamptz;
begin
  if not is_super_admin() then raise exception 'Access denied.'; end if;

  if p_extend_days is not null and p_extend_days > 0 then
    v_new_expiry := greatest(now(), coalesce((select expires_at from public.organizations where id = p_org_id), now())) + (p_extend_days || ' days')::interval;
    update public.organizations set status = p_status, expires_at = v_new_expiry where id = p_org_id;
  else
    update public.organizations set status = p_status where id = p_org_id;
  end if;

  return jsonb_build_object('success', true, 'org_id', p_org_id, 'status', p_status);
end;
$$;

drop function if exists public.super_admin_reset_owner_password(uuid, text);
drop function if exists public.super_admin_reset_owner_password(uuid, uuid, text);

create or replace function public.super_admin_reset_owner_password(
  p_org_id uuid default null,
  p_owner_id uuid default null,
  p_new_temporary_password text default 'Pass1234'
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_uid uuid := p_owner_id;
  v_email text;
begin
  if not is_super_admin() then raise exception 'Access denied.'; end if;

  if v_uid is null and p_org_id is not null then
    select p.id, u.email into v_uid, v_email
    from public.profiles p
    join auth.users u on u.id = p.id
    where p.org_id = p_org_id and p.role = 'owner'
    limit 1;
  end if;

  if v_uid is null then
    raise exception 'Owner account could not be found for this business.';
  end if;

  if v_email is null then
    select email into v_email from auth.users where id = v_uid;
  end if;

  update auth.users
  set encrypted_password = extensions.crypt(p_new_temporary_password, extensions.gen_salt('bf')),
      updated_at = now()
  where id = v_uid;

  if v_email is not null then
    insert into auth.identities (
      id,
      user_id,
      identity_data,
      provider,
      provider_id,
      last_sign_in_at,
      created_at,
      updated_at
    )
    values (
      gen_random_uuid(),
      v_uid,
      jsonb_build_object('sub', v_uid::text, 'email', lower(trim(v_email))),
      'email',
      lower(trim(v_email)),
      now(),
      now(),
      now()
    )
    on conflict (provider, provider_id) do update set
      user_id = excluded.user_id,
      identity_data = excluded.identity_data,
      updated_at = now();
  end if;

  return jsonb_build_object('success', true, 'owner_id', v_uid, 'owner_email', v_email);
end;
$$;

create or replace function public.super_admin_get_overview()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  if not is_super_admin() then raise exception 'Access denied.'; end if;

  select jsonb_agg(row_to_json(b)) into v_result
  from (
    select 
      o.id,
      o.name,
      o.join_code,
      o.status,
      o.subscription_fee,
      o.expires_at,
      o.contact_phone,
      o.contact_person,
      o.created_at,
      (select p.id from public.profiles p where p.org_id = o.id and p.role = 'owner' limit 1) as owner_id,
      (select u.email from public.profiles p join auth.users u on u.id = p.id where p.org_id = o.id and p.role = 'owner' limit 1) as owner_email,
      (select count(*) from public.profiles p where p.org_id = o.id and p.role <> 'owner') as staff_count,
      (select count(*) from public.transactions t where t.org_id = o.id) as tx_count,
      (select coalesce(sum(t.amount), 0) from public.transactions t where t.org_id = o.id) as total_revenue
    from public.organizations o
    where o.name not in ('Mela Master Admin', 'SwiftReceipt Master Admin')
    order by o.created_at desc
  ) b;

  return coalesce(v_result, '[]'::jsonb);
end;
$$;

grant execute on function public.super_admin_create_business to authenticated;
grant execute on function public.super_admin_edit_business to authenticated;
grant execute on function public.super_admin_delete_business to authenticated;
grant execute on function public.super_admin_set_business_status to authenticated;
grant execute on function public.super_admin_reset_owner_password(uuid, uuid, text) to authenticated;
grant execute on function public.super_admin_get_overview to authenticated;
grant execute on function public.is_super_admin to authenticated;
grant execute on function public.is_org_active to authenticated;

-- =====================================================================
-- 6.5 AUTOMATIC BI-DIRECTIONAL SMS RECONCILIATION TRIGGERS
-- =====================================================================

-- DIRECTION A: Scan arrives AFTER SMS (Payment already in bank_credits)
create or replace function public.match_transaction_with_credit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_credit_id uuid;
  v_credit_amount numeric(12,2);
begin
  new.reference_number := upper(trim(new.reference_number));

  select id, amount into v_credit_id, v_credit_amount
  from public.bank_credits
  where org_id = new.org_id
    and reference_number = new.reference_number
    and (used_by_tx_id is null or used_by_tx_id = new.id)
  order by created_at desc
  limit 1;

  if v_credit_id is not null then
    if abs(v_credit_amount - new.amount) < 0.05 then
      new.verification_status := 'verified';
    else
      new.verification_status := 'mismatch';
    end if;

    update public.bank_credits
    set used_by_tx_id = new.id
    where id = v_credit_id;
  else
    if new.verification_status is null or new.verification_status = '' then
      new.verification_status := 'awaiting';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_match_tx_on_insert on public.transactions;
create trigger trg_match_tx_on_insert
  before insert or update of reference_number, amount on public.transactions
  for each row execute function public.match_transaction_with_credit();

-- DIRECTION B: SMS arrives AFTER Scan (Scan was saved first with 'awaiting')
create or replace function public.match_credit_with_pending_transaction()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tx_id uuid;
  v_tx_amount numeric(12,2);
begin
  new.reference_number := upper(trim(new.reference_number));

  select id, amount into v_tx_id, v_tx_amount
  from public.transactions
  where org_id = new.org_id
    and reference_number = new.reference_number
    and verification_status in ('awaiting', 'unverified')
  order by created_at desc
  limit 1;

  if v_tx_id is not null then
    if abs(v_tx_amount - new.amount) < 0.05 then
      update public.transactions
      set verification_status = 'verified'
      where id = v_tx_id;
      new.used_by_tx_id := v_tx_id;
    else
      update public.transactions
      set verification_status = 'mismatch'
      where id = v_tx_id;
      new.used_by_tx_id := v_tx_id;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_match_credit_on_insert on public.bank_credits;
create trigger trg_match_credit_on_insert
  before insert on public.bank_credits
  for each row execute function public.match_credit_with_pending_transaction();

-- RPC for background SMS listener to record bank credit
create or replace function public.ingest_bank_sms(
  p_org_id uuid,
  p_reference text,
  p_amount numeric,
  p_sender text default null,
  p_provider text default null,
  p_raw_sms text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_status text := 'recorded';
begin
  insert into public.bank_credits (org_id, reference_number, amount, sender_name, provider, raw_sms)
  values (p_org_id, upper(trim(p_reference)), p_amount, p_sender, p_provider, p_raw_sms)
  returning id into v_id;

  select coalesce(t.verification_status, 'recorded') into v_status
  from public.bank_credits bc
  left join public.transactions t on t.id = bc.used_by_tx_id
  where bc.id = v_id;

  return jsonb_build_object(
    'success', true,
    'credit_id', v_id,
    'verification_status', v_status
  );
end;
$$;

grant execute on function public.ingest_bank_sms to authenticated, service_role;


-- 7. ROW LEVEL SECURITY (RLS) POLICIES
alter table public.organizations enable row level security;
alter table public.profiles enable row level security;
alter table public.transactions enable row level security;
alter table public.audits enable row level security;
alter table public.bank_credits enable row level security;

-- Super Admin has full permissions across all tables
drop policy if exists org_super_admin on public.organizations;
create policy org_super_admin on public.organizations for all to authenticated
  using (is_super_admin()) with check (is_super_admin());

drop policy if exists profiles_super_admin on public.profiles;
create policy profiles_super_admin on public.profiles for all to authenticated
  using (is_super_admin()) with check (is_super_admin());

-- Standard User Policies
drop policy if exists org_read on public.organizations;
create policy org_read on public.organizations for select to authenticated
  using (id = my_org() or is_super_admin());

drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated
  using (org_id = my_org() or is_super_admin());

drop policy if exists tx_all on public.transactions;
create policy tx_all on public.transactions for all to authenticated
  using (org_id = my_org() or is_super_admin())
  with check (org_id = my_org() or is_super_admin());


-- 8. INITIALIZE MASTER ADMIN ORG & CREATE NEW FRESH SUPER ADMIN ACCOUNT
-- Email: admin@swiftreceipt.et
-- Password: AdminPassword123
do $$
declare
  v_master_org uuid;
  v_admin_uid uuid := gen_random_uuid();
begin
  -- Create dedicated Master Organization
  insert into public.organizations (id, name, status, notes)
  values (gen_random_uuid(), 'Mela Master Admin', 'active', 'Platform Operations Root')
  returning id into v_master_org;

  -- Create fresh Super Admin in auth.users
  insert into auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at
  )
  values (
    '00000000-0000-0000-0000-000000000000',
    v_admin_uid,
    'authenticated',
    'authenticated',
    'admin@mela.et',
    extensions.crypt('AdminPassword123', extensions.gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}',
    jsonb_build_object('full_name', 'Super Administrator', 'role', 'super_admin', 'org_id', v_master_org::text),
    now(),
    now()
  );

  -- Create identity for master admin (required by GoTrue)
  insert into auth.identities (
    id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at
  )
  values (
    gen_random_uuid(), v_admin_uid,
    jsonb_build_object('sub', v_admin_uid::text, 'email', 'admin@mela.et'),
    'email', 'admin@mela.et', now(), now(), now()
  )
  on conflict (provider, provider_id) do update set
    user_id = excluded.user_id,
    identity_data = excluded.identity_data,
    updated_at = now();

  -- Create profile (upsert to handle trigger or explicit creation cleanly)
  insert into public.profiles (id, org_id, full_name, role)
  values (v_admin_uid, v_master_org, 'Super Administrator', 'super_admin')
  on conflict (id) do update set 
    org_id = excluded.org_id, 
    role = 'super_admin', 
    full_name = 'Super Administrator';
end $$;
