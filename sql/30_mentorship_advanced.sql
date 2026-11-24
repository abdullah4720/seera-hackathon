-- ============================================================
-- تطوير شامل لعملية الإرشاد: تذكير، عدم حضور، تقييم
-- ============================================================
-- يُطبّق بعد 29_team_codes.sql
-- ============================================================

-- ------------------------------------------------------------
-- 1. حالة "عدم الحضور" (No-show)
-- ------------------------------------------------------------
alter table public.mentor_bookings drop constraint if exists mentor_bookings_status_check;
alter table public.mentor_bookings add constraint mentor_bookings_status_check
  check (status in ('pending','confirmed','completed','cancelled','no_show_team','no_show_mentor'));

-- ------------------------------------------------------------
-- 2. تقييم الفريق للمرشد بعد الجلسة
-- ------------------------------------------------------------
create table public.mentor_ratings (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.mentor_bookings(id) on delete cascade,
  team_id uuid not null references public.teams(id) on delete cascade,
  mentor_user_id uuid not null references public.profiles(id) on delete cascade,
  rating int not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz default now(),
  unique(booking_id)
);
alter table public.mentor_ratings enable row level security;

create policy "mentor_ratings_select" on public.mentor_ratings
  for select using (
    public.is_team_member(team_id) or mentor_user_id = auth.uid()
    or public.has_role('admin') or public.has_role('coordinator')
  );
create policy "mentor_ratings_insert" on public.mentor_ratings
  for insert with check (public.is_team_member(team_id));

-- ------------------------------------------------------------
-- 3. تذكير تلقائي قبل الموعد (عبر pg_cron)
-- ------------------------------------------------------------
alter table public.mentor_bookings add column if not exists reminder_sent boolean default false;

create or replace function public.send_upcoming_mentorship_reminders()
returns void as $$
declare
  b record;
begin
  for b in (
    select mb.id, mb.team_id, ms.mentor_user_id, ms.start_time, t.team_name
    from public.mentor_bookings mb
    join public.mentor_slots ms on ms.id = mb.slot_id
    join public.teams t on t.id = mb.team_id
    where mb.status = 'confirmed'
      and mb.reminder_sent = false
      and ms.start_time between now() and now() + interval '35 minutes'
  ) loop
    insert into public.notifications (user_id, title, body)
    select tm.user_id, '⏰ تذكير: موعد إرشاد قريب', 'موعدكم مع المرشد يبدأ الساعة ' || to_char(b.start_time, 'HH12:MI AM')
    from public.team_members tm where tm.team_id = b.team_id;

    insert into public.notifications (user_id, title, body)
    values (b.mentor_user_id, '⏰ تذكير: موعد إرشاد قريب', 'لديك جلسة مع فريق "' || b.team_name || '" الساعة ' || to_char(b.start_time, 'HH12:MI AM'));

    update public.mentor_bookings set reminder_sent = true where id = b.id;
  end loop;
end;
$$ language plpgsql security definer set search_path = public;

-- تفعيل الجدولة التلقائية (يتطلب صلاحية pg_cron — إذا فشل هذا السطر،
-- فعّل امتداد pg_cron يدويًا من Database → Extensions بلوحة Supabase ثم أعد تشغيله)
create extension if not exists pg_cron;

do $$
begin
  if not exists (select 1 from cron.job where jobname = 'mentorship-reminders') then
    perform cron.schedule(
      'mentorship-reminders',
      '*/10 * * * *',
      $job$select public.send_upcoming_mentorship_reminders();$job$
    );
  end if;
end $$;

-- ------------------------------------------------------------
-- 4. تحديث سياسة التحديث لتشمل حالة عدم الحضور (لا تغيير مطلوب،
--    السياسة الحالية تسمح بالفعل بأي تحديث حالة من الأطراف المخوّلة)
-- ------------------------------------------------------------
