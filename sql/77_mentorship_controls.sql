-- ============================================================
-- 77) ضوابط جلسات الإرشاد ولوحة الإرشاد الحية (منقولة من ابتكار إنفاذ)
--   • تأكيد انعقاد الجلسة (المرشد أو الإدارة) ومعالجة الجلسة غير المنعقدة
--   • نافذة الحجز: فترة الإرشاد، موعد فتح الحجز، المهلة، منع التعارض،
--     الحد اليومي، والفاصل مع المرشد نفسه
--   • منع تداخل مواعيد المرشد، وحصر المواعيد في أيام الإرشاد
--   • عروض المتابعة الحية وملخص تقييم المرشدين
--   الحجز يُؤكَّد تلقائيًا كما في إنفاذ (لا ينتظر موافقة المرشد).
-- ============================================================

alter table public.mentor_bookings add column if not exists held_at timestamptz;
alter table public.mentor_bookings add column if not exists held_by uuid references public.profiles(id) on delete set null;
alter table public.mentor_bookings alter column status set default 'confirmed';
alter table public.mentor_ratings add column if not exists session_held boolean default true;

insert into public.platform_settings (key, value) values
  ('booking_opens_at', ''), ('booking_lead_minutes', '0'), ('max_bookings_per_day', '10'),
  ('allow_same_mentor_gap', '0'), ('same_mentor_gap_hours', '0')
on conflict (key) do nothing;

-- ---------- حالة الجلسة ----------
create or replace function public.session_state(p_end_time timestamptz, p_status text, p_held_at timestamptz)
returns text language sql stable as $$
  select case when p_status = 'cancelled' then 'cancelled'
              when p_held_at is not null then 'held'
              when p_end_time > now() then 'pending'
              else 'unconfirmed' end;
$$;

create or replace function public.confirm_session_held(p_booking_id uuid, p_held boolean default true)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_mentor uuid; v_start timestamptz;
begin
  select s.mentor_user_id, s.start_time into v_mentor, v_start
  from public.mentor_bookings b join public.mentor_slots s on s.id = b.slot_id where b.id = p_booking_id;
  if v_mentor is null then return jsonb_build_object('success', false, 'error', 'الحجز غير موجود'); end if;
  if not (v_mentor = auth.uid() or public.has_role('admin') or public.has_role('coordinator')) then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل');
  end if;
  if p_held and v_start > now() then
    return jsonb_build_object('success', false, 'error', 'يمكن التأكيد بعد بدء وقت الجلسة');
  end if;
  update public.mentor_bookings
  set held_at = case when p_held then now() end, held_by = case when p_held then auth.uid() end
  where id = p_booking_id;
  return jsonb_build_object('success', true, 'held', p_held);
end;
$$;
revoke execute on function public.confirm_session_held(uuid, boolean) from anon;

-- تقييم الفريق بأن الجلسة لم تُعقد يلغي الحجز
create or replace function public.handle_session_not_held()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.session_held = false then
    update public.mentor_bookings set status = 'cancelled' where id = new.booking_id and status <> 'cancelled';
  end if;
  return new;
exception when others then return new;
end;
$$;
create or replace trigger trg_session_not_held after insert on public.mentor_ratings
  for each row execute function public.handle_session_not_held();

-- ---------- نافذة الحجز ----------
create or replace function public.enforce_booking_window()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_opens timestamptz; v_lead int; v_start timestamptz; v_end timestamptz; v_mentor uuid;
        v_max_day int; v_today_ct int; v_clash int; v_no_repeat int; v_gap_h int;
