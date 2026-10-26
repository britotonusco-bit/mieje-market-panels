-- Aplicado al proyecto Supabase el 26-10-2026.
alter table public.business_members add column if not exists is_business_owner boolean not null default false;
create or replace function private.is_business_owner(p_business_id uuid)
returns boolean language sql stable security definer set search_path to '' as $function$
  select exists (
    select 1 from public.business_members bm join public.businesses b on b.id = bm.business_id
    where bm.business_id = p_business_id and bm.user_id = (select auth.uid())
      and bm.role = 'business_admin' and bm.is_business_owner = true
      and bm.is_active = true and coalesce(bm.is_blocked, false) = false and b.is_active = true
  );
$function$;
drop policy if exists access_block_requests_submit on public.access_block_requests;
create policy access_block_requests_submit on public.access_block_requests for insert to authenticated
with check (requested_by = auth.uid() and private.is_business_owner(business_id)
  and exists (select 1 from public.business_members bm where bm.business_id = access_block_requests.business_id and bm.user_id = target_user_id and bm.is_active = true));
