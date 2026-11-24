-- ============================================================
-- إصلاح/إضافة: عرض المشاريع للمرشدين والمحكّمين + التحديث اللحظي
-- ============================================================
-- يُطبّق بعد 11_leader_permissions.sql
-- ============================================================

-- السماح لأي مرشد أو محكّم بمشاهدة كل المشاريع المقدَّمة (صفحة عرض مشتركة)
-- ملاحظة: القراءة فقط، التعديل يبقى محصورًا بقائد الفريق (11_leader_permissions.sql)
create policy "submissions_select_mentors_judges" on public.submissions
  for select using (public.has_role('mentor') or public.has_role('judge'));

-- تفعيل التحديث اللحظي (Realtime) على جدول المشاريع
-- يسمح لصفحة العرض بالتحديث تلقائيًا دون الحاجة لتحديث الصفحة يدويًا
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'submissions'
  ) then
    alter publication supabase_realtime add table public.submissions;
  end if;
end $$;
