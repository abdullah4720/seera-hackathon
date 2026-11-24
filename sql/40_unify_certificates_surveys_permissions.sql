-- ============================================================
-- إصلاح جذري: توحيد صلاحيات admin/coordinator — الشهادات والاستبيانات
-- ============================================================
-- يُطبّق بعد 39_fix_prep_attendance_permissions.sql
--
-- نفس النمط المتكرر: 7 سياسات كانت admin فقط بدون coordinator،
-- أخطرها survey_responses و certificates لأن لوحة التحكم
-- تستعلمهم مباشرة (بدون دالة وسيطة) فتظهر فاضية بصمت لأي coordinator
-- ============================================================

-- ------------------------------------------------------------
-- 1. أنواع الشهادات
-- ------------------------------------------------------------
drop policy if exists "certificate_types_admin_manage" on public.certificate_types;
create policy "certificate_types_admin_manage" on public.certificate_types
  for all using (public.has_role('admin') or public.has_role('coordinator'));

-- ------------------------------------------------------------
-- 2. الشهادات الصادرة (رؤية القائمة الأخيرة بلوحة التحكم)
-- ------------------------------------------------------------
drop policy if exists "certificates_select_own_or_admin" on public.certificates;
create policy "certificates_select_own_or_admin" on public.certificates
  for select using (user_id = auth.uid() or public.has_role('admin') or public.has_role('coordinator'));

drop policy if exists "certificates_insert_system" on public.certificates;
create policy "certificates_insert_system" on public.certificates
  for insert with check (user_id = auth.uid() or public.has_role('admin') or public.has_role('coordinator'));

-- ------------------------------------------------------------
-- 3. الاستبيانات (إنشاء/تعديل + رؤية غير النشطة)
-- ------------------------------------------------------------
drop policy if exists "surveys_select_active" on public.surveys;
create policy "surveys_select_active" on public.surveys
  for select using (is_active = true or public.has_role('admin') or public.has_role('coordinator'));

drop policy if exists "surveys_admin_manage" on public.surveys;
create policy "surveys_admin_manage" on public.surveys
  for all using (public.has_role('admin') or public.has_role('coordinator'));

-- ------------------------------------------------------------
-- 4. ردود الاستبيانات — أهم إصلاح بهذا الملف
--    (لوحة التحكم تستعلمها مباشرة لعرض عدد الردود والتحليلات)
-- ------------------------------------------------------------
drop policy if exists "survey_responses_select_own_or_admin" on public.survey_responses;
create policy "survey_responses_select_own_or_admin" on public.survey_responses
  for select using (user_id = auth.uid() or public.has_role('admin') or public.has_role('coordinator'));

-- ------------------------------------------------------------
-- 5. سجل النشاط
-- ------------------------------------------------------------
drop policy if exists "activity_log_admin_only" on public.activity_log;
create policy "activity_log_admin_only" on public.activity_log
  for select using (public.has_role('admin') or public.has_role('coordinator'));
