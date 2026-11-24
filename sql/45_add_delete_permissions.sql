-- ============================================================
-- إضافة صلاحيات حذف ناقصة: الفرق والمشاريع
-- ============================================================
-- يُطبّق بعد 44_purge_test_track.sql
--
-- اكتُشف بالتدقيق: جدولا teams وsubmissions ما فيهم أي سياسة
-- حذف إطلاقًا — يعني حتى admin ما كان يقدر يحذف فريق أو مشروع
-- مباشرة قبل هذا الملف
-- ============================================================

create policy "teams_delete_admin" on public.teams
  for delete using (public.has_role('admin') or public.has_role('coordinator'));

create policy "submissions_delete_admin" on public.submissions
  for delete using (public.has_role('admin') or public.has_role('coordinator'));

-- ------------------------------------------------------------
-- دالة إنشاء فريق مباشرة من الإدارة (بدون قائد مبدئي إجباري)
-- ------------------------------------------------------------
create or replace function public.admin_create_team(
  p_track_id uuid,
  p_team_name text,
  p_leader_user_id uuid default null
) returns jsonb as $$
declare
  v_team_id uuid;
begin
  if not (public.has_role('admin') or public.has_role('coordinator')) then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل');
  end if;

  if p_team_name is null or trim(p_team_name) = '' then
    return jsonb_build_object('success', false, 'error', 'اسم الفريق مطلوب');
  end if;

  insert into public.teams (track_id, team_name, status)
  values (p_track_id, trim(p_team_name), 'confirmed')
  returning id into v_team_id;

  if p_leader_user_id is not null then
    if exists (select 1 from public.team_members where user_id = p_leader_user_id) then
      return jsonb_build_object('success', false, 'error', 'هذا المستخدم عضو بفريق آخر بالفعل');
    end if;
    insert into public.team_members (team_id, user_id, is_leader)
    values (v_team_id, p_leader_user_id, true);
  end if;

  return jsonb_build_object('success', true, 'team_id', v_team_id);
end;
$$ language plpgsql security definer set search_path = public;
