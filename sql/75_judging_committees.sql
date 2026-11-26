-- ============================================================
-- 75) التحكيم الكامل كما في منصة ابتكار إنفاذ (البنية فقط، بلا أي بيانات)
--   • لجان التحكيم وأعضاؤها، وإسناد المشروع للجنة كاملة
--   • التوزيع الآلي (لجان / محكّمين / مشاريع) وترتيب العرض
--   • اعتماد النتائج وقفل الدرجات بعده، ونطاق الدرجة، وساعات التحكيم
--   • الترتيب النهائي وإعلان النتائج وصفحتا النتائج والحفل
--   • أيام البرنامج (program_days) لضبط ساعات الإرشاد والتحكيم
-- لا تغيير على سياسات RLS القائمة؛ الجداول الجديدة لها سياساتها.
-- ============================================================

-- ---------- أعمدة جديدة ----------
alter table public.judge_assignments add column if not exists committee_id uuid;
alter table public.judge_assignments add column if not exists judging_order integer;

-- ---------- الجداول ----------
create table if not exists public.judging_committees (
  id uuid primary key default gen_random_uuid(),
  name_ar text not null,
  description text,
  track_id uuid references public.tracks(id) on delete set null,
  is_active boolean default true,
  created_at timestamptz default now(),
  created_by uuid references public.profiles(id) on delete set null
);

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'judge_assignments_committee_id_fkey') then
    alter table public.judge_assignments
      add constraint judge_assignments_committee_id_fkey
      foreign key (committee_id) references public.judging_committees(id) on delete set null;
  end if;
end $$;

create table if not exists public.committee_members (
  id uuid primary key default gen_random_uuid(),
  committee_id uuid not null references public.judging_committees(id) on delete cascade,
  judge_user_id uuid not null references public.profiles(id) on delete cascade,
  is_head boolean default false,
  created_at timestamptz default now(),
  unique (committee_id, judge_user_id),
  constraint committee_members_judge_unique unique (judge_user_id)
);

create table if not exists public.judging_approvals (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  round_id uuid not null references public.judging_rounds(id) on delete cascade,
  status text not null default 'approved' check (status in ('approved','rejected')),
  note text,
  approved_by uuid references public.profiles(id) on delete set null,
  approved_at timestamptz default now(),
  override_reason text,
  unique (team_id, round_id)
);

create table if not exists public.scores_deleted_archive (
  id uuid primary key default gen_random_uuid(),
  original_id uuid, judge_user_id uuid, team_id uuid, round_id uuid, criteria_id uuid,
  score numeric(5,2), comments text, submitted_at timestamptz,
  deleted_by uuid references public.profiles(id) on delete set null,
  deleted_at timestamptz default now(),
  deletion_reason text not null
);

create table if not exists public.track_specializations (
  id uuid primary key default gen_random_uuid(),
  track_id uuid not null references public.tracks(id) on delete cascade,
  keyword text not null,
  weight integer default 1,
  unique (track_id, keyword)
);

create table if not exists public.program_days (
  id uuid primary key default gen_random_uuid(),
  phase text not null check (phase in ('hackathon','mentorship','judging')),
  day_number integer not null check (day_number > 0),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  created_at timestamptz default now(),
  check (ends_at > starts_at),
  unique (phase, day_number)
);

-- ---------- RLS للجداول الجديدة (نفس سياسات إنفاذ) ----------
alter table public.judging_committees   enable row level security;
alter table public.committee_members    enable row level security;
alter table public.judging_approvals    enable row level security;
alter table public.scores_deleted_archive enable row level security;
alter table public.track_specializations enable row level security;
alter table public.program_days         enable row level security;

do $$ begin
  if not exists (select 1 from pg_policy where polname='committees_select' and polrelid='public.judging_committees'::regclass) then
    create policy committees_select on public.judging_committees for select using (auth.uid() is not null);
    create policy committees_manage on public.judging_committees for all
      using (public.has_role('admin') or public.has_role('coordinator'))
      with check (public.has_role('admin') or public.has_role('coordinator'));
  end if;
  if not exists (select 1 from pg_policy where polname='committee_members_select' and polrelid='public.committee_members'::regclass) then
    create policy committee_members_select on public.committee_members for select using (auth.uid() is not null);
    create policy committee_members_manage on public.committee_members for all
      using (public.has_role('admin') or public.has_role('coordinator'))
      with check (public.has_role('admin') or public.has_role('coordinator'));
  end if;
  if not exists (select 1 from pg_policy where polname='judging_approvals_admin_manage' and polrelid='public.judging_approvals'::regclass) then
    create policy judging_approvals_admin_manage on public.judging_approvals for all
      using (public.has_role('admin') or public.has_role('coordinator'))
      with check (public.has_role('admin') or public.has_role('coordinator'));
    create policy judging_approvals_judge_read on public.judging_approvals for select
      using (exists (select 1 from public.judge_assignments ja
                     where ja.judge_user_id = auth.uid() and ja.team_id = judging_approvals.team_id
                       and ja.round_id = judging_approvals.round_id));
  end if;
  if not exists (select 1 from pg_policy where polname='scores_archive_admin_only' and polrelid='public.scores_deleted_archive'::regclass) then
    create policy scores_archive_admin_only on public.scores_deleted_archive for select
      using (public.has_role('admin') or public.has_role('coordinator'));
  end if;
  if not exists (select 1 from pg_policy where polname='track_spec_select' and polrelid='public.track_specializations'::regclass) then
    create policy track_spec_select on public.track_specializations for select using (auth.uid() is not null);
    create policy track_spec_manage on public.track_specializations for all
      using (public.has_role('admin') or public.has_role('coordinator'))
      with check (public.has_role('admin') or public.has_role('coordinator'));
  end if;
  if not exists (select 1 from pg_policy where polname='program_days_select_all' and polrelid='public.program_days'::regclass) then
    create policy program_days_select_all on public.program_days for select using (true);
    create policy program_days_admin_manage on public.program_days for all
      using (public.has_role('admin') or public.has_role('coordinator'))
      with check (public.has_role('admin') or public.has_role('coordinator'));
  end if;
