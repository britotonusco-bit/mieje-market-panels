-- Aplicado al proyecto Supabase el 26-10-2026.
alter table public.job_applications add column if not exists application_data jsonb not null default '{}'::jsonb;