begin
  if public.has_role('admin') or public.has_role('coordinator') then return new; end if;

  select s.start_time, s.end_time, s.mentor_user_id into v_start, v_end, v_mentor
  from public.mentor_slots s where s.id = new.slot_id;

  if exists (select 1 from public.program_days where phase = 'mentorship') then
    if not exists (select 1 from public.program_days where phase = 'mentorship' and now() between starts_at and ends_at) then
      raise exception 'الحجز متاح خلال فترة الإرشاد فقط';
    end if;
  end if;

  select nullif(btrim(value), '')::timestamptz into v_opens from public.platform_settings where key = 'booking_opens_at';
  if v_opens is not null and now() < v_opens then
    raise exception 'الحجز يفتح في %', to_char(v_opens at time zone 'Asia/Riyadh', 'DD/MM/YYYY HH24:MI');
  end if;

  select coalesce(nullif(btrim(value), '')::int, 0) into v_lead from public.platform_settings where key = 'booking_lead_minutes';
  if coalesce(v_lead, 0) > 0 and v_start is not null and v_start < now() + (v_lead || ' minutes')::interval then
    raise exception 'يجب الحجز قبل الموعد بـ% دقيقة على الأقل', v_lead;
  end if;

  select count(*) into v_clash from public.mentor_bookings b join public.mentor_slots s on s.id = b.slot_id
  where b.team_id = new.team_id and b.status <> 'cancelled' and s.start_time < v_end and s.end_time > v_start;
  if v_clash > 0 then raise exception 'لديكم موعد آخر في نفس التوقيت'; end if;

  select coalesce(nullif(btrim(value), '')::int, 6) into v_max_day from public.platform_settings where key = 'max_bookings_per_day';
  select count(*) into v_today_ct from public.mentor_bookings b join public.mentor_slots s on s.id = b.slot_id
  where b.team_id = new.team_id and b.status <> 'cancelled'
    and (s.start_time at time zone 'Asia/Riyadh')::date = (v_start at time zone 'Asia/Riyadh')::date;
  if v_max_day > 0 and v_today_ct >= v_max_day then
    raise exception 'بلغتم الحد الأقصى للجلسات في هذا اليوم (% جلسات)', v_max_day;
  end if;

  select coalesce(nullif(btrim(value), '')::int, 1) into v_no_repeat from public.platform_settings where key = 'allow_same_mentor_gap';
  select coalesce(nullif(btrim(value), '')::int, 3) into v_gap_h from public.platform_settings where key = 'same_mentor_gap_hours';
  if v_no_repeat = 1 and v_gap_h > 0 and v_mentor is not null then
    if exists (select 1 from public.mentor_bookings b join public.mentor_slots s on s.id = b.slot_id
               where b.team_id = new.team_id and b.status <> 'cancelled' and s.mentor_user_id = v_mentor
                 and s.end_time > v_start - (v_gap_h || ' hours')::interval
                 and s.start_time < v_end + (v_gap_h || ' hours')::interval) then
      raise exception 'لديكم جلسة قريبة مع المرشد نفسه. اختاروا مرشدًا آخر أو وقتًا أبعد بـ% ساعات', v_gap_h;
    end if;
  end if;

  return new;
exception when invalid_datetime_format then return new;
end;
$$;
create or replace trigger trg_enforce_booking_window before insert on public.mentor_bookings
  for each row execute function public.enforce_booking_window();

-- ---------- مواعيد المرشد ----------
create or replace function public.enforce_mentorship_hours()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.has_role('admin') or public.has_role('coordinator') then return new; end if;
  if exists (select 1 from public.program_days where phase = 'mentorship') then
    if not exists (select 1 from public.program_days
                   where phase = 'mentorship' and new.start_time >= starts_at and new.end_time <= ends_at) then
      raise exception 'الموعد خارج أيام الإرشاد المحددة';
    end if;
  end if;
  return new;
end;
$$;
create or replace trigger trg_enforce_mentorship_hours before insert or update on public.mentor_slots
  for each row execute function public.enforce_mentorship_hours();

create or replace function public.prevent_slot_overlap()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_clash record;
begin
  if new.start_time is null or new.end_time is null then return new; end if;
  if new.end_time <= new.start_time then raise exception 'وقت النهاية يجب أن يكون بعد وقت البداية'; end if;
  if tg_op = 'UPDATE' and new.start_time is not distinct from old.start_time
     and new.end_time is not distinct from old.end_time
     and new.mentor_user_id is not distinct from old.mentor_user_id then
    return new;
  end if;
  select s.start_time, s.end_time into v_clash from public.mentor_slots s
  where s.mentor_user_id = new.mentor_user_id and s.id is distinct from new.id
    and s.start_time < new.end_time and s.end_time > new.start_time
  limit 1;
  if found then
    raise exception 'يتداخل هذا الموعد مع موعد قائم لديكم (% — %)',
      to_char(v_clash.start_time at time zone 'Asia/Riyadh', 'HH24:MI'),
      to_char(v_clash.end_time at time zone 'Asia/Riyadh', 'HH24:MI');
  end if;
  return new;
