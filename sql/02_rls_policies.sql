-- ============================================================
-- منصة هاكثون السيرة النبوية - سياسات الأمان (Row Level Security)
-- ============================================================
-- يُطبّق بعد 01_schema.sql
-- ============================================================

-- ------------------------------------------------------------
-- دالة مساعدة: هل المستخدم الحالي يملك دورًا معينًا؟
-- ------------------------------------------------------------
create or replace function public.has_role(role_key text)
returns boolean as $$
  select exists (
    select 1 from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where ur.user_id = auth.uid() and r.key = role_key
  );
$$ language sql security definer stable;

-- هل المستخدم عضو بفريق معين؟
create or replace function public.is_team_member(p_team_id uuid)
returns boolean as $$
  select exists (
    select 1 from public.team_members
    where team_id = p_team_id and user_id = auth.uid()
  );
$$ language sql security definer stable;

-- هل المستخدم مرشد لفريق معين (عبر حجوزات مؤكدة)؟
create or replace function public.is_team_mentor(p_team_id uuid)
returns boolean as $$
  select exists (
    select 1 from public.mentor_bookings mb
    join public.mentor_slots ms on ms.id = mb.slot_id
    where mb.team_id = p_team_id and ms.mentor_user_id = auth.uid()
  );
$$ language sql security definer stable;

-- ------------------------------------------------------------
-- تفعيل RLS على جميع الجداول
-- ------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.roles enable row level security;
alter table public.user_roles enable row level security;
alter table public.tracks enable row level security;
alter table public.teams enable row level security;
alter table public.team_members enable row level security;
alter table public.submissions enable row level security;
alter table public.prep_sessions enable row level security;
alter table public.prep_attendance enable row level security;
alter table public.mentor_slots enable row level security;
alter table public.mentor_bookings enable row level security;
alter table public.mentor_feedback enable row level security;
alter table public.judging_rounds enable row level security;
alter table public.judging_criteria enable row level security;
alter table public.judge_assignments enable row level security;
alter table public.scores enable row level security;
alter table public.events enable row level security;
alter table public.event_attendance enable row level security;
alter table public.certificate_types enable row level security;
alter table public.certificates enable row level security;
alter table public.surveys enable row level security;
alter table public.survey_responses enable row level security;
alter table public.activity_log enable row level security;

-- ------------------------------------------------------------
-- profiles: كل شخص يشوف ملفه، الإداري يشوف الكل
-- ------------------------------------------------------------
create policy "profiles_select_own_or_admin" on public.profiles
  for select using (id = auth.uid() or public.has_role('admin'));
create policy "profiles_update_own" on public.profiles
  for update using (id = auth.uid());
create policy "profiles_insert_own" on public.profiles
  for insert with check (id = auth.uid());

-- ------------------------------------------------------------
-- roles: قراءة عامة للمسجلين، تعديل للإداري فقط
-- ------------------------------------------------------------
create policy "roles_select_all" on public.roles
  for select using (auth.role() = 'authenticated');
create policy "roles_admin_manage" on public.roles
  for all using (public.has_role('admin'));

-- ------------------------------------------------------------
-- user_roles: المستخدم يشوف أدواره، الإداري يدير الكل
-- ------------------------------------------------------------
create policy "user_roles_select_own_or_admin" on public.user_roles
  for select using (user_id = auth.uid() or public.has_role('admin'));
create policy "user_roles_admin_manage" on public.user_roles
  for all using (public.has_role('admin'));

-- ------------------------------------------------------------
-- tracks: قراءة عامة، تعديل للإداري فقط
-- ------------------------------------------------------------
create policy "tracks_select_all" on public.tracks
  for select using (true);
create policy "tracks_admin_manage" on public.tracks
  for all using (public.has_role('admin'));

-- ------------------------------------------------------------
-- teams: أعضاء الفريق + المرشد المخصص + الإداري
-- ------------------------------------------------------------
create policy "teams_select" on public.teams
  for select using (
    public.is_team_member(id)
    or public.is_team_mentor(id)
    or public.has_role('admin')
    or public.has_role('coordinator')
  );
