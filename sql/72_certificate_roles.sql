-- ============================================================
-- 72: ربط أنواع الشهادات بالأدوار + منع إصدار شهادة لا تخص الدور
-- قبله: role_key فارغ لكل الأنواع، فتظهر كل الشهادات في كل الصفحات،
-- ويستطيع أي مشارك أن يُصدر لنفسه «شهادة الفوز» أو شهادة تقدير للمرشدين.
-- role_key = 'admin' ⇐ تُصدرها الإدارة فقط ولا تظهر في صفحات المستخدمين.
-- لا يغيّر أي سياسة RLS. الإدارة تُصدر أي شهادة لأي مستخدم كما كانت.
-- ============================================================

update public.certificate_types
set role_key = case key
  when 'participation' then 'participant'
  when 'mentor'        then 'mentor'
  when 'judge'         then 'judge'
  when 'winner'        then 'admin'
end
where key in ('participation','mentor','judge','winner') and role_key is null;

create or replace function public.issue_certificate(
  p_cert_type_key text,
  p_user_id uuid default null
) returns jsonb as $$
declare
  v_user_id uuid;
  v_cert_type record;
  v_eligibility jsonb;
begin
  select * into v_cert_type from public.certificate_types where key = p_cert_type_key;
  if not found then
    return jsonb_build_object('success', false, 'error', 'نوع الشهادة غير موجود');
  end if;

  if p_user_id is not null then
    -- إصدار نيابةً عن مستخدم: للإدارة والمنسقين فقط (كما كان)
    if not (public.has_role('admin') or public.has_role('coordinator')) then
      return jsonb_build_object('success', false, 'error', 'غير مخوّل بالإصدار نيابةً عن مستخدم آخر');
    end if;
    v_user_id := p_user_id;
  else
    v_user_id := auth.uid();
    if v_user_id is null then
      return jsonb_build_object('success', false, 'error', 'يجب تسجيل الدخول أولاً');
    end if;
    -- الإصدار الذاتي: الشهادة يجب أن تخص دور المستخدم
    if v_cert_type.role_key = 'admin' then
      return jsonb_build_object('success', false, 'error', 'هذه الشهادة تُصدرها إدارة الهاكثون فقط');
    end if;
    if v_cert_type.role_key is not null and not public.has_role(v_cert_type.role_key) then
      return jsonb_build_object('success', false, 'error', 'هذه الشهادة غير مخصصة لدورك في الهاكثون');
    end if;
    if v_cert_type.role_key = 'participant' and not exists (
      select 1 from public.team_members tm join public.teams t on t.id = tm.team_id
      where tm.user_id = v_user_id and t.status = 'confirmed'
    ) then
      return jsonb_build_object('success', false, 'error', 'شهادة المشاركة متاحة لأعضاء الفرق المعتمدة فقط');
    end if;
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
