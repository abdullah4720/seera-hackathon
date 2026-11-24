-- ============================================================
-- دور "الميسّر" (Facilitator) — صلاحيات مستقلة للتحضير اليومي
-- ============================================================
-- يُطبّق بعد 60_fix_mentor_visibility_root_cause.sql
--
-- الفكرة: دور جديد كامل مستقل عن admin/coordinator، صلاحياته
-- محصورة فقط بتسجيل حضور جلسات التحضير (يدوي + QR) — بدون أي
-- وصول لباقي لوحة التحكم (فرق، مشاريع، تحكيم، إلخ)
-- ============================================================

insert into public.roles (key, name_ar, name_en) values
  ('facilitator', 'ميسّر', 'Facilitator')
on conflict (key) do nothing;

-- ------------------------------------------------------------
-- رؤية المشاركين وفرقهم (لازمة لبناء قائمة الحضور اليدوي)
-- ------------------------------------------------------------
create policy "team_members_select_facilitator" on public.team_members
  for select using (public.has_role('facilitator'));

drop policy if exists "profiles_select_own_or_admin" on public.profiles;
create policy "profiles_select_own_or_admin" on public.profiles
  for select using (
    id = auth.uid()
    or public.has_role('admin')
    or public.has_role('coordinator')
    or public.has_role('mentor')
    or public.has_role('judge')
    or public.has_role('facilitator')
  );

-- ------------------------------------------------------------
-- تسجيل/حذف/رؤية الحضور (يدوي + عبر QR)
-- ------------------------------------------------------------
drop policy if exists "prep_attendance_select" on public.prep_attendance;
create policy "prep_attendance_select" on public.prep_attendance
  for select using (
    user_id = auth.uid() or public.has_role('admin') or public.has_role('coordinator') or public.has_role('facilitator')
  );

drop policy if exists "prep_attendance_insert_own" on public.prep_attendance;
create policy "prep_attendance_insert_own" on public.prep_attendance
  for insert with check (
    user_id = auth.uid() or public.has_role('admin') or public.has_role('coordinator') or public.has_role('facilitator')
  );

create policy "prep_attendance_delete_facilitator" on public.prep_attendance
  for delete using (public.has_role('admin') or public.has_role('coordinator') or public.has_role('facilitator'));

-- ------------------------------------------------------------
-- تحديث دالة تسجيل الحضور عبر QR لتشمل الميسّرين
-- ------------------------------------------------------------
create or replace function public.record_attendance(
  p_session_id uuid,
  p_user_id uuid
) returns jsonb as $$
declare
  v_name text;
  v_already boolean;
begin
  if not (public.has_role('admin') or public.has_role('coordinator') or public.has_role('facilitator')) then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل لتسجيل الحضور');
  end if;

  select full_name into v_name from public.profiles where id = p_user_id;
  if v_name is null then
    return jsonb_build_object('success', false, 'error', 'رمز غير معروف — تأكد من صحة الرمز الممسوح');
  end if;

  select exists(
    select 1 from public.prep_attendance where session_id = p_session_id and user_id = p_user_id
  ) into v_already;

  insert into public.prep_attendance (session_id, user_id)
  values (p_session_id, p_user_id)
  on conflict (session_id, user_id) do nothing;

  return jsonb_build_object('success', true, 'name', v_name, 'already_checked_in', v_already);
end;
$$ language plpgsql security definer set search_path = public;
