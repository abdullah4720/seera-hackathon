-- ============================================================
-- تفاصيل موسّعة لكل مسار: وصف كامل + متطلبات + محاور تقييم
-- ============================================================
-- يُطبّق بعد 52_team_scoped_announcements.sql
-- ============================================================

alter table public.tracks add column if not exists long_description text;
alter table public.tracks add column if not exists requirements jsonb default '[]'::jsonb;
alter table public.tracks add column if not exists evaluation_focus text;
