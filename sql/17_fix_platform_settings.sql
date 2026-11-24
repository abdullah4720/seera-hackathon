-- ============================================================
-- إصلاح: سياسة platform_settings — السماح بالحفظ فعليًا
-- ============================================================
-- يُطبّق بعد 16_engagement_features.sql
-- ============================================================

drop policy if exists "platform_settings_admin_manage" on public.platform_settings;

create policy "platform_settings_admin_manage" on public.platform_settings
  for all
  using (public.has_role('admin') or public.has_role('coordinator'))
  with check (public.has_role('admin') or public.has_role('coordinator'));

-- ------------------------------------------------------------
-- تحقق سريع: شغّل هذا وأنت بنفس حساب الأدمن (من داخل التطبيق وليس هنا)
-- إذا رجعت النتيجة false، فالمشكلة إن الحساب الحالي ما يملك دور admin فعليًا
-- ------------------------------------------------------------
-- select public.has_role('admin');   -- شغّلها من console المتصفح عبر sb.rpc، مو من هنا