end;
$$;
create or replace trigger trg_prevent_slot_overlap before insert or update on public.mentor_slots
  for each row execute function public.prevent_slot_overlap();

-- ---------- إشعار المرشد بالحجز: تفاصيل الفريق (الحجز مؤكَّد تلقائيًا) ----------
create or replace function public.notify_mentor_booking()
returns trigger as $$
declare v_team_name text; v_mentor_id uuid; v_mentor_name text; v_slot_time timestamptz; v_brief jsonb;
begin
  select team_name into v_team_name from public.teams where id = new.team_id;
  select mentor_user_id, start_time into v_mentor_id, v_slot_time from public.mentor_slots where id = new.slot_id;
  select full_name into v_mentor_name from public.profiles where id = v_mentor_id;
  v_brief := public.team_brief(new.team_id);

  insert into public.notifications (user_id, title, body)
  select tm.user_id, 'تأكيد حجز جلسة إرشاد',
         'نفيدكم بأنه تم حجز جلسة إرشاد لفريق «' || v_team_name || '» مع المرشد/ة '
         || coalesce(v_mentor_name, '') || '، يوم ' || public.ar_datetime(v_slot_time) || '.'
         || chr(10) || chr(10) || 'يُرجى الحضور في الموعد المحدد.'
  from public.team_members tm where tm.team_id = new.team_id;

  if v_mentor_id is not null then
    insert into public.notifications (user_id, title, body)
    values (v_mentor_id, 'حجز جديد لجلسة إرشاد',
      'نفيدكم بأن فريق «' || v_team_name || '» قد حجز جلسة إرشاد معكم، يوم ' || public.ar_datetime(v_slot_time) || '.'
      || chr(10) || chr(10) || 'رقم الفريق: ' || coalesce(v_brief->>'code', '—')
      || chr(10) || 'المسار: ' || coalesce(nullif(v_brief->>'track', ''), '—')
      || chr(10) || 'المشروع: ' || coalesce(nullif(v_brief->>'project', ''), '—')
      || coalesce(chr(10) || 'موضوع الجلسة: ' || nullif(btrim(new.requested_topic), ''), ''));
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

-- ---------- العروض ----------
create or replace view public.available_mentor_slots with (security_invoker = on) as
select ms.id, ms.mentor_user_id, p.full_name as "اسم_المرشد", p.specialization as "التخصص", p.avatar_url as "الصورة",
       ms.start_time, ms.end_time, ms.location, ms.is_online, ms.meeting_url
from public.mentor_slots ms join public.profiles p on p.id = ms.mentor_user_id
where not coalesce(ms.is_booked, false) and ms.start_time > now() and coalesce(p.is_active, true)
  and (not public.mentor_presence_required() or public.is_mentor_present_today(p.id))
  and (not exists (select 1 from public.program_days where phase = 'mentorship')
       or exists (select 1 from public.program_days where phase = 'mentorship' and now() between starts_at and ends_at));

create or replace view public.mentor_profiles as
select p.id, p.full_name as "الاسم", p.avatar_url as "الصورة", p.specialization as "التخصص",
       p.current_position as "المنصب", p.organization as "الجهة", p.bio as "نبذة", coalesce(p.is_active, true) as "نشط",
       (select count(*) from public.mentor_slots ms where ms.mentor_user_id = p.id
          and not coalesce(ms.is_booked, false) and ms.start_time > now()) as "مواعيد_متاحة",
       (select count(distinct b.team_id) from public.mentor_slots ms join public.mentor_bookings b on b.slot_id = ms.id
        where ms.mentor_user_id = p.id and b.status <> 'cancelled') as "فرق_أرشدها"
