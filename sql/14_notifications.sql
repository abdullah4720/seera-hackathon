-- ============================================================
-- نظام الإشعارات الداخلية
-- ============================================================
-- يُطبّق بعد 13_mentor_booking_trigger.sql
-- ============================================================

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  body text,
  link text,
  is_read boolean default false,
  created_at timestamptz default now()
);
create index idx_notifications_user on public.notifications(user_id, is_read);

alter table public.notifications enable row level security;

create policy "notifications_select_own" on public.notifications
  for select using (user_id = auth.uid());
create policy "notifications_update_own" on public.notifications
  for update using (user_id = auth.uid());

-- تفعيل التحديث اللحظي
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end $$;

-- ------------------------------------------------------------
-- 1. إشعار عند تغيير حالة الفريق (تأكيد/استبعاد/انسحاب)
-- ------------------------------------------------------------
create or replace function public.notify_team_status_change()
returns trigger as $$
declare
  v_labels jsonb := '{"confirmed":"تم تأكيد فريقكم 🎉","disqualified":"تم استبعاد فريقكم","withdrawn":"تم تسجيل انسحاب فريقكم","pending":"فريقكم قيد المراجعة"}'::jsonb;
begin
  if new.status is distinct from old.status then
    insert into public.notifications (user_id, title, body)
    select tm.user_id,
           coalesce(v_labels->>new.status, 'تحديث حالة الفريق'),
           'فريق "' || new.team_name || '"'
    from public.team_members tm where tm.team_id = new.id;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_notify_team_status on public.teams;
create trigger trg_notify_team_status
  after update on public.teams
  for each row execute function public.notify_team_status_change();

-- ------------------------------------------------------------
-- 2. إشعار عند نشر تحديث جديد (لأصحاب المسار المعني أو الجميع)
-- ------------------------------------------------------------
create or replace function public.notify_new_announcement()
returns trigger as $$
begin
  insert into public.notifications (user_id, title, body, link)
  select distinct p.id, '📢 ' || new.title, coalesce(left(new.body, 120), ''), null
  from public.profiles p
  where new.track_id is null
     or exists (
       select 1 from public.team_members tm
       join public.teams t on t.id = tm.team_id
       where tm.user_id = p.id and t.track_id = new.track_id
     );
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_notify_announcement on public.announcements;
create trigger trg_notify_announcement
  after insert on public.announcements
  for each row execute function public.notify_new_announcement();

-- ------------------------------------------------------------
-- 3. إشعار عند حجز موعد إرشاد (لكل أعضاء الفريق)
-- ------------------------------------------------------------
create or replace function public.notify_mentor_booking()
returns trigger as $$
declare
  v_team_name text;
begin
  select team_name into v_team_name from public.teams where id = new.team_id;
  insert into public.notifications (user_id, title, body)
  select tm.user_id, '🎓 تم حجز موعد إرشاد', 'فريقكم "' || v_team_name || '" حجز موعد إرشاد بنجاح'
  from public.team_members tm where tm.team_id = new.team_id;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_notify_mentor_booking on public.mentor_bookings;
create trigger trg_notify_mentor_booking
  after insert on public.mentor_bookings
  for each row execute function public.notify_mentor_booking();

-- ------------------------------------------------------------
-- 4. إشعار عند إصدار شهادة
-- ------------------------------------------------------------
create or replace function public.notify_certificate_issued()
returns trigger as $$
begin
  insert into public.notifications (user_id, title, body)
  values (new.user_id, '🏅 تم إصدار شهادتك', 'يمكنك الآن تحميل شهادتك من تبويب الشهادات');
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_notify_certificate on public.certificates;
create trigger trg_notify_certificate
  after insert on public.certificates
  for each row execute function public.notify_certificate_issued();
