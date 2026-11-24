-- ============================================================
-- إكمال مرحلة المشاريع: رفع ملفات فعلي + موعد نهائي للتقديم
-- ============================================================
-- يُطبّق بعد 34_participant_extra_fields.sql
-- ============================================================

-- ------------------------------------------------------------
-- 1. حاوية تخزين ملفات المشاريع (Supabase Storage)
-- ------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('project-files', 'project-files', true)
on conflict (id) do nothing;

-- السماح لأعضاء الفريق برفع ملفات داخل مجلد فريقهم فقط (المسار: {team_id}/الملف)
create policy "project_files_insert_team_members" on storage.objects
  for insert with check (
    bucket_id = 'project-files'
    and exists (
      select 1 from public.team_members tm
      where tm.team_id::text = (storage.foldername(name))[1] and tm.user_id = auth.uid()
    )
  );

-- قراءة عامة للملفات (نفس مبدأ الرابط الخارجي — أي حامل رابط يقدر يفتحه)
create policy "project_files_select_public" on storage.objects
  for select using (bucket_id = 'project-files');

-- السماح لعضو الفريق باستبدال/حذف ملفات فريقه فقط
create policy "project_files_update_team_members" on storage.objects
  for update using (
    bucket_id = 'project-files'
    and exists (
      select 1 from public.team_members tm
      where tm.team_id::text = (storage.foldername(name))[1] and tm.user_id = auth.uid()
    )
  );
create policy "project_files_delete_team_members" on storage.objects
  for delete using (
    bucket_id = 'project-files'
    and exists (
      select 1 from public.team_members tm
      where tm.team_id::text = (storage.foldername(name))[1] and tm.user_id = auth.uid()
    )
  );

-- ------------------------------------------------------------
-- 2. إعداد موعد نهائي للتقديم (submission_deadline)
-- ------------------------------------------------------------
insert into public.platform_settings (key, value) values
  ('submission_deadline', null)
on conflict (key) do nothing;
