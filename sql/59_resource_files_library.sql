-- ============================================================
-- مكتبة الملفات المستقلة (منفصلة عن التحديثات)
-- ============================================================
-- يُطبّق بعد 58_fix_mentor_profile_visibility.sql
--
-- الفكرة: التحديثات = محتوى زمني (إعلانات، تنبيهات)
--         الملفات = مرجع دائم (أدلة، قوالب، شعارات) يرجع له
--         المشارك أكثر من مرة، مستقل عن أي إعلان معيّن
-- ============================================================

create table public.resource_files (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  file_url text not null,
  category text,                              -- تصنيف اختياري (أدلة/قوالب/شعارات...) — نص حر
  track_id uuid references public.tracks(id) on delete cascade,   -- null = كل المسارات
  team_id uuid references public.teams(id) on delete cascade,     -- null = كل الفرق (استهداف فريق محدد)
  is_pinned boolean default false,
  uploaded_by uuid references public.profiles(id),
  created_at timestamptz default now()
);

alter table public.resource_files enable row level security;

-- القراءة: أي مستخدم مسجّل دخول يشوف الملفات العامة، أو الخاصة بمساره، أو الخاصة بفريقه
create policy "resource_files_select" on public.resource_files
  for select using (
    (track_id is null and team_id is null)
    or (team_id is not null and public.is_team_member(team_id))
    or (track_id is not null and exists (
      select 1 from public.team_members tm join public.teams t on t.id = tm.team_id
      where tm.user_id = auth.uid() and t.track_id = resource_files.track_id
    ))
    or public.has_role('admin') or public.has_role('coordinator')
  );

create policy "resource_files_admin_manage" on public.resource_files
  for all using (public.has_role('admin') or public.has_role('coordinator'));

-- ------------------------------------------------------------
-- حاوية تخزين مستقلة للملفات المرجعية
-- ------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('resource-files', 'resource-files', true)
on conflict (id) do nothing;

create policy "resource_files_storage_insert_admin" on storage.objects
  for insert with check (
    bucket_id = 'resource-files'
    and (public.has_role('admin') or public.has_role('coordinator'))
  );

create policy "resource_files_storage_delete_admin" on storage.objects
  for delete using (
    bucket_id = 'resource-files'
    and (public.has_role('admin') or public.has_role('coordinator'))
  );

create policy "resource_files_storage_select_public" on storage.objects
  for select using (bucket_id = 'resource-files');
