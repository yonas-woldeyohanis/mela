-- =====================================================================
-- Migration: Add account_holder_name to organizations & update RPCs
-- Allows businesses to specify registered bank/wallet account holder names
-- (e.g. "BETELHEM FKADU CHALA") to prevent false fraud warnings on CBE/Telebirr
-- =====================================================================

-- 1. Add column to organizations
alter table public.organizations 
  add column if not exists account_holder_name text;

-- 2. Drop old overloads to prevent 42725 ambiguity
drop function if exists public.super_admin_create_business(text, text, text, text, text, numeric, integer, text);
drop function if exists public.super_admin_create_business(text, text, text, text, text, numeric, integer, text, text);
drop function if exists public.super_admin_edit_business(uuid, text, text, text, numeric);
drop function if exists public.super_admin_edit_business(uuid, text, text, text, numeric, text);

-- 3. Updated super_admin_create_business with p_account_holder_name
create or replace function public.super_admin_create_business(
  p_business_name text,
  p_owner_email text,
  p_owner_name text,
  p_temporary_password text,
  p_contact_phone text default null,
  p_subscription_fee numeric default 1000.00,
  p_duration_days integer default 30,
  p_notes text default null,
  p_account_holder_name text default null
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

  -- 1. Create Organization
  insert into public.organizations (
    name, 
    account_holder_name,
    status, 
    subscription_fee, 
    expires_at, 
    contact_phone, 
    contact_person, 
    notes
  )
  values (
    trim(p_business_name), 
    nullif(trim(p_account_holder_name), ''),
    'active', 
    p_subscription_fee, 
    v_expires_at, 
    p_contact_phone, 
    p_owner_name, 
    p_notes
  )
  returning id, join_code into v_org_id, v_join_code;

  -- 2. Resolve owner if already created via GoTrue Auth
  select id into v_user_id from auth.users where email = lower(trim(p_owner_email)) limit 1;

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
    'account_holder_name', p_account_holder_name,
    'join_code', v_join_code,
    'owner_id', v_user_id,
    'owner_email', p_owner_email,
    'expires_at', v_expires_at
  );
end;
$$;

-- 4. Updated super_admin_edit_business with p_account_holder_name
create or replace function public.super_admin_edit_business(
  p_org_id uuid,
  p_business_name text,
  p_contact_person text default null,
  p_contact_phone text default null,
  p_subscription_fee numeric default null,
  p_account_holder_name text default null
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
      subscription_fee = coalesce(p_subscription_fee, subscription_fee),
      account_holder_name = coalesce(p_account_holder_name, account_holder_name)
  where id = p_org_id;

  return jsonb_build_object('success', true, 'org_id', p_org_id);
end;
$$;

-- 5. RPC allowing Business Owner / Manager to update their own account holder name
create or replace function public.update_org_account_holder(p_account_holder_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_role text;
begin
  select org_id, role into v_org_id, v_role from public.profiles where id = auth.uid();
  if v_org_id is null or (v_role <> 'owner' and v_role <> 'manager' and v_role <> 'super_admin') then
    raise exception 'Access denied: Only business owners or managers can update account holder name.';
  end if;

  update public.organizations
  set account_holder_name = trim(p_account_holder_name)
  where id = v_org_id;

  return jsonb_build_object('success', true, 'account_holder_name', trim(p_account_holder_name));
end;
$$;

-- 6. Updated super_admin_get_overview including account_holder_name
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

  select jsonb_build_object(
    'businesses', coalesce(jsonb_agg(row_to_json(b)), '[]'::jsonb),
    'total_businesses', count(*),
    'active_businesses', count(*) filter (where b.status = 'active'),
    'suspended_businesses', count(*) filter (where b.status <> 'active'),
    'estimated_monthly_income_etb', coalesce(sum(b.subscription_fee) filter (where b.status = 'active'), 0)
  ) into v_result
  from (
    select distinct on (o.id)
      o.id,
      o.name,
      o.account_holder_name,
      o.join_code,
      o.status,
      coalesce(o.subscription_fee, 1000.00) as subscription_fee,
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
    order by o.id, o.created_at desc
  ) b;

  return coalesce(v_result, '{"businesses":[]}'::jsonb);
end;
$$;

-- Grants
grant execute on function public.super_admin_create_business to authenticated;
grant execute on function public.super_admin_edit_business to authenticated;
grant execute on function public.update_org_account_holder to authenticated;
grant execute on function public.super_admin_get_overview to authenticated;
