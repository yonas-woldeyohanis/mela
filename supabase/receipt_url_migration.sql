-- Migration: Add receipt_url column to transactions
alter table transactions add column if not exists receipt_url text;
