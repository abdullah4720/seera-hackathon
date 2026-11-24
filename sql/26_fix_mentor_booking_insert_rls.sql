-- ============================================================
-- الإصلاح الجذري: ربط المشارك بطلب الإرشاد وتأكيده بشكل كامل
-- ============================================================
-- يُطبّق بعد 25_mentorship_notifications.sql
--
-- المشكلة الحقيقية: سياسة INSERT على mentor_bookings كانت تسمح فقط
-- لعضو الفريق نفسه بإنشاء حجز — الإداري (اللي مو عضو بأي فريق)
-- ما كان يقدر يُدرج حجزًا نيابة عن فريق إطلاقًا، فيفشل التعيين
-- اليدوي صامتًا من قاعدة البيانات نفسها بغض النظر عن كود الواجهة
-- ============================================================

drop policy if exists "mentor_bookings_insert_team" on public.mentor_bookings;

create policy "mentor_bookings_insert_team_or_admin" on public.mentor_bookings
  for insert with check (
    public.is_team_member(team_id)
    or public.has_role('admin')
    or public.has_role('coordinator')
  );

-- تقوية سياسة التعديل لتشمل المنسّق أيضًا (كانت تشمل admin فقط)
drop policy if exists "mentor_bookings_update" on public.mentor_bookings;

create policy "mentor_bookings_update" on public.mentor_bookings
  for update using (
    public.is_team_member(team_id)
    or exists (select 1 from public.mentor_slots where id = slot_id and mentor_user_id = auth.uid())
    or public.has_role('admin')
    or public.has_role('coordinator')
  );

-- ------------------------------------------------------------
-- تحقق سريع بعد التطبيق: يجب أن يرجع صفين (insert + update) لهذا الجدول
-- ------------------------------------------------------------
-- select policyname, cmd from pg_policies where tablename = 'mentor_bookings';
