-- ============================================================
-- إصلاح: دالة موحّدة لإنشاء فريق + إضافة المُنشئ كقائد
-- ============================================================
-- يحل مشكلة تعارض سياسة SELECT مع insert().select() من العميل
-- مباشرة بعد إنشاء الفريق (المستخدم ليس عضوًا بالفريق بعد لحظة الإنشاء)
-- ============================================================

create or replace function public.create_team_with_leader(
  p_track_id uuid,
  p_team_name text
) returns jsonb as $$
declare
  v_user_id uuid := auth.uid();
  v_team_id uuid;
  v_result jsonb;
begin
  if v_user_id is null then
    return jsonb_build_object('success', false, 'error', 'يجب تسجيل الدخول أولاً');
  end if;

  if p_team_name is null or trim(p_team_name) = '' then
    return jsonb_build_object('success', false, 'error', 'اسم الفريق مطلوب');
  end if;

  -- تأكد إن المستخدم مو عضو بفريق آخر أصلاً
  if exists (select 1 from public.team_members where user_id = v_user_id) then
    return jsonb_build_object('success', false, 'error', 'أنت عضو بفريق آخر بالفعل');
  end if;

  insert into public.teams (track_id, team_name)
  values (p_track_id, trim(p_team_name))
  returning id into v_team_id;

  insert into public.team_members (team_id, user_id, is_leader)
  values (v_team_id, v_user_id, true);

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

-- ============================================================
-- إصلاح مشابه: الانضمام لفريق عبر رمز الدعوة بعملية واحدة آمنة
-- ============================================================
create or replace function public.join_team_with_code(
  p_invite_code text
) returns jsonb as $$
declare
  v_user_id uuid := auth.uid();
  v_team record;
  v_current_count int;
begin
  if v_user_id is null then
    return jsonb_build_object('success', false, 'error', 'يجب تسجيل الدخول أولاً');
  end if;

  if exists (select 1 from public.team_members where user_id = v_user_id) then
    return jsonb_build_object('success', false, 'error', 'أنت عضو بفريق آخر بالفعل');
  end if;

  select t.id, t.team_name, tr.max_team_size
  into v_team
  from public.teams t
  join public.tracks tr on tr.id = t.track_id
  where t.invite_code = lower(trim(p_invite_code));

  if v_team.id is null then
    return jsonb_build_object('success', false, 'error', 'رمز الدعوة غير صحيح');
  end if;

  select count(*) into v_current_count from public.team_members where team_id = v_team.id;
  if v_current_count >= v_team.max_team_size then
    return jsonb_build_object('success', false, 'error', 'الفريق مكتمل العدد');
  end if;

  insert into public.team_members (team_id, user_id, is_leader)
  values (v_team.id, v_user_id, false);

  return jsonb_build_object('success', true, 'team_id', v_team.id, 'team_name', v_team.team_name);
end;
$$ language plpgsql security definer set search_path = public;
