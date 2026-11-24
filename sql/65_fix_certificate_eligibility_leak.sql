-- ============================================================
-- إصلاح أمني حرج: تسريب بيانات حضور مستخدمين آخرين
-- ============================================================
-- يُطبّق بعد 64_certificate_badges.sql
--
-- الثغرة: دالة check_certificate_eligibility تقبل p_user_id كمعامل
-- حر بدون أي تحقق من إنه يطابق هوية المتصل (auth.uid()) — يعني
-- أي حساب مسجَّل دخول يقدر يستدعيها بـ UUID شخص ثاني ويشوف نسبة
-- حضوره وأهليته للشهادة، بدون إذنه.
--
-- الإصلاح: الدالة الآن ترفض أي استدعاء يحاول فحص بيانات شخص غير
-- المتصل نفسه، إلا لو المتصل admin أو coordinator.
-- ============================================================

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
  -- الحماية: لا يقدر أي مستخدم يفحص بيانات شخص ثاني، إلا الإدارة
  if p_user_id != auth.uid() and not (public.has_role('admin') or public.has_role('coordinator')) then
    return jsonb_build_object('eligible', false, 'reason', 'غير مخوّل لعرض بيانات مستخدم آخر');
  end if;

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
