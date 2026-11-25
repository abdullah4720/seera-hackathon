-- ============================================================
-- 73: منع إدراج الشهادات مباشرة في الجدول لغير الإدارة
-- قبله: سياسة certificates_insert_system تسمح لأي مستخدم بإدراج شهادة
-- لنفسه من أي نوع (مثل «شهادة الفوز») متجاوزًا شروط الإصدار.
-- بعده: الإدراج المباشر للإدارة والمنسقين فقط؛ وبقية المستخدمين يُصدرون
-- شهاداتهم عبر الدالة issue_certificate التي تتحقق من الدور والحضور والاستبيان.
-- (تعديل سياسة RLS بموافقة صاحب المنصة — 25 نوفمبر 2026)
-- ============================================================
drop policy if exists "certificates_insert_system" on public.certificates;
create policy "certificates_insert_system" on public.certificates
  for insert with check (public.has_role('admin') or public.has_role('coordinator'));
