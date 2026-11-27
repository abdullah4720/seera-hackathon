-- ============================================================
-- 82) شروط الشهادات والاستبيانات والحضور كما في ابتكار إنفاذ
--   الشهادة: لا تُتاح قبل انتهاء مرحلة محددة، وحد أدنى للجلسات
--   (للمرشد: جلسات منعقدة، وللمحكّم: مشاريع مقيَّمة)، وسبب واضح للمشارك.
--   الاستبيان: موعد فتح وإغلاق، وحد أدنى من الحضور — مطبّق من الخادم.
--   الحضور: نافذة تحضير لكل جلسة، وتحديد ما يُحتسب في نسبة الشهادة،
--   وجلسة حضور تلقائية لكل يوم هاكثون من جدول البرنامج، وإشعار عند التحضير.
--   إضافات السيرة: شهادة المشاركة لأعضاء الفرق المعتمدة فقط، ولا تُتاح
--   إلا بعد نهاية آخر يوم في الهاكثون (وإن لم يُحدَّد الجدول: hackathon_end_date).
-- ============================================================

-- ---------- الأعمدة ----------
alter table public.prep_sessions add column if not exists program_day_id uuid references public.program_days(id) on delete set null;
alter table public.prep_sessions add column if not exists attendance_open boolean default false;
alter table public.prep_sessions add column if not exists counts_for_certificate boolean default true;
alter table public.prep_sessions add column if not exists display_order integer;
-- جلسات أيام الهاكثون تُعرف بـ program_day_id (نوعها prep)، فلا يلزم تعديل قيد النوع

alter table public.surveys add column if not exists opens_at timestamptz;
alter table public.surveys add column if not exists closes_at timestamptz;

alter table public.certificate_types add column if not exists intro_text text;
alter table public.certificate_types add column if not exists signature_label text;
alter table public.certificate_types add column if not exists signature_name text;
alter table public.certificate_types add column if not exists for_role text;
alter table public.certificate_types add column if not exists min_sessions integer default 0;
alter table public.certificate_types add column if not exists opens_after_phase text;

insert into public.platform_settings (key, value) values
  ('survey_min_attendance', '1'),
  ('attendance_title', 'تسجيل حضور'),
  ('attendance_body', 'نفيدكم بأنه تم تسجيل حضوركم في «{{session}}» بتاريخ {{date}}.' || chr(10) || chr(10) || 'نشكر لكم التزامكم، ونتمنى لكم التوفيق.')
on conflict (key) do nothing;

-- شهادة المشاركة: بعد نهاية آخر يوم في الهاكثون (5 ديسمبر)
update public.certificate_types set opens_after_phase = 'hackathon'
where key = 'participation' and opens_after_phase is null;

-- ---------- الحضور ----------
create or replace function public.set_attendance_open(p_session_id uuid, p_open boolean)
returns json language plpgsql security definer set search_path = public as $$
declare v_title text;
begin
  if not (public.has_role('admin') or public.has_role('coordinator')) then
    return json_build_object('success', false, 'error', 'صلاحية غير كافية');
  end if;
  -- is_checkin_active يُحدَّث معه لتعمل صفحة المسح الحالية (scan.html) بالنافذة نفسها
  update public.prep_sessions set attendance_open = p_open, is_checkin_active = p_open
  where id = p_session_id returning title into v_title;
  if v_title is null then return json_build_object('success', false, 'error', 'الجلسة غير موجودة'); end if;
  return json_build_object('success', true, 'title', v_title, 'open', p_open);
end;
$$;
revoke execute on function public.set_attendance_open(uuid, boolean) from anon;

create or replace function public.notify_attendance()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_title text; v_body text; v_session text; v_when timestamptz; v_name text;
begin
  select value into v_title from public.platform_settings where key = 'attendance_title';
  select value into v_body from public.platform_settings where key = 'attendance_body';
  if v_title is null or v_body is null then return null; end if;
  select s.title, s.session_date into v_session, v_when from public.prep_sessions s where s.id = new.session_id;
  select full_name into v_name from public.profiles where id = new.user_id;
  v_body := replace(v_body, '{{session}}', coalesce(v_session, 'الجلسة'));
  v_body := replace(v_body, '{{name}}', coalesce(v_name, ''));
  v_body := replace(v_body, '{{date}}', coalesce(public.ar_datetime(coalesce(v_when, new.checked_in_at), true), ''));
  insert into public.notifications (user_id, title, body, link) values (new.user_id, v_title, v_body, '/registration.html');
  return null;
