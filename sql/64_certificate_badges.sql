-- ============================================================
-- شعارات مميّزة لأنواع الشهادات + إصلاح خلل حرج بأهلية الشهادات
-- ============================================================
-- يُطبّق بعد 63_mentor_rating_criteria.sql
--
-- الجزء الأول: شعار مميّز (أيقونة ولون) لكل نوع شهادة — زي صيف الابتكار
-- عمود is_active موجود أصلًا بالجدول من البداية ومفعَّل بالكامل
-- بواجهة لوحة التحكم، هذا الملف يضيف بس الشعار.
--
-- الجزء الثاني (خلل حرج مُكتشَف): دالة check_certificate_eligibility
-- وعرض certificate_status_matrix كانا لسا يعتمدان على جدولي
-- events/event_attendance القديمين اللي دُمجا بجلسة سابقة داخل
-- prep_sessions/prep_attendance (ملف 62) — يعني حساب نسبة الحضور
-- لأهلية الشهادات كان معطّلاً بصمت من وقتها. نصلحه هنا بالكامل.
-- ============================================================

alter table public.certificate_types add column if not exists badge_icon text default 'award';
alter table public.certificate_types add column if not exists badge_color text default '#C9922A';

comment on column public.certificate_types.badge_icon is 'اسم أيقونة Lucide تُعرض كختم مميّز على الشهادة';
comment on column public.certificate_types.badge_color is 'اللون المصاحب للختم (Hex)';

-- ------------------------------------------------------------
-- إصلاح: دالة أهلية الشهادة — تعتمد الآن على prep_sessions
-- ------------------------------------------------------------
create or replace function public.check_certificate_eligibility(
  p_user_id uuid,
  p_cert_type_key text
) returns jsonb as $$
declare
  v_cert_type record;
  v_total_events int;
  v_attended_events int;
  v_attendance_pct numeric;
  v_survey_ok boolean := true;
  v_eligible boolean;
  v_track_id uuid;
begin
  select * into v_cert_type from public.certificate_types where key = p_cert_type_key;
  if not found then
    return jsonb_build_object('eligible', false, 'reason', 'نوع الشهادة غير موجود');
  end if;

  select t.track_id into v_track_id
  from public.team_members tm join public.teams t on t.id = tm.team_id
  where tm.user_id = p_user_id limit 1;

  select count(*) into v_total_events
    from public.prep_sessions
    where track_id is null or track_id = v_track_id;
  select count(*) into v_attended_events
    from public.prep_attendance pa
    join public.prep_sessions ps on ps.id = pa.session_id
    where pa.user_id = p_user_id and (ps.track_id is null or ps.track_id = v_track_id);

  v_attendance_pct := case when v_total_events = 0 then 100
    else (v_attended_events::numeric / v_total_events::numeric) * 100 end;

  if v_cert_type.requires_survey then
    select exists (
      select 1 from public.surveys s
      join public.survey_responses sr on sr.survey_id = s.id
      where s.gates_certificate_type_id = v_cert_type.id and sr.user_id = p_user_id
    ) into v_survey_ok;
  end if;

  v_eligible := (v_attendance_pct >= v_cert_type.min_attendance_pct) and v_survey_ok;

  return jsonb_build_object(
    'eligible', v_eligible,
    'attendance_pct', round(v_attendance_pct, 1),
    'required_attendance_pct', v_cert_type.min_attendance_pct,
    'survey_completed', v_survey_ok,
    'survey_required', v_cert_type.requires_survey
  );
end;
$$ language plpgsql security definer set search_path = public;

-- ------------------------------------------------------------
-- إصلاح: عرض حالة الشهادات — نفس المنطق المصحَّح + عمودا الشعار
-- ------------------------------------------------------------
create or replace view public.certificate_status_matrix as
select
  p.id as user_id,
  p.full_name,
  p.email,
  ct.id as cert_type_id,
  ct.key as cert_type_key,
  ct.name_ar as cert_type_name,
  ct.certificate_text,
  ct.min_attendance_pct,
  ct.requires_survey,
  coalesce(att.attendance_pct, 100) as attendance_pct,
  case when ct.requires_survey then coalesce(sv.has_response, false) else true end as survey_ok,
  c.id as certificate_id,
  c.issued_at,
  c.verification_code,
  ct.badge_icon,
  ct.badge_color
from public.profiles p
join public.team_members tm on tm.user_id = p.id
join public.teams t on t.id = tm.team_id and t.status = 'confirmed'
cross join public.certificate_types ct
left join lateral (
  select
    case when count(ps.id) = 0 then 100
    else round(100.0 * count(pa.id) / count(ps.id), 2) end as attendance_pct
  from public.prep_sessions ps
  left join public.prep_attendance pa on pa.session_id = ps.id and pa.user_id = p.id
  where ps.track_id is null or ps.track_id = t.track_id
) att on true
left join lateral (
  select exists(
    select 1 from public.surveys s
    join public.survey_responses sr on sr.survey_id = s.id
    where s.gates_certificate_type_id = ct.id and sr.user_id = p.id
  ) as has_response
) sv on true
left join public.certificates c on c.user_id = p.id and c.cert_type_id = ct.id;
