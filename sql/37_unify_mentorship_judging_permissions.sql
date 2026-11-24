-- ============================================================
-- إصلاح جذري: توحيد صلاحيات admin/coordinator بمرحلة الإرشاد والتحكيم
-- ============================================================
-- يُطبّق بعد 36_unify_admin_coordinator_permissions.sql
--
-- نفس النمط المكتشف بالمرحلتين 1 و2: عدة جداول أساسية بالإرشاد
-- والتحكيم كانت تسمح بـ admin فقط بدون coordinator
-- ============================================================

-- ------------------------------------------------------------
-- 1. جولات التحكيم (إنشاء، تفعيل، نشر النتائج)
-- ------------------------------------------------------------
drop policy if exists "judging_rounds_admin_manage" on public.judging_rounds;
create policy "judging_rounds_admin_manage" on public.judging_rounds
  for all using (public.has_role('admin') or public.has_role('coordinator'));

-- ------------------------------------------------------------
-- 2. معايير التحكيم
-- ------------------------------------------------------------
drop policy if exists "judging_criteria_admin_manage" on public.judging_criteria;
create policy "judging_criteria_admin_manage" on public.judging_criteria
  for all using (public.has_role('admin') or public.has_role('coordinator'));

-- ------------------------------------------------------------
-- 3. تعيين المحكّمين للفرق (رؤية وإدارة)
-- ------------------------------------------------------------
drop policy if exists "judge_assignments_select" on public.judge_assignments;
create policy "judge_assignments_select" on public.judge_assignments
  for select using (judge_user_id = auth.uid() or public.has_role('admin') or public.has_role('coordinator'));

drop policy if exists "judge_assignments_admin_manage" on public.judge_assignments;
create policy "judge_assignments_admin_manage" on public.judge_assignments
  for all using (public.has_role('admin') or public.has_role('coordinator'));

-- ------------------------------------------------------------
-- 4. الدرجات — رؤية فقط (نزاهة التحكيم تمنع أي تعديل حتى للمنسّق)
-- ------------------------------------------------------------
drop policy if exists "scores_select_own_or_admin" on public.scores;
create policy "scores_select_own_or_admin" on public.scores
  for select using (judge_user_id = auth.uid() or public.has_role('admin') or public.has_role('coordinator'));

-- ------------------------------------------------------------
-- 5. مواعيد الإرشاد — يشمل تعديل المرشد لموعده + إدارة الإدارة
-- ------------------------------------------------------------
drop policy if exists "mentor_slots_mentor_manage" on public.mentor_slots;
create policy "mentor_slots_mentor_manage" on public.mentor_slots
  for all using (mentor_user_id = auth.uid() or public.has_role('admin') or public.has_role('coordinator'));

-- ------------------------------------------------------------
-- 6. حجوزات الإرشاد (كانت مصلحة جزئيًا بملف 26، نوحّدها بالكامل هنا)
-- ------------------------------------------------------------
drop policy if exists "mentor_bookings_select" on public.mentor_bookings;
create policy "mentor_bookings_select" on public.mentor_bookings
  for select using (
    public.is_team_member(team_id)
    or exists (select 1 from public.mentor_slots where id = slot_id and mentor_user_id = auth.uid())
    or public.has_role('admin')
    or public.has_role('coordinator')
  );

drop policy if exists "mentor_bookings_update" on public.mentor_bookings;
create policy "mentor_bookings_update" on public.mentor_bookings
  for update using (
    public.is_team_member(team_id)
    or exists (select 1 from public.mentor_slots where id = slot_id and mentor_user_id = auth.uid())
    or public.has_role('admin')
    or public.has_role('coordinator')
  );
