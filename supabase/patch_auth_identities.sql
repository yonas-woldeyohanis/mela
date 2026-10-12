-- =====================================================================
-- Mela: Patch for Owner Login & Password Reset
-- Run this in your Supabase SQL Editor (No data will be deleted!)
-- =====================================================================

-- 1. BACKFILL IDENTITIES FOR ALL USERS (Fixes "Database error querying schema")
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
select 
  gen_random_uuid(),
  u.id,
  jsonb_build_object('sub', u.id::text, 'email', lower(trim(u.email))),
  'email',
  lower(trim(u.email)),
  now(),
  now(),
  now()
from auth.users u
on conflict (provider, provider_id) do update set
  user_id = excluded.user_id,
  identity_data = excluded.identity_data,
  updated_at = now();


-- 2. UPDATE super_admin_create_business TO AUTOMATICALLY REGISTER IDENTITY
create or replace function public.super_admin_create_business(
  p_business_name text,
  p_owner_name text,
  p_owner_email text,
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

  -- 1. Create Organization (generates unique join_code automatically)
  insert into public.organizations (name, status, subscription_fee, expires_at, contact_phone, contact_person, notes)
  values (trim(p_business_name), 'active', p_subscription_fee, v_expires_at, p_contact_phone, p_owner_name, p_notes)
  returning id, join_code into v_org_id, v_join_code;

  -- 2. Create Auth User for the business owner
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

  -- 2b. Register identity in auth.identities (required by GoTrue for email auth)
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


-- 3. DROP OLD OVERLOADS & UPDATE super_admin_reset_owner_password
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

grant execute on function public.super_admin_create_business to authenticated;
grant execute on function public.super_admin_reset_owner_password(uuid, uuid, text) to authenticated;
