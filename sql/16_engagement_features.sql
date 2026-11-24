-- ============================================================
-- تواصل داخل الفريق + إعدادات عامة + مغادرة الفريق + نشر نتائج التحكيم
-- ============================================================
-- يُطبّق بعد 15_attendance_scan.sql
-- ============================================================

-- ------------------------------------------------------------
-- 1. إعدادات عامة للمنصة (key/value) — تُستخدم لتاريخ الهاكثون وغيره
-- ------------------------------------------------------------
create table public.platform_settings (
  key text primary key,
  value text
);
alter table public.platform_settings enable row level security;

create policy "platform_settings_select_all" on public.platform_settings
  for select using (true);
create policy "platform_settings_admin_manage" on public.platform_settings
  for all using (public.has_role('admin'));

-- قيمة افتراضية — عدّلها من لوحة التحكم أو مباشرة هنا
insert into public.platform_settings (key, value) values
  ('hackathon_start_date', '2026-12-03T09:00:00+03:00')
on conflict (key) do nothing;

-- ------------------------------------------------------------
-- 2. تواصل داخلي بسيط بين أعضاء الفريق
-- ------------------------------------------------------------
create table public.team_messages (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  message text not null,
  created_at timestamptz default now()
);
create index idx_team_messages_team on public.team_messages(team_id, created_at);

alter table public.team_messages enable row level security;

create policy "team_messages_select" on public.team_messages
  for select using (public.is_team_member(team_id) or public.has_role('admin'));
create policy "team_messages_insert" on public.team_messages
  for insert with check (public.is_team_member(team_id) and user_id = auth.uid());

-- تفعيل التحديث اللحظي للدردشة
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'team_messages'
  ) then
    alter publication supabase_realtime add table public.team_messages;
  end if;
end $$;

-- ------------------------------------------------------------
-- 3. مغادرة الفريق ذاتيًا (للعضو غير القائد فقط)
-- ------------------------------------------------------------
create policy "team_members_delete_self" on public.team_members
  for delete using (user_id = auth.uid() and is_leader = false);

-- ------------------------------------------------------------
-- 4. نشر نتائج التحكيم للفرق (تغذية راجعة بعد الإعلان)
-- ------------------------------------------------------------
alter table public.judging_rounds add column if not exists results_published boolean default false;

create policy "scores_select_team_after_publish" on public.scores
  for select using (
    public.is_team_member(scores.team_id)
    and exists (
      select 1 from public.judging_rounds jr
      where jr.id = scores.round_id and jr.results_published = true
    )
  );