from public.profiles p
where exists (select 1 from public.user_roles ur join public.roles r on r.id = ur.role_id
              where ur.user_id = p.id and r.key = 'mentor')
  and coalesce(p.is_active, true);
revoke all on public.mentor_profiles from anon;

create or replace view public.mentor_rating_summary with (security_invoker = on) as
select p.id as mentor_user_id, p.full_name as "المرشد",
       count(*) filter (where r.session_held) as "جلسات_منعقدة",
       count(*) filter (where not r.session_held) as "لم_تُعقد",
       round(avg(r.rating) filter (where r.session_held), 2) as "متوسط_الاستفادة",
       round(avg(r.specialty_fit_rating) filter (where r.session_held), 2) as "متوسط_الملاءمة"
from public.profiles p join public.mentor_ratings r on r.mentor_user_id = p.id
group by p.id, p.full_name;

create or replace view public.mentorship_admin_detail with (security_invoker = on) as
select p.id as mentor_id, p.full_name as "المرشد", p.specialization as "التخصص",
       public.is_mentor_present_today(p.id) as "حاضر_اليوم",
       (select count(*) from public.mentor_slots s where s.mentor_user_id = p.id) as "إجمالي_المواعيد",
       (select count(*) from public.mentor_slots s where s.mentor_user_id = p.id
          and not coalesce(s.is_booked, false) and s.start_time > now()) as "متاحة_الآن",
       (select count(*) from public.mentor_bookings b join public.mentor_slots s on s.id = b.slot_id
        where s.mentor_user_id = p.id and b.status <> 'cancelled') as "محجوزة",
       (select count(*) from public.mentor_bookings b join public.mentor_slots s on s.id = b.slot_id
        where s.mentor_user_id = p.id and b.status <> 'cancelled' and s.end_time < now()) as "منتهية",
       (select round(avg(r.rating), 2) from public.mentor_ratings r where r.mentor_user_id = p.id and r.session_held) as "متوسط_التقييم",
       (select count(*) from public.mentor_ratings r where r.mentor_user_id = p.id and not r.session_held) as "لم_تُعقد"
from public.profiles p
join public.user_roles ur on ur.user_id = p.id
join public.roles r2 on r2.id = ur.role_id and r2.key = 'mentor'
where coalesce(p.is_active, true);

create or replace view public.mentorship_health with (security_invoker = on) as
select (select count(*) from public.profiles p join public.user_roles ur on ur.user_id = p.id
          join public.roles r on r.id = ur.role_id and r.key = 'mentor') as "إجمالي_المرشدين",
       (select count(*) from public.profiles p join public.user_roles ur on ur.user_id = p.id
          join public.roles r on r.id = ur.role_id and r.key = 'mentor' where public.is_mentor_present_today(p.id)) as "حاضرون_اليوم",
       (select count(*) from public.mentor_slots s where not coalesce(s.is_booked, false) and s.start_time > now()
          and (not public.mentor_presence_required() or public.is_mentor_present_today(s.mentor_user_id))) as "مواعيد_ظاهرة",
       exists (select 1 from public.program_days where phase = 'mentorship' and now() between starts_at and ends_at) as "فترة_الإرشاد_جارية";

