-- ============================================================
-- إصلاح: السماح لصاحب الطلب بتعديل طلبه (مرشد/محكّم) قبل المراجعة
-- ============================================================
-- يُطبّق بعد 21_judge_applications.sql
-- المشكلة: عند إعادة إرسال الطلب (upsert)، Postgres ينفّذ تحديث
-- على الصف الموجود، لكن سياسة UPDATE كانت مقصورة على الإداري فقط
-- ============================================================

create policy "mentor_applications_update_own" on public.mentor_applications
  for update using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy "judge_applications_update_own" on public.judge_applications
  for update using (user_id = auth.uid())
  with check (user_id = auth.uid());
