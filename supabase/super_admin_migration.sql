-- =====================================================================
-- SwiftReceipt: Super Admin, Multi-Tenant Subscription & Access Control
-- Run this in your Supabase SQL Editor.
-- =====================================================================

create extension if not exists pgcrypto schema extensions;

-- 1. Extend organizations table with subscription control
alter table organizations 
  add column if not exists status text not null default 'active' 
  check (status in ('active', 'suspended', 'trial', 'expired')),
  add column if not exists subscription_fee numeric(10,2) default 1000.00,
  add column if not exists billing_cycle text default 'monthly',
  add column if not exists expires_at timestamptz default (now() + interval '30 days'),
  add column if not exists contact_phone text,
  add column if not exists contact_person text,
  add column if not exists notes text;

-- 2. Allow 'super_admin' in profiles role check
alter table profiles drop constraint if exists profiles_role_check;
alter table profiles add constraint profiles_role_check 
  check (role in ('waiter', 'cashier', 'manager', 'owner', 'super_admin'));

-- Helper to check if caller is super admin
create or replace function is_super_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select role = 'super_admin' from profiles where id = auth.uid()), false);
$$;

-- Helper to check if an organization is currently active and not expired
create or replace function is_org_active(p_org_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from organizations 
    where id = p_org_id 
      and status = 'active'
      and (expires_at is null or expires_at >= now())
  );
$$;

-- 3. Update the global auth trigger handle_new_user() so it supports super_admin provisioning
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_org uuid;
  v_name text := coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'), ''), split_part(new.email, '@', 1));
  v_role text := coalesce(nullif(trim(new.raw_user_meta_data->>'role'), ''), 'waiter');
begin
  -- Case A: Super Admin explicitly passed an existing org_id in metadata
  if coalesce(new.raw_user_meta_data->>'org_id', '') <> '' then
    v_org := (new.raw_user_meta_data->>'org_id')::uuid;
    insert into profiles(id, org_id, full_name, role)
    values (new.id, v_org, v_name, v_role)
    on conflict (id) do update set org_id = v_org, full_name = v_name, role = v_role;

  -- Case B: Direct self-registration of business with org_name
  elsif coalesce(new.raw_user_meta_data->>'org_name', '') <> '' then
    insert into organizations(name) values (new.raw_user_meta_data->>'org_name') returning id into v_org;
    insert into profiles(id, org_id, full_name, role)
    values (new.id, v_org, v_name, 'owner')
    on conflict (id) do update set org_id = v_org, full_name = v_name, role = 'owner';

  -- Case C: Staff member joining via team join code
  elsif coalesce(new.raw_user_meta_data->>'join_code', '') <> '' then
    select id into v_org from organizations
      where join_code = upper(trim(new.raw_user_meta_data->>'join_code'));
    if v_org is null then raise exception 'Invalid join code'; end if;
    insert into profiles(id, org_id, full_name, role)
    values (new.id, v_org, v_name, 'waiter')
    on conflict (id) do update set org_id = v_org, full_name = v_name, role = 'waiter';

  -- Case D: Fallback for super admin users
  else
    select id into v_org from organizations where name = 'SwiftReceipt Super Admin' limit 1;
    if v_org is not null then
      insert into profiles(id, org_id, full_name, role)
      values (new.id, v_org, v_name, 'super_admin')
      on conflict (id) do nothing;
    end if;
  end if;
  return new;
end;
$$;