-- ملخص حي (أرقام إجمالية فقط) — لا يُعرض لغير المسجّلين
create or replace view public.mentorship_live_summary as
select (select count(*) from public.profiles p join public.user_roles ur on ur.user_id = p.id
          join public.roles r on r.id = ur.role_id and r.key = 'mentor' where coalesce(p.is_active, true)) as "إجمالي_المرشدين",
       (select count(*) from public.profiles p join public.user_roles ur on ur.user_id = p.id
          join public.roles r on r.id = ur.role_id and r.key = 'mentor'
        where coalesce(p.is_active, true) and public.is_mentor_present_today(p.id)) as "المرشدون_الحاضرون",
       (select count(*) from public.mentor_bookings b join public.mentor_slots s on s.id = b.slot_id
        where b.status <> 'cancelled' and (s.start_time at time zone 'Asia/Riyadh')::date = (now() at time zone 'Asia/Riyadh')::date) as "جلسات_اليوم",
       (select count(*) from public.mentor_bookings b join public.mentor_slots s on s.id = b.slot_id
        where b.status <> 'cancelled' and s.start_time <= now() and s.end_time > now()) as "جلسات_جارية",
       (select count(*) from public.mentor_bookings b join public.mentor_slots s on s.id = b.slot_id
        where b.status <> 'cancelled' and s.end_time < now()) as "جلسات_منتهية",
       (select count(*) from public.mentor_slots s where not coalesce(s.is_booked, false) and s.start_time > now()
          and (not public.mentor_presence_required() or public.is_mentor_present_today(s.mentor_user_id))) as "مواعيد_متاحة",
       (select count(*) from public.teams where status = 'confirmed') as "إجمالي_الفرق",
       (select count(distinct b.team_id) from public.mentor_bookings b where b.status <> 'cancelled') as "فرق_استفادت",
       (select round(avg(rating), 2) from public.mentor_ratings where session_held) as "متوسط_التقييم",
       exists (select 1 from public.program_days where phase = 'mentorship' and now() between starts_at and ends_at) as "الإرشاد_جارٍ",
       now() as "وقت_التحديث";
revoke all on public.mentorship_live_summary from anon;

create or replace view public.mentorship_by_track as
select tr.name_ar as "المسار", count(distinct t.id) as "الفرق",
       count(b.id) filter (where b.status <> 'cancelled') as "الجلسات",
       count(distinct b.team_id) filter (where b.status <> 'cancelled') as "فرق_استفادت"
from public.tracks tr
left join public.teams t on t.track_id = tr.id and t.status = 'confirmed'
left join public.mentor_bookings b on b.team_id = t.id
where tr.is_active
group by tr.id, tr.name_ar, tr.display_order
order by tr.display_order;
revoke all on public.mentorship_by_track from anon;

create or replace view public.mentorship_timeline with (security_invoker = on) as
with hours as (
  select generate_series(
    date_trunc('hour', least((select min(start_time) from public.mentor_slots
                              where (start_time at time zone 'Asia/Riyadh')::date = (now() at time zone 'Asia/Riyadh')::date), now())),
    date_trunc('hour', greatest((select max(start_time) from public.mentor_slots
                              where (start_time at time zone 'Asia/Riyadh')::date = (now() at time zone 'Asia/Riyadh')::date), now())),
    interval '1 hour') as h
)
select to_char(h.h at time zone 'Asia/Riyadh', 'HH24:MI') as "الساعة",
       extract(hour from h.h at time zone 'Asia/Riyadh')::int as "ساعة_رقمية",
       count(s.id) as "مواعيد",
       count(s.id) filter (where b.id is not null and b.status <> 'cancelled') as "محجوزة",
       count(s.id) filter (where b.id is null) as "متاحة",
       h.h <= now() and now() < h.h + interval '1 hour' as "الساعة_الحالية"
from hours h
left join public.mentor_slots s on s.start_time >= h.h and s.start_time < h.h + interval '1 hour'
left join public.mentor_bookings b on b.slot_id = s.id
group by h.h order by h.h;

create or replace view public.mentorship_upcoming with (security_invoker = on) as
select s.start_time, s.end_time, p.full_name as "المرشد", t.team_name as "الفريق", t.team_code as "رمز_الفريق",
       tr.name_ar as "المسار", s.location, s.is_online,
       case when b.status = 'cancelled' then 'ملغاة' when s.end_time < now() then 'منتهية'
            when s.start_time <= now() then 'جارية' else 'قادمة' end as "الحالة"
from public.mentor_bookings b
join public.mentor_slots s on s.id = b.slot_id
join public.teams t on t.id = b.team_id
left join public.tracks tr on tr.id = t.track_id
left join public.profiles p on p.id = s.mentor_user_id
where b.status <> 'cancelled' and s.end_time > now() - interval '3 hours'
order by s.start_time limit 50;

