-- ============================================================
-- إصلاح: السماح للمنسّق (مو admin فقط) بإدارة أدوار المستخدمين
-- ============================================================
-- يُطبّق بعد 26_fix_mentor_booking_insert_rls.sql
-- السياسة القديمة كانت تسمح لـ admin فقط بإضافة/حذف الأدوار
-- (مثل تعيين مرشد أو حذفه) — نوسّعها لتشمل coordinator أيضًا
-- ============================================================

drop policy if exists "user_roles_admin_manage" on public.user_roles;

create policy "user_roles_admin_manage" on public.user_roles
  for all
  using (public.has_role('admin') or public.has_role('coordinator'))
  with check (public.has_role('admin') or public.has_role('coordinator'));