exception when others then return null;
end;
$$;
create or replace trigger trg_notify_attendance after insert on public.prep_attendance
  for each row execute function public.notify_attendance();

-- جلسة حضور لكل يوم هاكثون في جدول البرنامج
create or replace function public.sync_day_sessions_internal()
returns void language plpgsql security definer set search_path = public as $$
declare d record;
begin
  for d in select * from public.program_days where phase = 'hackathon' order by day_number loop
    if exists (select 1 from public.prep_sessions where program_day_id = d.id) then
      update public.prep_sessions set
        title = 'اليوم ' || d.day_number || ' — الهاكثون',
        session_date = d.starts_at,
        duration_minutes = greatest(1, extract(epoch from (d.ends_at - d.starts_at)) / 60)::int,
        display_order = d.day_number
      where program_day_id = d.id;
    else
      insert into public.prep_sessions (title, session_date, duration_minutes, session_type, program_day_id,
                                        display_order, counts_for_certificate, attendance_open)
      values ('اليوم ' || d.day_number || ' — الهاكثون', d.starts_at,
              greatest(1, extract(epoch from (d.ends_at - d.starts_at)) / 60)::int, 'prep', d.id, d.day_number, true, false);
    end if;
  end loop;
  -- يوم يُحذف من الجدول: تبقى جلسته وحضورها (program_day_id يصبح فارغًا) ويحذفها المدير يدويًا إن أراد
end;
$$;

create or replace function public.trg_sync_day_sessions()
returns trigger language plpgsql security definer set search_path = public as $$
begin perform public.sync_day_sessions_internal(); return null; end;
$$;
create or replace trigger trg_program_days_sync_sessions after insert or delete or update on public.program_days
  for each statement execute function public.trg_sync_day_sessions();

create or replace function public.sync_hackathon_day_sessions()
returns json language plpgsql security definer set search_path = public as $$
declare v_before int; v_after int;
begin
  if not (public.has_role('admin') or public.has_role('coordinator')) then
    return json_build_object('success', false, 'error', 'صلاحية غير كافية');
  end if;
  select count(*) into v_before from public.prep_sessions where program_day_id is not null;
  perform public.sync_day_sessions_internal();
  select count(*) into v_after from public.prep_sessions where program_day_id is not null;
  return json_build_object('success', true, 'day_sessions', v_after, 'changed', v_after - v_before);
end;
$$;
revoke execute on function public.sync_hackathon_day_sessions() from anon;