end $$;

-- ---------- دوال مساعدة ----------
create or replace function public.is_within_phase_hours(p_phase text, p_at timestamptz default now())
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when not exists (select 1 from public.program_days where phase = p_phase) then true
    else exists (select 1 from public.program_days
                 where phase = p_phase and p_at >= starts_at and p_at <= ends_at)
  end;
$$;

create or replace function public.assignment_has_scores(p_judge uuid, p_team uuid, p_round uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.scores
                 where judge_user_id = p_judge and team_id = p_team and round_id = p_round);
$$;

create or replace function public.judge_track_score(p_judge_id uuid, p_track_id uuid)
returns integer language sql stable security definer set search_path = public as $$
  select coalesce(sum(ts.weight), 0)::int
  from public.track_specializations ts
  join public.profiles p on p.id = p_judge_id
  where ts.track_id = p_track_id
    and coalesce(p.specialization, '') ilike '%' || ts.keyword || '%';
$$;

create or replace function public.team_brief(p_team_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'team',    coalesce(t.team_name, ''),
    'code',    coalesce(t.team_code, ''),
    'track',   coalesce(tr.name_ar, ''),
    'project', coalesce((select s.title from public.submissions s
                         where s.team_id = t.id order by s.version desc nulls last limit 1), ''))
  from public.teams t left join public.tracks tr on tr.id = t.track_id
  where t.id = p_team_id;
$$;
revoke execute on function public.team_brief(uuid) from anon;

-- مزامنة أيام البرنامج مع إعدادات بداية/نهاية كل مرحلة
create or replace function public.sync_phase_window_settings()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_phase text; v_min timestamptz; v_max timestamptz;
begin
  v_phase := coalesce(new.phase, old.phase);
  select min(starts_at), max(ends_at) into v_min, v_max from public.program_days where phase = v_phase;
  insert into public.platform_settings (key, value) values
    (v_phase || '_start_date', case when v_min is null then null else v_min::text end),
    (v_phase || '_end_date',   case when v_max is null then null else v_max::text end)
  on conflict (key) do update set value = excluded.value;
  return null;
end;
$$;
create or replace trigger trg_sync_phase_window after insert or delete or update on public.program_days
  for each row execute function public.sync_phase_window_settings();

-- ---------- مشغّلات الإسناد ----------
create or replace function public.validate_assignment_membership()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.committee_id is null then return new; end if;
  if not exists (select 1 from public.committee_members cm
                 where cm.judge_user_id = new.judge_user_id and cm.committee_id = new.committee_id) then
    raise exception 'المحكّم ليس عضوًا في هذه اللجنة';
  end if;
  return new;
end;
$$;
create or replace trigger trg_validate_assignment_membership
  before insert or update of committee_id, judge_user_id on public.judge_assignments
  for each row execute function public.validate_assignment_membership();

create or replace function public.enforce_one_committee_per_team()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_other uuid; v_name text;
begin
  if new.committee_id is null then return new; end if;
  select distinct a.committee_id into v_other
  from public.judge_assignments a
  where a.team_id = new.team_id and a.round_id = new.round_id
    and a.committee_id is not null and a.committee_id <> new.committee_id
  limit 1;
  if v_other is not null then
    select name_ar into v_name from public.judging_committees where id = v_other;
    raise exception 'هذا المشروع تحكّمه % في هذه الجولة — لجنة واحدة لكل مشروع', coalesce(v_name, 'لجنة أخرى');
  end if;
  return new;
end;
$$;
create or replace trigger trg_one_committee_per_team before insert or update on public.judge_assignments
  for each row execute function public.enforce_one_committee_per_team();