create policy "teams_insert_authenticated" on public.teams
  for insert with check (auth.role() = 'authenticated');
create policy "teams_update_leader_or_admin" on public.teams
  for update using (
    exists (select 1 from public.team_members
            where team_id = id and user_id = auth.uid() and is_leader = true)
    or public.has_role('admin')
  );

-- ------------------------------------------------------------
-- team_members: أعضاء نفس الفريق + الإداري
-- ------------------------------------------------------------
create policy "team_members_select" on public.team_members
  for select using (
    public.is_team_member(team_id) or public.has_role('admin') or public.has_role('coordinator')
  );
create policy "team_members_insert" on public.team_members
  for insert with check (
    user_id = auth.uid() or public.has_role('admin')
  );
create policy "team_members_delete_leader_or_admin" on public.team_members
  for delete using (
    exists (select 1 from public.team_members tm
            where tm.team_id = team_members.team_id and tm.user_id = auth.uid() and tm.is_leader = true)
    or public.has_role('admin')
  );

-- ------------------------------------------------------------
-- submissions: أعضاء الفريق + المحكّمون المعيّنون + الإداري
-- ------------------------------------------------------------
create policy "submissions_select" on public.submissions
  for select using (
    public.is_team_member(team_id)
    or exists (select 1 from public.judge_assignments
               where team_id = submissions.team_id and judge_user_id = auth.uid())
    or public.has_role('admin')
  );
create policy "submissions_insert_team_member" on public.submissions
  for insert with check (public.is_team_member(team_id));
create policy "submissions_update_team_member" on public.submissions
  for update using (public.is_team_member(team_id));

-- ------------------------------------------------------------
-- prep_sessions: قراءة عامة، إدارة للإداري/المنسق
-- ------------------------------------------------------------
create policy "prep_sessions_select_all" on public.prep_sessions
  for select using (true);
create policy "prep_sessions_admin_manage" on public.prep_sessions
  for all using (public.has_role('admin') or public.has_role('coordinator'));

-- ------------------------------------------------------------
-- prep_attendance: المستخدم يسجل حضوره، الإداري يشوف الكل
-- ------------------------------------------------------------
create policy "prep_attendance_select" on public.prep_attendance
  for select using (user_id = auth.uid() or public.has_role('admin') or public.has_role('coordinator'));
create policy "prep_attendance_insert_own" on public.prep_attendance
  for insert with check (user_id = auth.uid() or public.has_role('admin'));

-- ------------------------------------------------------------
-- mentor_slots: المرشد يدير مواعيده، المشاركون يشوفون المتاح
-- ------------------------------------------------------------
create policy "mentor_slots_select_all" on public.mentor_slots
  for select using (true);
create policy "mentor_slots_mentor_manage" on public.mentor_slots
  for all using (mentor_user_id = auth.uid() or public.has_role('admin'));

-- ------------------------------------------------------------
-- mentor_bookings: أعضاء الفريق + المرشد صاحب الموعد + الإداري
-- ------------------------------------------------------------
create policy "mentor_bookings_select" on public.mentor_bookings
  for select using (
    public.is_team_member(team_id)
    or exists (select 1 from public.mentor_slots where id = slot_id and mentor_user_id = auth.uid())
    or public.has_role('admin')
  );
create policy "mentor_bookings_insert_team" on public.mentor_bookings
  for insert with check (public.is_team_member(team_id));
create policy "mentor_bookings_update" on public.mentor_bookings
  for update using (
    public.is_team_member(team_id)
    or exists (select 1 from public.mentor_slots where id = slot_id and mentor_user_id = auth.uid())
    or public.has_role('admin')
  );

-- ------------------------------------------------------------
-- mentor_feedback: المرشد صاحب الملاحظة + الإداري (المشارك لا يشوفها)
-- ------------------------------------------------------------
create policy "mentor_feedback_select" on public.mentor_feedback
  for select using (mentor_user_id = auth.uid() or public.has_role('admin') or public.has_role('coordinator'));
create policy "mentor_feedback_insert" on public.mentor_feedback
  for insert with check (mentor_user_id = auth.uid());

