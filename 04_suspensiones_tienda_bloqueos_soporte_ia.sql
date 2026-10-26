-- MiEje Market: ampliación aditiva, sin borrar tablas ni registros existentes.
-- Aplicada al proyecto Supabase el 26-10-2026.

alter table public.businesses
  add column if not exists suspension_reason text,
  add column if not exists suspension_public_message text,
  add column if not exists suspended_at timestamptz,
  add column if not exists suspended_by uuid references public.profiles(id);

alter table public.business_members
  add column if not exists is_business_owner boolean not null default false,
  add column if not exists is_blocked boolean not null default false,
  add column if not exists block_reason text,
  add column if not exists blocked_at timestamptz,
  add column if not exists blocked_by uuid references public.profiles(id);

create table if not exists public.business_store_settings (
  business_id uuid primary key references public.businesses(id) on delete cascade,
  whatsapp_number text,
  payment_methods jsonb not null default '[]'::jsonb,
  delivery_options jsonb not null default '[]'::jsonb,
  contact_options jsonb not null default '{}'::jsonb,
  advertising_enabled boolean not null default true,
  updated_by uuid references public.profiles(id),
  updated_at timestamptz not null default now()
);

create table if not exists public.business_content_pages (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  content_type text not null check (content_type in ('promotion','job_form','announcement','contact')),
  title text not null,
  body text not null default '',
  content jsonb not null default '{}'::jsonb,
  is_published boolean not null default false,
  moderation_status text not null default 'pending' check (moderation_status in ('pending','approved','rejected')),
  moderation_note text,
  moderated_by uuid references public.profiles(id),
  moderated_at timestamptz,
  starts_at timestamptz,
  ends_at timestamptz,
  created_by uuid references public.profiles(id),
  updated_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.business_content_pages
  add column if not exists moderation_status text not null default 'pending',
  add column if not exists moderation_note text,
  add column if not exists moderated_by uuid references public.profiles(id),
  add column if not exists moderated_at timestamptz;
do $$ begin
  if not exists (select 1 from pg_constraint where conname='business_content_pages_moderation_status_check' and conrelid='public.business_content_pages'::regclass) then
    alter table public.business_content_pages add constraint business_content_pages_moderation_status_check check (moderation_status in ('pending','approved','rejected'));
  end if;
end $$;

create table if not exists public.access_block_requests (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  requested_by uuid not null references public.profiles(id),
  target_user_id uuid not null references public.profiles(id),
  reason text not null check (length(trim(reason)) >= 5),
  status text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  technician_note text,
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (requested_by <> target_user_id)
);

create table if not exists public.platform_ai_settings (
  id boolean primary key default true check (id = true),
  enabled boolean not null default false,
  assistant_name text not null default 'Asistente general de MiEje Market',
  system_instructions text not null default '',
  knowledge_scope text not null default 'platform',
  settings jsonb not null default '{}'::jsonb,
  updated_by uuid references public.profiles(id),
  updated_at timestamptz not null default now()
);

create table if not exists public.platform_public_settings (
  id boolean primary key default true check (id = true),
  support_whatsapp text not null default '',
  updated_by uuid references public.profiles(id),
  updated_at timestamptz not null default now()
);

create table if not exists public.business_ai_settings (
  business_id uuid primary key references public.businesses(id) on delete cascade,
  enabled boolean not null default false,
  assistant_name text not null default 'Asistente del negocio',
  instructions text not null default '',
  settings jsonb not null default '{}'::jsonb,
  updated_by uuid references public.profiles(id),
  updated_at timestamptz not null default now()
);

create table if not exists public.job_applications (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  content_page_id uuid not null references public.business_content_pages(id) on delete cascade,
  applicant_name text not null check (length(trim(applicant_name)) between 2 and 120),
  applicant_contact text not null check (length(trim(applicant_contact)) between 3 and 180),
  applicant_message text not null default '' check (length(applicant_message) <= 2000),
  application_data jsonb not null default '{}'::jsonb,
  status text not null default 'new' check (status in ('new','reviewing','contacted','closed')),
  created_at timestamptz not null default now()
);
alter table public.job_applications add column if not exists application_data jsonb not null default '{}'::jsonb;

alter table public.business_store_settings enable row level security;
alter table public.business_content_pages enable row level security;
alter table public.access_block_requests enable row level security;
alter table public.platform_ai_settings enable row level security;
alter table public.platform_public_settings enable row level security;
alter table public.business_ai_settings enable row level security;
alter table public.job_applications enable row level security;

create or replace function private.is_business_owner(p_business_id uuid)
returns boolean language sql stable security definer set search_path to '' as $function$
  select exists (select 1 from public.business_members bm join public.businesses b on b.id = bm.business_id
    where bm.business_id = p_business_id and bm.user_id = (select auth.uid()) and bm.role = 'business_admin'
      and bm.is_business_owner = true and bm.is_active = true and coalesce(bm.is_blocked, false) = false and b.is_active = true);
$function$;

-- Public settings only reveal store-specific checkout/contact choices for active stores.
drop policy if exists business_store_settings_public_read on public.business_store_settings;
create policy business_store_settings_public_read on public.business_store_settings for select to anon, authenticated
using (exists (select 1 from public.businesses b where b.id = business_id and b.is_active = true));
drop policy if exists business_store_settings_member_read on public.business_store_settings;
create policy business_store_settings_member_read on public.business_store_settings for select to authenticated
using (private.is_platform_owner() or private.is_business_member(business_id, array['business_admin','employee']));
drop policy if exists business_store_settings_admin_write on public.business_store_settings;
create policy business_store_settings_admin_write on public.business_store_settings for all to authenticated
using (private.is_platform_owner() or private.is_business_member(business_id, array['business_admin']))
with check (private.is_platform_owner() or private.is_business_member(business_id, array['business_admin']));

drop policy if exists business_content_public_read on public.business_content_pages;
create policy business_content_public_read on public.business_content_pages for select to anon, authenticated
using (is_published = true and moderation_status = 'approved' and (starts_at is null or starts_at <= now()) and (ends_at is null or ends_at >= now())
  and exists (select 1 from public.businesses b where b.id = business_id and b.is_active = true));
drop policy if exists business_content_admin_manage on public.business_content_pages;
create policy business_content_admin_manage on public.business_content_pages for all to authenticated
using (private.is_platform_owner() or private.is_business_member(business_id, array['business_admin']))
with check (private.is_platform_owner() or private.is_business_member(business_id, array['business_admin']));

drop policy if exists access_block_requests_submitter_read on public.access_block_requests;
create policy access_block_requests_submitter_read on public.access_block_requests for select to authenticated
using (private.is_platform_owner() or requested_by = auth.uid() or private.is_business_member(business_id, array['business_admin']));
drop policy if exists access_block_requests_submit on public.access_block_requests;
create policy access_block_requests_submit on public.access_block_requests for insert to authenticated
with check (requested_by = auth.uid() and private.is_business_owner(business_id)
  and exists (select 1 from public.business_members bm where bm.business_id = access_block_requests.business_id and bm.user_id = target_user_id and bm.is_active = true));
drop policy if exists access_block_requests_technical_update on public.access_block_requests;
create policy access_block_requests_technical_update on public.access_block_requests for update to authenticated
using (private.is_platform_owner()) with check (private.is_platform_owner());

drop policy if exists platform_ai_settings_owner_only on public.platform_ai_settings;
create policy platform_ai_settings_owner_only on public.platform_ai_settings for all to authenticated
using (private.is_platform_owner()) with check (private.is_platform_owner());
drop policy if exists platform_public_settings_read on public.platform_public_settings;
create policy platform_public_settings_read on public.platform_public_settings for select to anon, authenticated using (true);
drop policy if exists platform_public_settings_owner_manage on public.platform_public_settings;
create policy platform_public_settings_owner_manage on public.platform_public_settings for all to authenticated
using (private.is_platform_owner()) with check (private.is_platform_owner());

drop policy if exists business_ai_settings_admin_manage on public.business_ai_settings;
create policy business_ai_settings_admin_manage on public.business_ai_settings for all to authenticated
using (private.is_platform_owner() or private.is_business_member(business_id, array['business_admin']))
with check (private.is_platform_owner() or private.is_business_member(business_id, array['business_admin']));

drop policy if exists job_applications_public_submit on public.job_applications;
create policy job_applications_public_submit on public.job_applications for insert to anon, authenticated
with check (exists (select 1 from public.business_content_pages p join public.businesses b on b.id = p.business_id
  where p.id = content_page_id and p.business_id = job_applications.business_id and p.content_type = 'job_form'
    and p.is_published = true and (p.starts_at is null or p.starts_at <= now())
    and (p.ends_at is null or p.ends_at >= now()) and b.is_active = true));
drop policy if exists job_applications_business_read on public.job_applications;
create policy job_applications_business_read on public.job_applications for select to authenticated
using (private.is_platform_owner() or private.is_business_member(business_id, array['business_admin']));
drop policy if exists job_applications_business_update on public.job_applications;
create policy job_applications_business_update on public.job_applications for update to authenticated
using (private.is_platform_owner() or private.is_business_member(business_id, array['business_admin']))
with check (private.is_platform_owner() or private.is_business_member(business_id, array['business_admin']));

drop policy if exists businesses_public_suspension_read on public.businesses;
create policy businesses_public_suspension_read on public.businesses for select to anon, authenticated using (is_active = false);
drop policy if exists businesses_member_status_read on public.businesses;
create policy businesses_member_status_read on public.businesses for select to authenticated
using (exists (select 1 from public.business_members bm where bm.business_id = businesses.id and bm.user_id = auth.uid()));


create or replace function private.prevent_nontechnical_content_moderation()
returns trigger language plpgsql security definer set search_path to '' as $function$
begin
  if auth.uid() is not null and not private.is_platform_owner() then
    if tg_op = 'INSERT' and new.moderation_status <> 'pending' then
      raise exception 'Las publicaciones nuevas deben quedar pendientes de revisión técnica.';
    end if;
    if tg_op = 'UPDATE' and new.moderation_status is distinct from old.moderation_status then
      raise exception 'Solo el servicio técnico puede aprobar o rechazar publicaciones.';
    end if;
  end if;
  return new;
end;
$function$;
drop trigger if exists enforce_business_content_moderation on public.business_content_pages;
create trigger enforce_business_content_moderation before insert or update on public.business_content_pages
for each row execute function private.prevent_nontechnical_content_moderation();

create or replace function private.is_business_member(p_business_id uuid, p_roles text[] default null::text[])
returns boolean language sql stable security definer set search_path to '' as $function$
  select exists (select 1 from public.business_members bm join public.businesses b on b.id = bm.business_id
    where bm.business_id = p_business_id and bm.user_id = (select auth.uid()) and bm.is_active = true
      and coalesce(bm.is_blocked, false) = false and b.is_active = true
      and (p_roles is null or bm.role = any(p_roles)));
$function$;

grant select on public.business_store_settings, public.business_content_pages, public.platform_public_settings to anon, authenticated;
grant insert, update, delete on public.business_store_settings, public.business_content_pages to authenticated;
grant select, insert, update on public.access_block_requests to authenticated;
grant select, insert, update, delete on public.platform_ai_settings, public.business_ai_settings to authenticated;
grant insert, select, update on public.job_applications to authenticated;
grant insert on public.job_applications to anon;