create or replace view public.mentorship_coverage with (security_invoker = on) as
select count(*) as "إجمالي_الفرق",
       count(*) filter (where exists (select 1 from public.mentor_bookings b where b.team_id = t.id and b.status <> 'cancelled')) as "فرق_حجزت",
       count(*) filter (where not exists (select 1 from public.mentor_bookings b where b.team_id = t.id and b.status <> 'cancelled')) as "فرق_بلا_إرشاد",
       case when count(*) = 0 then 0 else round(count(*) filter (where exists (
         select 1 from public.mentor_bookings b where b.team_id = t.id and b.status <> 'cancelled'))::numeric / count(*) * 100) end as "نسبة_التغطية"
from public.teams t where status = 'confirmed';

create or replace view public.teams_without_mentorship with (security_invoker = on) as
select t.id as team_id, t.team_name as "الفريق", t.team_code as "رمز_الفريق", tr.name_ar as "المسار",
       (select count(*) from public.mentor_bookings b where b.team_id = t.id) as "حجوزات_كلية",
       (select count(*) from public.mentor_bookings b where b.team_id = t.id and b.status <> 'cancelled') as "حجوزات_قائمة",
       case when not exists (select 1 from public.mentor_bookings b where b.team_id = t.id) then 'لم يحجز قط'
            when not exists (select 1 from public.mentor_bookings b where b.team_id = t.id and b.status <> 'cancelled') then 'ألغى كل حجوزاته'
            else 'لديه حجوزات' end as "الحالة"
from public.teams t left join public.tracks tr on tr.id = t.track_id
where t.status = 'confirmed'
  and not exists (select 1 from public.mentor_bookings b where b.team_id = t.id and b.status <> 'cancelled')
order by tr.name_ar, t.team_code;

create or replace view public.unconfirmed_sessions with (security_invoker = on) as
select b.id as booking_id, p.full_name as "المرشد", t.team_name as "الفريق", t.team_code as "رمز_الفريق",
       s.start_time, s.end_time,
       to_char(s.start_time at time zone 'Asia/Riyadh', 'DD/MM HH24:MI') as "الموعد",
       (select count(*) from public.mentor_feedback f where f.booking_id = b.id) > 0 as "لها_ملاحظات"
from public.mentor_bookings b
join public.mentor_slots s on s.id = b.slot_id
left join public.teams t on t.id = b.team_id
left join public.profiles p on p.id = s.mentor_user_id
where b.status <> 'cancelled' and b.held_at is null and s.end_time < now()
order by s.start_time desc;

create or replace view public.team_bookings_view with (security_invoker = on) as
select b.id, b.team_id, b.slot_id, b.status, b.requested_topic, s.start_time, s.end_time, s.location, s.is_online,
       s.meeting_url, s.mentor_user_id, p.full_name as "اسم_المرشد", p.specialization as "تخصص_المرشد",
       case when b.status = 'cancelled' then 'ملغاة' when s.end_time < now() then 'منتهية'
            when s.start_time <= now() then 'جارية الآن' else 'قادمة' end as "حالة_الجلسة",
       s.end_time < now() as "انتهت",
       exists (select 1 from public.mentor_ratings r where r.booking_id = b.id) as "قُيّمت"
from public.mentor_bookings b
join public.mentor_slots s on s.id = b.slot_id
left join public.profiles p on p.id = s.mentor_user_id;

revoke select on public.available_mentor_slots, public.mentor_rating_summary, public.mentorship_admin_detail,
  public.mentorship_health, public.mentorship_timeline, public.mentorship_upcoming, public.mentorship_coverage,
  public.teams_without_mentorship, public.unconfirmed_sessions, public.team_bookings_view from anon;

-- (80) الجلسة التي لم تُعقد تُسجَّل بلا تقييم؛ التقييم إلزامي فقط للجلسة المنعقدة
alter table public.mentor_ratings alter column rating drop not null;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'mentor_ratings_rating_required_if_held') then
    alter table public.mentor_ratings add constraint mentor_ratings_rating_required_if_held
      check (session_held = false or rating is not null);
  end if;
end $$;
