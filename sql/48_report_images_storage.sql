-- ============================================================
-- حاوية تخزين لصور التقرير النهائي (لقطات من الفعالية)
-- ============================================================
-- يُطبّق بعد 47_dynamic_submission_fields.sql
-- ============================================================

insert into storage.buckets (id, name, public)
values ('report-images', 'report-images', true)
on conflict (id) do nothing;

-- رفع/حذف: admin أو coordinator فقط
create policy "report_images_insert_admin" on storage.objects
  for insert with check (
    bucket_id = 'report-images'
    and (public.has_role('admin') or public.has_role('coordinator'))
  );

create policy "report_images_delete_admin" on storage.objects
  for delete using (
    bucket_id = 'report-images'
    and (public.has_role('admin') or public.has_role('coordinator'))
  );

-- قراءة عامة (تحتاجها pptxgenjs بالمتصفح لجلب الصور مباشرة برابطها)
create policy "report_images_select_public" on storage.objects
  for select using (bucket_id = 'report-images');