create or replace function public.grant_member_assignments()
returns trigger language plpgsql security definer set search_path = public as $$
declare r record;
begin
  for r in select distinct a.team_id, a.round_id from public.judge_assignments a
           where a.committee_id = new.committee_id loop
    begin
      insert into public.judge_assignments (judge_user_id, team_id, round_id, committee_id)
      values (new.judge_user_id, r.team_id, r.round_id, new.committee_id)
      on conflict (judge_user_id, team_id, round_id) do update set committee_id = excluded.committee_id;
    exception when others then null;
    end;
  end loop;
  return new;
exception when others then return new;
end;
$$;
create or replace trigger trg_grant_member_assignments after insert on public.committee_members
  for each row execute function public.grant_member_assignments();

create or replace function public.cleanup_member_assignments()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  delete from public.judge_assignments a
  where a.judge_user_id = old.judge_user_id and a.committee_id = old.committee_id
    and not exists (select 1 from public.scores s
                    where s.judge_user_id = a.judge_user_id and s.team_id = a.team_id and s.round_id = a.round_id);
  return old;
exception when others then return old;
end;
$$;
create or replace trigger trg_cleanup_member_assignments after delete on public.committee_members
  for each row execute function public.cleanup_member_assignments();

create or replace function public.cleanup_committee_assignments()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_scored int;
begin
  select count(*) into v_scored from public.judge_assignments a
  where a.committee_id = old.id
    and exists (select 1 from public.scores s
                where s.judge_user_id = a.judge_user_id and s.team_id = a.team_id and s.round_id = a.round_id);
  if v_scored > 0 then
    raise exception 'لا يمكن حذف لجنة «%»: بدأ تحكيم % من مشاريعها. أعد توزيع المشاريع أولًا.', old.name_ar, v_scored;
  end if;
  delete from public.judge_assignments where committee_id = old.id;
  return old;
end;
$$;
create or replace trigger trg_cleanup_committee_assignments before delete on public.judging_committees
  for each row execute function public.cleanup_committee_assignments();

create or replace function public.cleanup_team_judging()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  delete from public.scores            where team_id = old.id;
  delete from public.judge_assignments where team_id = old.id;
  return old;
exception when others then return old;
end;
$$;
create or replace trigger trg_cleanup_team_judging before delete on public.teams
  for each row execute function public.cleanup_team_judging();

-- ---------- مشغّلات الدرجات ----------
create or replace function public.validate_score_range()
returns trigger language plpgsql set search_path = public as $$
declare v_max int;
begin
  select max_score into v_max from public.judging_criteria where id = new.criteria_id;
  if v_max is null then raise exception 'المعيار غير موجود'; end if;
  if new.score < 0 or new.score > v_max then
    raise exception 'الدرجة % خارج النطاق المسموح (0 إلى %)', new.score, v_max;
  end if;
  return new;
end;
$$;
create or replace trigger trg_validate_score_range before insert or update on public.scores
  for each row execute function public.validate_score_range();

create or replace function public.block_scores_after_approval()
returns trigger language plpgsql set search_path = public as $$
begin
  if exists (select 1 from public.judging_approvals
             where team_id = new.team_id and round_id = new.round_id and status = 'approved') then
    raise exception 'النتيجة معتمدة من الإدارة — لا يمكن تعديلها. راجع فريق التنظيم.';
  end if;
  return new;
end;
$$;
create or replace trigger trg_block_scores_after_approval before insert or update on public.scores
  for each row execute function public.block_scores_after_approval();

create or replace function public.enforce_judging_hours()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.has_role('admin') or public.has_role('coordinator') then return new; end if;
  if not public.is_within_phase_hours('judging') then
    raise exception 'التحكيم مغلق حاليًا — راجع جدول أيام التحكيم';
  end if;
  return new;
end;
$$;
create or replace trigger trg_enforce_judging_hours before insert or update on public.scores
  for each row execute function public.enforce_judging_hours();

create or replace function public.validate_judging_approval()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_assigned int; v_submitted int; v_team text;
begin
  if new.status <> 'approved' then return new; end if;
  if not (public.has_role('admin') or public.has_role('coordinator')) then
    raise exception 'الاعتماد للإدارة وحدها';
  end if;
  select team_name into v_team from public.teams where id = new.team_id;
  select count(distinct judge_user_id) into v_assigned from public.judge_assignments
  where team_id = new.team_id and round_id = new.round_id;
  select count(distinct judge_user_id) into v_submitted from public.scores
  where team_id = new.team_id and round_id = new.round_id;
  if v_assigned = 0 then raise exception 'لا محكّمين مسنَدين لفريق «%»', coalesce(v_team, '؟'); end if;
  if v_submitted = 0 then raise exception 'لا درجات مسجّلة لفريق «%» — لا يمكن الاعتماد', coalesce(v_team, '؟'); end if;
  return new;
end;
$$;
create or replace trigger trg_validate_judging_approval before insert or update on public.judging_approvals
  for each row execute function public.validate_judging_approval();
