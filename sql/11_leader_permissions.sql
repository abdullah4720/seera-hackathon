-- ============================================================
-- إصلاح: صلاحيات زملاء الفريق + تقييد تعديل الفكرة للقائد فقط
-- ============================================================
-- يُطبّق بعد 10_team_rpc.sql
-- ============================================================

-- ------------------------------------------------------------
-- 1. السماح لأعضاء نفس الفريق برؤية ملفات بعضهم الأساسية
--    (سياسة إضافية تُضاف فوق الموجودة، لا تلغيها)
-- ------------------------------------------------------------
create policy "profiles_select_teammates" on public.profiles
  for select using (
    exists (
      select 1 from public.team_members tm1
      join public.team_members tm2 on tm1.team_id = tm2.team_id
      where tm1.user_id = auth.uid() and tm2.user_id = profiles.id
    )
  );

-- ------------------------------------------------------------
-- 2. دالة مساعدة: هل المستخدم قائد فريق معيّن؟
-- ------------------------------------------------------------
create or replace function public.is_team_leader(p_team_id uuid)
returns boolean as $$
  select exists (
    select 1 from public.team_members
    where team_id = p_team_id and user_id = auth.uid() and is_leader = true
  );
$$ language sql security definer stable;

-- ------------------------------------------------------------
-- 3. تقييد إدراج/تعديل "الفكرة المقدَّمة" (submissions) للقائد فقط
--    (كانت مسموحة لأي عضو بالفريق، الآن حصرًا على القائد أو الإداري)
-- ------------------------------------------------------------
drop policy if exists "submissions_insert_team_member" on public.submissions;
create policy "submissions_insert_leader_only" on public.submissions
  for insert with check (public.is_team_leader(team_id) or public.has_role('admin'));

drop policy if exists "submissions_update_team_member" on public.submissions;
create policy "submissions_update_leader_only" on public.submissions
  for update using (public.is_team_leader(team_id) or public.has_role('admin'));

-- ملاحظة: القراءة (select) تبقى متاحة لكل أعضاء الفريق، التغيير فقط يُقيَّد بالقائد
