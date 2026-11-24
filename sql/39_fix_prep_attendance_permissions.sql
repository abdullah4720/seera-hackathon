-- ============================================================
-- إصلاح: صلاحيات تسجيل/إلغاء الحضور اليدوي (prep_attendance)
-- ============================================================
-- يُطبّق بعد 38_judging_mentorship_reliability.sql
--
-- ثغرتان حقيقيتان اكتُشفتا:
-- 1) الإدراج كان يسمح لـ admin فقط بدون coordinator — يكسر ميزة
--    تسجيل الحضور اليدوي لأي حساب coordinator
-- 2) لا توجد سياسة حذف إطلاقًا — حتى admin ما يقدر يلغي تسجيل
--    حضور بالخطأ (زر "✓ حاضر" بالضغط الثاني كان يفشل صامتًا)
-- ============================================================

drop policy if exists "prep_attendance_insert_own" on public.prep_attendance;
create policy "prep_attendance_insert_own" on public.prep_attendance
  for insert with check (
    user_id = auth.uid() or public.has_role('admin') or public.has_role('coordinator')
  );

create policy "prep_attendance_delete_admin" on public.prep_attendance
  for delete using (public.has_role('admin') or public.has_role('coordinator'));

-- ------------------------------------------------------------
-- ثغرة أمنية أخطر: event_attendance_insert كانت "with check (true)"
-- أي مستخدم مسجّل دخول يقدر يُدرج حضورًا لنفسه أو لأي شخص آخر
-- مباشرة بتجاوز كامل لدالة record_event_attendance الآمنة
-- ------------------------------------------------------------
drop policy if exists "event_attendance_insert" on public.event_attendance;
create policy "event_attendance_insert" on public.event_attendance
  for insert with check (public.has_role('admin') or public.has_role('coordinator'));

create policy "event_attendance_delete_admin" on public.event_attendance
  for delete using (public.has_role('admin') or public.has_role('coordinator'));
