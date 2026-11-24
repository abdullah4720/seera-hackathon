-- ============================================================
-- منصة هاكثون السيرة النبوية - التحديثات والملفات (Announcements)
-- ============================================================
-- يُطبّق بعد 04_seed.sql
-- ============================================================

create table public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text,
  file_url text,              -- رابط ملف مرفق (اختياري)
  track_id uuid references public.tracks(id),   -- null = لجميع المسارات
  is_pinned boolean default false,
  published_at timestamptz default now(),
  created_by uuid references public.profiles(id),
  created_at timestamptz default now()
);

create index idx_announcements_track on public.announcements(track_id);
create index idx_announcements_published on public.announcements(published_at desc);

alter table public.announcements enable row level security;

-- قراءة عامة لكل المسجلين (المشارك يشوف تحديثات مساره + العامة)
create policy "announcements_select_all" on public.announcements
  for select using (auth.role() = 'authenticated');

-- الإدارة والتنسيق فقط يضيفون/يعدّلون/يحذفون
create policy "announcements_admin_manage" on public.announcements
  for all using (public.has_role('admin') or public.has_role('coordinator'));
