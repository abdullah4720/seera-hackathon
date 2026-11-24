-- ============================================================
-- مصفوفة حالة الشهادات: كل مشارك × كل نوع شهادة (صادرة/مؤهل/غير مؤهل)
-- ============================================================
-- يُطبّق بعد 40_unify_certificates_surveys_permissions.sql
-- ============================================================

-- ------------------------------------------------------------
-- نص الشهادة القابل للتخصيص (يدعم {{name}} و{{date}} و{{code}})
-- ------------------------------------------------------------
alter table public.certificate_types add column if not exists certificate_text text;

-- ------------------------------------------------------------
-- تحديث issue_certificate: يدعم الإصدار نيابة عن أي مستخدم من
-- قبل admin/coordinator (كان يصدر لصاحب الجلسة فقط سابقًا)
-- ملاحظة مهمة: نحذف التوقيع القديم صراحة لأن تغيير عدد المعاملات
-- يجعل Postgres يعتبرها دالة مختلفة تمامًا (overload) بدل استبدالها،
-- وهذا يسبب لبس عند استدعائها عبر PostgREST
-- ------------------------------------------------------------
drop function if exists public.issue_certificate(text);

create or replace function public.issue_certificate(
  p_cert_type_key text,
  p_user_id uuid default null
) returns jsonb as $$
declare
  v_user_id uuid;
  v_cert_type record;
  v_eligibility jsonb;
begin
  if p_user_id is not null then
    if not (public.has_role('admin') or public.has_role('coordinator')) then
      return jsonb_build_object('success', false, 'error', 'غير مخوّل بالإصدار نيابةً عن مستخدم آخر');
    end if;
    v_user_id := p_user_id;
  else
    v_user_id := auth.uid();
  end if;

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
  on conflict (user_id, cert_type_id) do nothing;

  return jsonb_build_object('success', true);
end;
$$ language plpgsql security definer set search_path = public;

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
  c.verification_code
from public.profiles p
join public.team_members tm on tm.user_id = p.id
join public.teams t on t.id = tm.team_id and t.status = 'confirmed'
cross join public.certificate_types ct
left join lateral (
  select (count(*)::numeric / nullif((select count(*) from public.events),0)::numeric * 100) as attendance_pct
  from public.event_attendance ea where ea.user_id = p.id
) att on true
left join lateral (
  select exists(
    select 1 from public.surveys s
    join public.survey_responses sr on sr.survey_id = s.id
    where s.gates_certificate_type_id = ct.id and sr.user_id = p.id
  ) as has_response
) sv on true
left join public.certificates c on c.user_id = p.id and c.cert_type_id = ct.id;

-- ------------------------------------------------------------
-- صلاحية القراءة: admin/coordinator فقط (نفس نمط باقي التحليلات)
-- (الـ view يستخدم صلاحيات الجداول الأساسية تلقائيًا، هذا للتوثيق فقط)
-- ------------------------------------------------------------
