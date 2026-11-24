-- ============================================================
-- إصلاح شامل: صلاحيات + تحسينات (دفعة تطوير جديدة)
-- ============================================================
-- يُطبّق بعد 45_add_delete_permissions.sql
-- ============================================================

-- ------------------------------------------------------------
-- 1. المرشدون والمحكّمون يقدرون يشوفون كل المشاريع (submissions)
--    لكن ما كانوا يقدرون يشوفون أعضاء الفريق (team_members) —
--    فجوة حقيقية تمنع عرض "أسماء الفريق" بصفحة المشاريع المشتركة
-- ------------------------------------------------------------
create policy "team_members_select_mentors_judges" on public.team_members
  for select using (public.has_role('mentor') or public.has_role('judge'));

-- ------------------------------------------------------------
-- 2. نفس الشي لجدول profiles — عشان تبان أسماء الأعضاء فعليًا
--    (مو بس معرّفات user_id بدون اسم)
-- ------------------------------------------------------------
drop policy if exists "profiles_select_own_or_admin" on public.profiles;
create policy "profiles_select_own_or_admin" on public.profiles
  for select using (
    id = auth.uid()
    or public.has_role('admin')
    or public.has_role('coordinator')
    or public.has_role('mentor')
    or public.has_role('judge')
  );
