-- ============================================================
-- إعداد وضع توجيه الإرشاد الافتراضي
-- ============================================================
-- يُطبّق بعد 22_fix_application_update.sql
-- ============================================================

insert into public.platform_settings (key, value) values
  ('mentorship_mode', 'self')
on conflict (key) do nothing;
