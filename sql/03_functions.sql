-- ============================================================
-- منصة هاكثون السيرة النبوية - دوال وViews مساعدة
-- ============================================================
-- يُطبّق بعد 02_rls_policies.sql
-- ============================================================

-- ------------------------------------------------------------
-- 1. دالة: التحقق من أهلية إصدار شهادة معينة لمستخدم
-- تُستخدم من Edge Function عند طلب إصدار الشهادة (self-service)
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
begin
  select * into v_cert_type from public.certificate_types where key = p_cert_type_key;
  if not found then
    return jsonb_build_object('eligible', false, 'reason', 'نوع الشهادة غير موجود');
  end if;

  select count(*) into v_total_events from public.events;
  select count(*) into v_attended_events
    from public.event_attendance where user_id = p_user_id;

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
$$ language plpgsql security definer;

-- ------------------------------------------------------------
-- 2. دالة: إصدار شهادة (بعد التحقق من الأهلية)
-- ------------------------------------------------------------
create or replace function public.issue_certificate(
  p_cert_type_key text
) returns jsonb as $$
declare
  v_user_id uuid := auth.uid();
  v_cert_type record;
  v_eligibility jsonb;
  v_cert_id uuid;
begin
  select * into v_cert_type from public.certificate_types where key = p_cert_type_key;
  if not found then
    return jsonb_build_object('success', false, 'error', 'نوع الشهادة غير موجود');
  end if;

  v_eligibility := public.check_certificate_eligibility(v_user_id, p_cert_type_key);

  if not (v_eligibility->>'eligible')::boolean then
    return jsonb_build_object('success', false, 'error', 'الشروط غير مكتملة', 'details', v_eligibility);
  end if;

  insert into public.certificates (user_id, cert_type_id)
  values (v_user_id, v_cert_type.id)
  on conflict (user_id, cert_type_id) do nothing
  returning id into v_cert_id;

  if v_cert_id is null then
    select id into v_cert_id from public.certificates
      where user_id = v_user_id and cert_type_id = v_cert_type.id;
    return jsonb_build_object('success', true, 'certificate_id', v_cert_id, 'note', 'الشهادة صادرة مسبقًا');
  end if;

  return jsonb_build_object('success', true, 'certificate_id', v_cert_id);
end;
$$ language plpgsql security definer;

-- ------------------------------------------------------------
-- 3. دالة: تعليم تعارض المصالح تلقائيًا عند تشابه الجهة
-- (تُشغَّل يدويًا من لوحة التحكم أو عبر trigger عند إضافة تعيين)
-- ------------------------------------------------------------
create or replace function public.flag_judge_conflicts()
returns trigger as $$
declare
  v_judge_org text;
  v_team_has_match boolean;
begin
  select organization into v_judge_org from public.profiles where id = new.judge_user_id;

  select exists (
    select 1 from public.team_members tm
    join public.profiles p on p.id = tm.user_id
    where tm.team_id = new.team_id and p.organization = v_judge_org and v_judge_org is not null
  ) into v_team_has_match;

  if v_team_has_match then
    new.has_conflict := true;
    new.conflict_reason := 'تطابق الجهة مع أحد أعضاء الفريق';
  end if;

  return new;
end;
$$ language plpgsql security definer;

create trigger trg_flag_judge_conflicts
  before insert on public.judge_assignments
  for each row execute function public.flag_judge_conflicts();

-- ------------------------------------------------------------
-- 4. View: نتائج التحكيم المجمّعة لكل فريق (بالوزن)
-- ------------------------------------------------------------
create or replace view public.team_scores_summary as
select
  s.team_id,
  s.round_id,
  jr.name_ar as round_name,
  t.team_name,
  tr.name_ar as track_name,
  sum(s.score * jc.weight) / nullif(sum(jc.weight), 0) as weighted_average,
  count(distinct s.judge_user_id) as judges_count
from public.scores s
join public.judging_criteria jc on jc.id = s.criteria_id
join public.judging_rounds jr on jr.id = s.round_id
join public.teams t on t.id = s.team_id
join public.tracks tr on tr.id = t.track_id
group by s.team_id, s.round_id, jr.name_ar, t.team_name, tr.name_ar;

-- ------------------------------------------------------------
-- 5. View: إحصائيات لوحة التحكم الإدارية العامة
-- ------------------------------------------------------------
create or replace view public.dashboard_stats as
select
  (select count(*) from public.profiles) as total_users,
  (select count(*) from public.teams where status = 'confirmed') as confirmed_teams,
  (select count(*) from public.teams) as total_teams,
  (select count(distinct user_id) from public.team_members) as total_participants,
  (select count(*) from public.tracks where is_active = true) as active_tracks,
  (select count(*) from public.certificates) as certificates_issued,
  (select round(avg(nps_score), 1) from public.survey_responses where nps_score is not null) as avg_nps;

-- ------------------------------------------------------------
-- 6. View: تفصيل الرضا حسب مرحلة الاستبيان (لقياس رضا المشاركين)
-- ------------------------------------------------------------
create or replace view public.satisfaction_by_stage as
select
  s.target_stage,
  s.title as survey_title,
  count(sr.id) as responses_count,
  round(avg(sr.nps_score), 2) as avg_nps,
  round(
    100.0 * count(*) filter (where sr.nps_score >= 9) / nullif(count(sr.nps_score), 0), 1
  ) as promoters_pct,
  round(
    100.0 * count(*) filter (where sr.nps_score <= 6) / nullif(count(sr.nps_score), 0), 1
  ) as detractors_pct
from public.surveys s
left join public.survey_responses sr on sr.survey_id = s.id
group by s.id, s.target_stage, s.title;

-- ------------------------------------------------------------
-- 7. View: نسبة الحضور لكل مستخدم (تُستخدم لعرض تقدمه بلوحته الشخصية)
-- ------------------------------------------------------------
create or replace view public.user_attendance_summary as
select
  p.id as user_id,
  p.full_name,
  count(distinct e.id) as total_events,
  count(distinct ea.event_id) as attended_events,
  round(
    100.0 * count(distinct ea.event_id) / nullif(count(distinct e.id), 0), 1
  ) as attendance_pct
from public.profiles p
cross join public.events e
left join public.event_attendance ea on ea.event_id = e.id and ea.user_id = p.id
group by p.id, p.full_name;
