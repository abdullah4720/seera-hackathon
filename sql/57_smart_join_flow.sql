-- ============================================================
-- تحسين تجربة التسجيل: معاينة الفريق قبل الانضمام + إشعار تلقائي
-- ============================================================
-- يُطبّق بعد 56_email_alignment.sql
-- ============================================================

-- ------------------------------------------------------------
-- 1. معاينة عامة للفريق برمز الدعوة — بدون تسجيل دخول
--    (تكشف بس: اسم الفريق، المسار، هل مكتمل العدد أم لا —
--    ما تكشف أعضاء الفريق أو أي بيانات حساسة)
-- ------------------------------------------------------------
create or replace function public.get_team_preview_by_code(p_invite_code text)
returns jsonb as $$
declare
  v_team record;
  v_current_count int;
begin
  select t.id, t.team_name, tr.name_ar as track_name, tr.max_team_size, tr.registration_open
  into v_team
  from public.teams t
  join public.tracks tr on tr.id = t.track_id
  where t.invite_code = lower(trim(p_invite_code));

  if v_team.id is null then
    return jsonb_build_object('found', false);
  end if;

  select count(*) into v_current_count from public.team_members where team_id = v_team.id;

  return jsonb_build_object(
    'found', true,
    'team_name', v_team.team_name,
    'track_name', v_team.track_name,
    'is_full', v_current_count >= v_team.max_team_size,
    'registration_open', v_team.registration_open,
    'current_count', v_current_count,
    'max_count', v_team.max_team_size
  );
end;
$$ language plpgsql security definer set search_path = public;

-- السماح لأي زائر (حتى بدون تسجيل دخول) يستدعي هذي الدالة تحديدًا
grant execute on function public.get_team_preview_by_code(text) to anon, authenticated;

-- ------------------------------------------------------------
-- 2. تحديث دالة إنشاء الفريق: إشعار تلقائي فيه رابط الدعوة فور
--    إنشاء الفريق (يُرسَل إيميل تلقائيًا لو Resend مفعّل)
-- ------------------------------------------------------------
create or replace function public.create_team_with_leader(
  p_track_id uuid,
  p_team_name text
) returns jsonb as $$
declare
  v_user_id uuid := auth.uid();
  v_team_id uuid;
  v_invite_code text;
  v_result jsonb;
begin
  if v_user_id is null then
    return jsonb_build_object('success', false, 'error', 'يجب تسجيل الدخول أولاً');
  end if;

  if p_team_name is null or trim(p_team_name) = '' then
    return jsonb_build_object('success', false, 'error', 'اسم الفريق مطلوب');
  end if;

  if exists (select 1 from public.team_members where user_id = v_user_id) then
    return jsonb_build_object('success', false, 'error', 'أنت عضو بفريق آخر بالفعل');
  end if;

  insert into public.teams (track_id, team_name)
  values (p_track_id, trim(p_team_name))
  returning id, invite_code into v_team_id, v_invite_code;

  insert into public.team_members (team_id, user_id, is_leader)
  values (v_team_id, v_user_id, true);

  -- إشعار تلقائي للقائد فيه رابط دعوة جاهز لمشاركته مع زملائه
  insert into public.notifications (user_id, title, body, link)
  values (
    v_user_id,
    'فريقك جاهز — شارك رابط الدعوة',
    'أنشأت فريق "' || trim(p_team_name) || '" بنجاح. انسخ رابط الدعوة أدناه وأرسله لزملائك للانضمام مباشرة.',
    '/registration.html?join=' || v_invite_code
  );

  select jsonb_build_object(
    'success', true,
    'team_id', t.id,
    'team_name', t.team_name,
    'invite_code', t.invite_code,
    'status', t.status
  ) into v_result
  from public.teams t where t.id = v_team_id;

  return v_result;
end;
$$ language plpgsql security definer set search_path = public;
