-- ============================================================
-- إكمال مرحلة التسجيل والمشاركين: صلاحيات ناقصة + فرض قيود المسار
-- ============================================================
-- يُطبّق بعد 32_track_capacity_and_active_day.sql
-- ============================================================

-- ------------------------------------------------------------
-- 1. صلاحية تعديل عضوية الفريق (لازمة لنقل القيادة)
--    لم تكن موجودة أصلًا — القائد ما كان يقدر يعدّل is_leader لأي أحد
-- ------------------------------------------------------------
create policy "team_members_update_leader_or_admin" on public.team_members
  for update using (
    exists (select 1 from public.team_members tm
            where tm.team_id = team_members.team_id and tm.user_id = auth.uid() and tm.is_leader = true)
    or public.has_role('admin')
  );

-- ------------------------------------------------------------
-- 2. دالة نقل القيادة (تضمن يوجد قائد واحد بالضبط دائمًا)
-- ------------------------------------------------------------
create or replace function public.transfer_team_leadership(p_team_id uuid, p_new_leader_id uuid)
returns jsonb as $$
begin
  if not (
    exists (select 1 from public.team_members where team_id = p_team_id and user_id = auth.uid() and is_leader = true)
    or public.has_role('admin')
  ) then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل — فقط قائد الفريق يقدر ينقل القيادة');
  end if;

  if not exists (select 1 from public.team_members where team_id = p_team_id and user_id = p_new_leader_id) then
    return jsonb_build_object('success', false, 'error', 'هذا الشخص ليس عضوًا بالفريق');
  end if;

  update public.team_members set is_leader = false where team_id = p_team_id and is_leader = true;
  update public.team_members set is_leader = true where team_id = p_team_id and user_id = p_new_leader_id;

  return jsonb_build_object('success', true);
end;
$$ language plpgsql security definer set search_path = public;

-- ------------------------------------------------------------
-- 3. فرض قيود المسار (مفتوح/سعة) عند إنشاء فريق جديد
--    (كانت الدالة القديمة تنشئ الفريق بدون أي تحقق من حالة المسار)
-- ------------------------------------------------------------
create or replace function public.create_team_with_leader(
  p_track_id uuid,
  p_team_name text
) returns jsonb as $$
declare
  v_user_id uuid := auth.uid();
  v_team_id uuid;
  v_result jsonb;
  v_track record;
  v_current_count int;
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

  select * into v_track from public.tracks where id = p_track_id;
  if v_track.id is null then
    return jsonb_build_object('success', false, 'error', 'المسار غير موجود');
  end if;
  if not v_track.registration_open then
    return jsonb_build_object('success', false, 'error', 'التسجيل بهذا المسار مغلق حاليًا');
  end if;
  if v_track.max_participants is not null then
    v_current_count := public.get_track_participant_count(p_track_id);
    if v_current_count >= v_track.max_participants then
      return jsonb_build_object('success', false, 'error', 'اكتملت السعة القصوى لهذا المسار');
    end if;
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

-- ------------------------------------------------------------
-- 4. نفس الفحص بدالة الانضمام برمز الدعوة (سعة الفريق موجودة أصلًا،
--    نضيف فحص حالة المسار نفسه أيضًا)
-- ------------------------------------------------------------
create or replace function public.join_team_with_code(
  p_invite_code text
) returns jsonb as $$
declare
  v_user_id uuid := auth.uid();
  v_team record;
  v_current_count int;
  v_track record;
begin
  if v_user_id is null then
    return jsonb_build_object('success', false, 'error', 'يجب تسجيل الدخول أولاً');
  end if;

  if exists (select 1 from public.team_members where user_id = v_user_id) then
    return jsonb_build_object('success', false, 'error', 'أنت عضو بفريق آخر بالفعل');
  end if;

  select t.id, t.team_name, t.track_id, tr.max_team_size, tr.registration_open
  into v_team
  from public.teams t
  join public.tracks tr on tr.id = t.track_id
  where t.invite_code = lower(trim(p_invite_code));

  if v_team.id is null then
    return jsonb_build_object('success', false, 'error', 'رمز الدعوة غير صحيح');
  end if;
  if not v_team.registration_open then
    return jsonb_build_object('success', false, 'error', 'التسجيل بمسار هذا الفريق مغلق حاليًا');
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
