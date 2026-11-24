-- ============================================================
-- الجدول الزمني الكامل للبرنامج (هاكثون، إرشاد، تحكيم)
-- ============================================================
-- يُطبّق بعد 30_mentorship_advanced.sql
-- ============================================================

insert into public.platform_settings (key, value) values
  ('hackathon_end_date', '2026-12-05T20:00:00+03:00'),
  ('mentorship_start_date', null),
  ('mentorship_end_date', null),
  ('judging_start_date', null),
  ('judging_end_date', null)
on conflict (key) do nothing;
