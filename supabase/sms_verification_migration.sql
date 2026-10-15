-- =====================================================================
-- SwiftReceipt: Real vs Fake Receipt SMS Verification System
-- Execute this script in your Supabase SQL Editor.
-- =====================================================================

-- 1. Ensure verification_status column exists on transactions
alter table transactions 
  add column if not exists verification_status text default 'awaiting' 
  check (verification_status in ('verified', 'mismatch', 'awaiting', 'unverified'));

create index if not exists idx_tx_verif_status on transactions (org_id, verification_status);

-- 2. Create bank_credits table
create table if not exists bank_credits (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  reference_number text not null,
  amount numeric(12,2) not null check (amount > 0),
  sender_name text,
  provider text, -- 'telebirr', 'cbe', etc.
  raw_sms text,
  used_by_tx_id uuid references transactions(id) on delete set null,
  created_at timestamptz default now()
);

create index if not exists idx_bc_org_ref on bank_credits (org_id, reference_number);
create index if not exists idx_bc_used on bank_credits (used_by_tx_id);

-- Enable RLS on bank_credits
alter table bank_credits enable row level security;

-- Only managers/owners can view bank credits directly
create policy bank_credits_read on bank_credits for select to authenticated
  using (org_id = my_org() and is_manager());

-- Allow inserting bank credits via service role / edge function or authenticated manager
create policy bank_credits_insert on bank_credits for insert to authenticated
  with check (org_id = my_org() and is_manager());


-- 3. Trigger Function: When a new receipt (transaction) is inserted or reference updated
create or replace function match_transaction_with_credit()
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

  -- Look for an unused bank credit with the exact same reference for this org
  select id, amount into v_credit_id, v_credit_amount
  from bank_credits
  where org_id = new.org_id
    and reference_number = new.reference_number
    and (used_by_tx_id is null or used_by_tx_id = new.id)
  order by created_at desc
  limit 1;

  if v_credit_id is not null then
    -- Check if amount matches within 0.05 tolerance OR within known transfer fee tier (up to 20 ETB)
    if abs(v_credit_amount - new.amount) < 0.05 or (new.amount > v_credit_amount and (new.amount - v_credit_amount) <= 20.0) then
      new.verification_status := 'verified';
    else
      new.verification_status := 'mismatch';
    end if;

    -- Link this credit to the transaction
    update bank_credits
    set used_by_tx_id = new.id
    where id = v_credit_id;
  else
    -- If no credit exists yet, mark as awaiting SMS confirmation
    if new.verification_status is null or new.verification_status = '' then
      new.verification_status := 'awaiting';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_match_tx_on_insert on transactions;
create trigger trg_match_tx_on_insert
  before insert or update of reference_number, amount on transactions
  for each row execute function match_transaction_with_credit();


-- 4. Trigger Function: When a new bank credit arrives from the SMS forwarder
create or replace function match_credit_with_pending_transaction()
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

  -- Find any pending or awaiting transaction with matching reference in this org
  select id, amount into v_tx_id, v_tx_amount
  from transactions
  where org_id = new.org_id
    and reference_number = new.reference_number
    and verification_status in ('awaiting', 'unverified')
  order by created_at desc
  limit 1;

  if v_tx_id is not null then
    -- Check if amount matches within 0.05 tolerance OR within known transfer fee tier (up to 20 ETB)
    if abs(v_tx_amount - new.amount) < 0.05 or (v_tx_amount > new.amount and (v_tx_amount - new.amount) <= 20.0) then
      update transactions
      set verification_status = 'verified'
      where id = v_tx_id;
      new.used_by_tx_id := v_tx_id;
    else
      update transactions
      set verification_status = 'mismatch'
      where id = v_tx_id;
      new.used_by_tx_id := v_tx_id;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_match_credit_on_insert on bank_credits;
create trigger trg_match_credit_on_insert
  before insert on bank_credits
  for each row execute function match_credit_with_pending_transaction();


-- 5. RPC endpoint to easily ingest SMS from webhook / forwarder
create or replace function ingest_bank_sms(
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
  insert into bank_credits (org_id, reference_number, amount, sender_name, provider, raw_sms)
  values (p_org_id, upper(trim(p_reference)), p_amount, p_sender, p_provider, p_raw_sms)
  returning id into v_id;

  select coalesce(t.verification_status, 'recorded') into v_status
  from bank_credits bc
  left join transactions t on t.id = bc.used_by_tx_id
  where bc.id = v_id;

  return jsonb_build_object(
    'success', true,
    'credit_id', v_id,
    'verification_status', v_status
  );
end;
$$;

grant execute on function ingest_bank_sms to authenticated, service_role;