-- ------------------------------------------------------------
-- judging_rounds / judging_criteria: قراءة عامة، تعديل للإداري
-- ------------------------------------------------------------
create policy "judging_rounds_select_all" on public.judging_rounds
  for select using (true);
create policy "judging_rounds_admin_manage" on public.judging_rounds
  for all using (public.has_role('admin'));

create policy "judging_criteria_select_all" on public.judging_criteria
  for select using (true);
create policy "judging_criteria_admin_manage" on public.judging_criteria
  for all using (public.has_role('admin'));

-- ------------------------------------------------------------
-- judge_assignments: المحكّم يشوف تعييناته، الإداري يدير الكل
-- ------------------------------------------------------------
create policy "judge_assignments_select" on public.judge_assignments
  for select using (judge_user_id = auth.uid() or public.has_role('admin'));
create policy "judge_assignments_admin_manage" on public.judge_assignments
  for all using (public.has_role('admin'));

-- ------------------------------------------------------------
-- scores: المحكّم يدخل درجاته فقط، الإداري يشوف الكل
-- المشارك والمحكّمون الآخرون لا يشوفون الدرجات (نزاهة التحكيم)
-- ------------------------------------------------------------
create policy "scores_select_own_or_admin" on public.scores
  for select using (judge_user_id = auth.uid() or public.has_role('admin'));
create policy "scores_insert_own" on public.scores
  for insert with check (
    judge_user_id = auth.uid()
    and exists (
      select 1 from public.judge_assignments
      where judge_user_id = auth.uid()
        and team_id = scores.team_id
        and round_id = scores.round_id
        and has_conflict = false
    )
  );
create policy "scores_update_own" on public.scores
  for update using (judge_user_id = auth.uid());

-- ------------------------------------------------------------
-- events / event_attendance
-- ------------------------------------------------------------
create policy "events_select_all" on public.events
  for select using (true);
create policy "events_admin_manage" on public.events
  for all using (public.has_role('admin') or public.has_role('coordinator'));

create policy "event_attendance_select" on public.event_attendance
  for select using (user_id = auth.uid() or public.has_role('admin') or public.has_role('coordinator'));
create policy "event_attendance_insert" on public.event_attendance
  for insert with check (true);  -- يُتحقق منطقيًا عبر Edge Function عند مسح QR

-- ------------------------------------------------------------
-- certificate_types: قراءة عامة، تعديل للإداري
-- ------------------------------------------------------------
create policy "certificate_types_select_all" on public.certificate_types
  for select using (true);
create policy "certificate_types_admin_manage" on public.certificate_types
  for all using (public.has_role('admin'));

-- ------------------------------------------------------------
-- certificates: صاحب الشهادة + الإداري
-- ------------------------------------------------------------
create policy "certificates_select_own_or_admin" on public.certificates
  for select using (user_id = auth.uid() or public.has_role('admin'));
create policy "certificates_insert_system" on public.certificates
  for insert with check (user_id = auth.uid() or public.has_role('admin'));

-- ------------------------------------------------------------
-- surveys: قراءة عامة (للنشطة)، تعديل للإداري
-- ------------------------------------------------------------
create policy "surveys_select_active" on public.surveys
  for select using (is_active = true or public.has_role('admin'));
create policy "surveys_admin_manage" on public.surveys
  for all using (public.has_role('admin'));

-- ------------------------------------------------------------
-- survey_responses: صاحب الرد + الإداري
-- ------------------------------------------------------------
create policy "survey_responses_select_own_or_admin" on public.survey_responses
  for select using (user_id = auth.uid() or public.has_role('admin'));
create policy "survey_responses_insert_own" on public.survey_responses
  for insert with check (user_id = auth.uid());

-- ------------------------------------------------------------
-- activity_log: الإداري فقط
-- ------------------------------------------------------------
create policy "activity_log_admin_only" on public.activity_log
  for select using (public.has_role('admin'));
create policy "activity_log_insert_authenticated" on public.activity_log
  for insert with check (auth.role() = 'authenticated');