-- 4. Super Admin RPC: Register a new Hotel / Restaurant / Cafe with its Owner and auto-generate invite code
create or replace function super_admin_create_business(
  p_business_name text,
  p_owner_email text,
  p_owner_name text,
  p_temporary_password text,
  p_contact_phone text default null,
  p_subscription_fee numeric default 1000.00,
  p_duration_days integer default 30,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_org_id uuid;
  v_user_id uuid;
  v_join_code text;
  v_expires_at timestamptz;
begin
  if not is_super_admin() then
    raise exception 'Access denied: Only Super Admin can register new businesses.';
  end if;

  v_expires_at := now() + (p_duration_days || ' days')::interval;

  -- 1. Create Organization (this automatically generates a unique join_code via column default)
  insert into organizations (name, status, subscription_fee, expires_at, contact_phone, contact_person, notes)
  values (trim(p_business_name), 'active', p_subscription_fee, v_expires_at, p_contact_phone, p_owner_name, p_notes)
  returning id, join_code into v_org_id, v_join_code;

  -- 2. Create Auth User for the business owner
  -- We include org_id, org_name, and role in metadata so handle_new_user() passes smoothly
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

  -- 3. Ensure profile is linked to the new organization
  insert into profiles (id, org_id, full_name, role)
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

-- 5. Super Admin RPC: Edit an existing Business details
create or replace function super_admin_edit_business(
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
  if not is_super_admin() then
    raise exception 'Access denied.';
  end if;

  update organizations
  set name = coalesce(nullif(trim(p_business_name), ''), name),
      contact_person = coalesce(p_contact_person, contact_person),
      contact_phone = coalesce(p_contact_phone, contact_phone),
      subscription_fee = coalesce(p_subscription_fee, subscription_fee)
  where id = p_org_id;

  return jsonb_build_object('success', true, 'org_id', p_org_id);
end;
$$;

-- 6. Super Admin RPC: Delete a Business and cascade purge all its data
create or replace function super_admin_delete_business(
  p_org_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_owner_ids uuid[];
begin
  if not is_super_admin() then
    raise exception 'Access denied.';
  end if;

  -- Collect owners/staff associated with this org
  select array_agg(id) into v_owner_ids from profiles where org_id = p_org_id;

  -- Cascade delete organization
  delete from organizations where id = p_org_id;

  -- Delete auth users
  if v_owner_ids is not null and array_length(v_owner_ids, 1) > 0 then
    delete from auth.users where id = any(v_owner_ids);
  end if;

  return jsonb_build_object('success', true, 'deleted_org_id', p_org_id);
end;
$$;

-- 7. Super Admin RPC: Suspend or Activate a business (Access Denial)
create or replace function super_admin_set_business_status(
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
  if not is_super_admin() then
    raise exception 'Access denied: Only Super Admin can change business subscription status.';
  end if;

  if p_status not in ('active', 'suspended', 'trial', 'expired') then
    raise exception 'Invalid status value.';
  end if;

  if p_extend_days is not null and p_extend_days > 0 then
    v_new_expiry := greatest(now(), coalesce((select expires_at from organizations where id = p_org_id), now())) + (p_extend_days || ' days')::interval;
    update organizations
    set status = p_status, expires_at = v_new_expiry
    where id = p_org_id;
  else
    update organizations
    set status = p_status
    where id = p_org_id;
  end if;

  return jsonb_build_object('success', true, 'org_id', p_org_id, 'status', p_status);
end;
$$;

-- 8. Super Admin RPC: Reset Owner Temporary Password
create or replace function super_admin_reset_owner_password(
  p_owner_id uuid,
  p_new_temporary_password text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
begin
  if not is_super_admin() then
    raise exception 'Access denied: Only Super Admin can reset owner credentials.';
  end if;

  update auth.users
  set encrypted_password = extensions.crypt(p_new_temporary_password, extensions.gen_salt('bf')),
      updated_at = now()
  where id = p_owner_id;

  return jsonb_build_object('success', true, 'owner_id', p_owner_id);
end;
$$;

-- 9. Super Admin RPC: Fetch All Businesses Overview
create or replace function super_admin_get_overview()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  if not is_super_admin() then
    raise exception 'Access denied.';
  end if;

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
      (select p.id from profiles p where p.org_id = o.id and p.role = 'owner' limit 1) as owner_id,
      (select u.email from profiles p join auth.users u on u.id = p.id where p.org_id = o.id and p.role = 'owner' limit 1) as owner_email,
      (select count(*) from profiles p where p.org_id = o.id and p.role <> 'owner') as staff_count,
      (select count(*) from transactions t where t.org_id = o.id) as tx_count,
      (select coalesce(sum(t.amount), 0) from transactions t where t.org_id = o.id) as total_revenue
    from organizations o
    where o.name <> 'SwiftReceipt Super Admin'
    order by o.created_at desc
  ) b;

  return coalesce(v_result, '[]'::jsonb);
end;
$$;

grant execute on function super_admin_create_business to authenticated;
grant execute on function super_admin_edit_business to authenticated;
grant execute on function super_admin_delete_business to authenticated;
grant execute on function super_admin_set_business_status to authenticated;
grant execute on function super_admin_reset_owner_password to authenticated;
grant execute on function super_admin_get_overview to authenticated;
grant execute on function is_super_admin to authenticated;
grant execute on function is_org_active to authenticated;

-- 10. Row Level Security Policies
drop policy if exists org_super_admin on organizations;
create policy org_super_admin on organizations for all to authenticated
  using (is_super_admin())
  with check (is_super_admin());

drop policy if exists profiles_super_admin on profiles;
create policy profiles_super_admin on profiles for all to authenticated
  using (is_super_admin())
  with check (is_super_admin());

create or replace function make_super_admin(p_email text)
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid;
  v_org uuid;
begin
  select id into v_uid from auth.users where lower(email) = lower(trim(p_email));
  if v_uid is null then return 'User email not found. Please register or sign in first.'; end if;

  select id into v_org from organizations where name = 'SwiftReceipt Super Admin' limit 1;
  if v_org is null then
    insert into organizations (name, status, notes)
    values ('SwiftReceipt Super Admin', 'active', 'Master Admin Organization')
    returning id into v_org;
  end if;

  insert into profiles (id, org_id, full_name, role)
  values (v_uid, v_org, 'Super Administrator', 'super_admin')
  on conflict (id) do update set role = 'super_admin';

  return 'User ' || p_email || ' is now SUPER_ADMIN!';
end;
$$;

grant execute on function make_super_admin to authenticated, anon;
