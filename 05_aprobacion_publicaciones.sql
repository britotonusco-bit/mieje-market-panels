-- Aplicado al proyecto Supabase el 26-10-2026. Solo el propietario técnico puede moderar.
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
create or replace function private.prevent_nontechnical_content_moderation()
returns trigger language plpgsql security definer set search_path to '' as $function$
begin
  if auth.uid() is not null and not private.is_platform_owner() then
    if tg_op = 'INSERT' and new.moderation_status <> 'pending' then raise exception 'Las publicaciones nuevas deben quedar pendientes de revisión técnica.'; end if;
    if tg_op = 'UPDATE' and new.moderation_status is distinct from old.moderation_status then raise exception 'Solo el servicio técnico puede aprobar o rechazar publicaciones.'; end if;
  end if;
  return new;
end;
$function$;
drop trigger if exists enforce_business_content_moderation on public.business_content_pages;
create trigger enforce_business_content_moderation before insert or update on public.business_content_pages for each row execute function private.prevent_nontechnical_content_moderation();
drop policy if exists business_content_public_read on public.business_content_pages;
create policy business_content_public_read on public.business_content_pages for select to anon, authenticated
using (is_published = true and moderation_status = 'approved' and (starts_at is null or starts_at <= now()) and (ends_at is null or ends_at >= now()) and exists (select 1 from public.businesses b where b.id = business_id and b.is_active = true));
