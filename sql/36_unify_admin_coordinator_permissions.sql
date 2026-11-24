-- ============================================================
-- إصلاح جذري وشامل: توحيد صلاحيات admin و coordinator
-- ============================================================
-- يُطبّق بعد 35_project_files_and_deadline.sql
--
-- المشكلة المكتشفة بالتدقيق: عدة سياسات كانت تسمح لـ admin فقط
-- بدون coordinator، رغم أن كل الميزات الإدارية بالمنصة مصمَّمة
-- على افتراض تكافؤ الدورين. هذا على الأغلب هو السبب الجذري
-- لمعظم مشاكل "غير مخوّل" المتكررة عبر الجلسات السابقة.
-- ============================================================

-- ------------------------------------------------------------
-- 1. المسارات — كانت admin فقط، تعطيل كامل لتحكم coordinator بالمسارات
-- ------------------------------------------------------------
drop policy if exists "tracks_admin_manage" on public.tracks;
create policy "tracks_admin_manage" on public.tracks
  for all using (public.has_role('admin') or public.has_role('coordinator'));

-- ------------------------------------------------------------
-- 2. الملفات الشخصية — coordinator ما كان يقدر يشوف كل المشاركين
-- ------------------------------------------------------------
drop policy if exists "profiles_select_own_or_admin" on public.profiles;
create policy "profiles_select_own_or_admin" on public.profiles
  for select using (id = auth.uid() or public.has_role('admin') or public.has_role('coordinator'));

-- ------------------------------------------------------------
-- 3. المشاريع — coordinator ما كان يقدر يشوف أي مشروع إطلاقًا
-- ------------------------------------------------------------
drop policy if exists "submissions_select" on public.submissions;
create policy "submissions_select" on public.submissions
  for select using (
    public.is_team_member(team_id)
    or exists (select 1 from public.judge_assignments
               where team_id = submissions.team_id and judge_user_id = auth.uid())
    or public.has_role('admin')
    or public.has_role('coordinator')
  );

drop policy if exists "submissions_insert_leader_only" on public.submissions;
create policy "submissions_insert_leader_only" on public.submissions
  for insert with check (public.is_team_leader(team_id) or public.has_role('admin') or public.has_role('coordinator'));

drop policy if exists "submissions_update_leader_only" on public.submissions;
create policy "submissions_update_leader_only" on public.submissions
  for update using (public.is_team_leader(team_id) or public.has_role('admin') or public.has_role('coordinator'));

-- ------------------------------------------------------------
-- 4. الفرق — تعديل بيانات الفريق (الاسم مثلًا) من الإدارة
-- ------------------------------------------------------------
drop policy if exists "teams_update_leader_or_admin" on public.teams;
create policy "teams_update_leader_or_admin" on public.teams
  for update using (
    exists (select 1 from public.team_members
            where team_id = id and user_id = auth.uid() and is_leader = true)
    or public.has_role('admin')
    or public.has_role('coordinator')
  );

-- ------------------------------------------------------------
-- 5. أعضاء الفريق — رؤية، حذف (طرد عضو)، إضافة يدوية، تعديل القيادة
-- ------------------------------------------------------------
drop policy if exists "team_members_select" on public.team_members;
create policy "team_members_select" on public.team_members
  for select using (
    public.is_team_member(team_id) or public.has_role('admin') or public.has_role('coordinator')
  );

drop policy if exists "team_members_delete_leader_or_admin" on public.team_members;
create policy "team_members_delete_leader_or_admin" on public.team_members
  for delete using (
    exists (select 1 from public.team_members tm
            where tm.team_id = team_members.team_id and tm.user_id = auth.uid() and tm.is_leader = true)
    or public.has_role('admin')
    or public.has_role('coordinator')
  );

drop policy if exists "team_members_insert" on public.team_members;
create policy "team_members_insert" on public.team_members
  for insert with check (
    (user_id = auth.uid() and auth.uid() is not null)
    or public.has_role('admin')
    or public.has_role('coordinator')
  );

drop policy if exists "team_members_update_leader_or_admin" on public.team_members;
create policy "team_members_update_leader_or_admin" on public.team_members
  for update using (
    exists (select 1 from public.team_members tm
            where tm.team_id = team_members.team_id and tm.user_id = auth.uid() and tm.is_leader = true)
    or public.has_role('admin')
    or public.has_role('coordinator')
  );

-- ------------------------------------------------------------
-- 6. دالة نقل القيادة — كانت تتحقق من admin فقط بداخلها
-- ------------------------------------------------------------
create or replace function public.transfer_team_leadership(p_team_id uuid, p_new_leader_id uuid)
returns jsonb as $$
begin
  if not (
    exists (select 1 from public.team_members where team_id = p_team_id and user_id = auth.uid() and is_leader = true)
    or public.has_role('admin')
    or public.has_role('coordinator')
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
-- 7. حاوية ملفات المشاريع — السماح لـ admin/coordinator بالحذف/الاستبدال كذلك
-- ------------------------------------------------------------
drop policy if exists "project_files_update_team_members" on storage.objects;
create policy "project_files_update_team_members" on storage.objects
  for update using (
    bucket_id = 'project-files'
    and (
      exists (select 1 from public.team_members tm
              where tm.team_id::text = (storage.foldername(name))[1] and tm.user_id = auth.uid())
      or public.has_role('admin') or public.has_role('coordinator')
    )
  );
drop policy if exists "project_files_delete_team_members" on storage.objects;
create policy "project_files_delete_team_members" on storage.objects
  for delete using (
    bucket_id = 'project-files'
    and (
      exists (select 1 from public.team_members tm
              where tm.team_id::text = (storage.foldername(name))[1] and tm.user_id = auth.uid())
      or public.has_role('admin') or public.has_role('coordinator')
    )
  );