-- ---------- الاستبيان ----------
create or replace function public.can_take_survey(p_user_id uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare v_min int; v_attended int;
begin
  select coalesce(nullif(btrim(value), '')::int, 1) into v_min from public.platform_settings where key = 'survey_min_attendance';
  if coalesce(v_min, 0) = 0 then return true; end if;
  select count(distinct session_id) into v_attended from public.prep_attendance where user_id = p_user_id;
  select v_attended + count(distinct event_id) into v_attended from public.event_attendance where user_id = p_user_id;
  return v_attended >= v_min;
end;
$$;

create or replace function public.enforce_survey_window()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_opens timestamptz; v_closes timestamptz; v_active boolean; v_min int; v_att int;
begin
  select opens_at, closes_at, is_active into v_opens, v_closes, v_active from public.surveys where id = new.survey_id;
  if not coalesce(v_active, false) then raise exception 'هذا الاستبيان غير متاح حاليًا'; end if;
  if v_opens is not null and now() < v_opens then
    raise exception 'يفتح الاستبيان في %', to_char(v_opens at time zone 'Asia/Riyadh', 'DD/MM/YYYY HH24:MI');
  end if;
  if v_closes is not null and now() > v_closes then raise exception 'أُغلق باب التعبئة'; end if;
  select coalesce(nullif(btrim(value), '')::int, 1) into v_min from public.platform_settings where key = 'survey_min_attendance';
  if coalesce(v_min, 0) > 0 and not public.can_take_survey(new.user_id) then
    select count(distinct session_id) into v_att from public.prep_attendance where user_id = new.user_id;
    raise exception 'يتاح الاستبيان بعد حضور % جلسة على الأقل (حضوركم: %)', v_min, coalesce(v_att, 0);
  end if;
  return new;
end;
$$;
create or replace trigger trg_enforce_survey_window before insert on public.survey_responses
  for each row execute function public.enforce_survey_window();

create or replace view public.my_surveys with (security_invoker = on) as
select s.id, s.title, s.target_stage, s.questions_json, s.is_active, s.gates_certificate_type_id, s.created_at,
       s.opens_at, s.closes_at,
       public.can_take_survey(auth.uid()) as "مستحق",
       (select count(distinct pa.session_id) from public.prep_attendance pa where pa.user_id = auth.uid()) as "حضوري",
       coalesce((select nullif(btrim(value), '')::int from public.platform_settings where key = 'survey_min_attendance'), 1) as "الحضور_المطلوب",
       exists (select 1 from public.survey_responses sr where sr.survey_id = s.id and sr.user_id = auth.uid()) as "عبّأته"
from public.surveys s
where s.is_active and (s.opens_at is null or now() >= s.opens_at) and (s.closes_at is null or now() <= s.closes_at)
  and public.can_take_survey(auth.uid());

create or replace view public.open_surveys with (security_invoker = on) as
select s.id, s.title, s.target_stage, s.questions_json, s.is_active, s.gates_certificate_type_id, s.created_at,
       s.opens_at, s.closes_at,
       case when s.opens_at is not null and now() < s.opens_at then 'لم يُفتح بعد'
            when s.closes_at is not null and now() > s.closes_at then 'أُغلق' else 'متاح' end as "الحالة"
from public.surveys s
where s.is_active and (s.opens_at is null or now() >= s.opens_at) and (s.closes_at is null or now() <= s.closes_at);
revoke select on public.my_surveys, public.open_surveys from anon;

-- ---------- أهلية الشهادة ----------
create or replace function public.check_certificate_eligibility(p_user_id uuid, p_cert_type_key text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_ct record; v_total int := 0; v_attended int := 0; v_pct numeric := 100; v_survey_ok boolean := true;
  v_sessions int := 0; v_phase_ok boolean := true; v_phase_end timestamptz; v_eligible boolean;
  v_reason text; v_role text; v_track_id uuid; v_team_ok boolean := true;
begin
  if p_user_id is distinct from auth.uid() and not (public.has_role('admin') or public.has_role('coordinator')) then
    return jsonb_build_object('eligible', false, 'reason', 'غير مخوّل لعرض بيانات مستخدم آخر');
  end if;
  select * into v_ct from public.certificate_types where key = p_cert_type_key;
  if not found then return jsonb_build_object('eligible', false, 'reason', 'نوع الشهادة غير موجود'); end if;

  -- الدور الذي تُقاس به الشروط: for_role، وإلا دور الشهادة (شهادة الإدارة تُقاس كمشارك)
  v_role := coalesce(nullif(v_ct.for_role, ''), case when v_ct.role_key in ('mentor','judge') then v_ct.role_key else 'participant' end);

  -- لا شهادة قبل انتهاء المرحلة؛ وإن لم يُحدَّد جدولها نرجع لإعداد نهاية المرحلة،
  -- وإن غاب الاثنان تبقى مغلقة (لا تُفتح مبكرًا بالخطأ)
  if nullif(v_ct.opens_after_phase, '') is not null then
    select max(ends_at) into v_phase_end from public.program_days where phase = v_ct.opens_after_phase;
    if v_phase_end is null then
      begin
        select nullif(btrim(value), '')::timestamptz into v_phase_end
        from public.platform_settings where key = v_ct.opens_after_phase || '_end_date';
      exception when others then v_phase_end := null;
      end;
    end if;
    if v_phase_end is null then
      v_phase_ok := false; v_reason := 'تُتاح الشهادة بعد انتهاء المرحلة';
    elsif now() < v_phase_end then
      v_phase_ok := false;
      v_reason := 'تُتاح الشهادة بعد ' || public.ar_datetime(v_phase_end, true);
    end if;
  end if;

  if v_role = 'judge' then
    select count(distinct (team_id, round_id)) into v_sessions from public.scores where judge_user_id = p_user_id;
    if v_sessions < coalesce(v_ct.min_sessions, 0) then
      v_reason := coalesce(v_reason, 'يلزم تقييم ' || v_ct.min_sessions || ' مشروعًا على الأقل (الحالي: ' || v_sessions || ')');
    end if;
  elsif v_role = 'mentor' then
    select count(*) into v_sessions from public.mentor_bookings b join public.mentor_slots s on s.id = b.slot_id
    where s.mentor_user_id = p_user_id and b.status <> 'cancelled' and s.end_time < now();
    if v_sessions < coalesce(v_ct.min_sessions, 0) then
      v_reason := coalesce(v_reason, 'يلزم إتمام ' || v_ct.min_sessions || ' جلسة إرشاد على الأقل (الحالي: ' || v_sessions || ')');
    end if;
  else
    select t.track_id into v_track_id from public.team_members tm join public.teams t on t.id = tm.team_id
    where tm.user_id = p_user_id and t.status = 'confirmed' limit 1;
    v_team_ok := found;
    if not v_team_ok then v_reason := coalesce(v_reason, 'الشهادة لأعضاء الفرق المعتمدة فقط'); end if;

    -- الجلسات المحتسبة فقط، وجلسات المسار أو العامة
    select count(*) into v_total from public.prep_sessions
    where coalesce(counts_for_certificate, true) and (track_id is null or track_id = v_track_id);
    select count(distinct pa.session_id) into v_attended
    from public.prep_attendance pa join public.prep_sessions ps on ps.id = pa.session_id
    where pa.user_id = p_user_id and coalesce(ps.counts_for_certificate, true) and (ps.track_id is null or ps.track_id = v_track_id);
    v_pct := case when v_total = 0 then 100 else (v_attended::numeric / v_total) * 100 end;

    if v_ct.requires_survey then
      select exists (select 1 from public.surveys s join public.survey_responses sr on sr.survey_id = s.id
                     where s.gates_certificate_type_id = v_ct.id and sr.user_id = p_user_id) into v_survey_ok;
      if not v_survey_ok then v_reason := coalesce(v_reason, 'يلزم تعبئة استبيان التقييم'); end if;
    end if;
    if v_pct < coalesce(v_ct.min_attendance_pct, 0) then
      v_reason := coalesce(v_reason, 'نسبة الحضور ' || round(v_pct) || '% والمطلوب ' || round(v_ct.min_attendance_pct) || '%');
    end if;
  end if;

  v_eligible := v_phase_ok and v_team_ok and v_pct >= coalesce(v_ct.min_attendance_pct, 0)
                and v_survey_ok and v_sessions >= coalesce(v_ct.min_sessions, 0);

  return jsonb_build_object(
    'eligible', v_eligible, 'reason', v_reason, 'role', v_role,
    'attendance_pct', round(v_pct, 1), 'required_attendance_pct', coalesce(v_ct.min_attendance_pct, 0),
    'attended', v_attended, 'total_sessions', v_total,
    'sessions', v_sessions, 'required_sessions', coalesce(v_ct.min_sessions, 0),
    'survey_completed', v_survey_ok, 'survey_required', coalesce(v_ct.requires_survey, false),
    'phase_ok', v_phase_ok, 'opens_at', v_phase_end);
end;
$$;

-- مصفوفة حالة الشهادات (للوحة التحكم): الجلسات المحتسبة فقط + حقول النص والتوقيع
create or replace view public.certificate_status_matrix with (security_invoker = on) as
select p.id as user_id, p.full_name, p.email, ct.id as cert_type_id, ct.key as cert_type_key, ct.name_ar as cert_type_name,
       ct.certificate_text, ct.min_attendance_pct, ct.requires_survey,
       coalesce(att.attendance_pct, 100::numeric) as attendance_pct,
       case when ct.requires_survey then coalesce(sv.has_response, false) else true end as survey_ok,
       c.id as certificate_id, c.issued_at, c.verification_code, ct.badge_icon, ct.badge_color,
       ct.intro_text, ct.signature_label, ct.signature_name
from public.profiles p
join public.team_members tm on tm.user_id = p.id
join public.teams t on t.id = tm.team_id and t.status = 'confirmed'
cross join public.certificate_types ct
left join lateral (
  select case when count(ps.id) = 0 then 100::numeric
              else round(100.0 * count(pa.id)::numeric / count(ps.id)::numeric, 2) end as attendance_pct
  from public.prep_sessions ps
  left join public.prep_attendance pa on pa.session_id = ps.id and pa.user_id = p.id
  where coalesce(ps.counts_for_certificate, true) and (ps.track_id is null or ps.track_id = t.track_id)) att on true
left join lateral (
  select exists (select 1 from public.surveys s join public.survey_responses sr on sr.survey_id = s.id
                 where s.gates_certificate_type_id = ct.id and sr.user_id = p.id) as has_response) sv on true
left join public.certificates c on c.user_id = p.id and c.cert_type_id = ct.id;
revoke select on public.certificate_status_matrix from anon;
