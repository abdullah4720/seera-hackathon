-- ============================================================
-- 86) صلاحيات الميسّرين المجزّأة + تحضير المحكّمين
-- ------------------------------------------------------------
-- كل ميسّر له مجموعة صلاحيات يحددها المدير:
--   teams   = حضور الفرق (الجلسات، الحضور الشامل، الفرق، مسح QR)
--   mentors = تحضير المرشدين (يُظهر مواعيدهم للفرق)
--   judges  = تحضير المحكّمين (تسجيل حضور فقط، لا يؤثر على التحكيم)
-- المدير والمنسّق يملكان الثلاث دائمًا.
-- • fac_can(p) هي نقطة الفحص الوحيدة، تستخدمها الدوال والسياسات.
-- • سياسة إدراج/حذف prep_attendance صارت: المدير/المنسّق أو ميسّر
--   بصلاحية teams. أُزيل إدراج المشارك لحضوره بنفسه (لم تكن أي
--   صفحة تستخدمه، وكان يفتح الاستبيان والشهادة بلا حضور فعلي).
-- • الميسّرون الحاليون يُمنحون الصلاحيات الثلاث حتى لا يتغير عملهم.
-- ============================================================

create table if not exists public.facilitator_permissions (
  user_id    uuid primary key references public.profiles(id) on delete cascade,
  perms      text[] not null default '{}'
             check (perms <@ array['teams','mentors','judges']::text[]),
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id)
);
alter table public.facilitator_permissions enable row level security;
create policy facilitator_permissions_select_own_or_admin on public.facilitator_permissions
  for select using (user_id = auth.uid() or public.has_role('admin') or public.has_role('coordinator'));

-- الميسّرون الحاليون: كل الصلاحيات (سلوكهم قبل هذا التغيير)
insert into public.facilitator_permissions (user_id, perms)
select distinct ur.user_id, array['teams','mentors','judges']
from public.user_roles ur join public.roles r on r.id = ur.role_id
where r.key = 'facilitator'
on conflict (user_id) do nothing;

-- ---------- الفحص ----------
create or replace function public.fac_can(p_perm text)
returns boolean language sql stable security definer set search_path = public as $$
  select public.has_role('admin') or public.has_role('coordinator')
      or (public.has_role('facilitator') and exists (
            select 1 from public.facilitator_permissions fp
            where fp.user_id = auth.uid() and p_perm = any(fp.perms)));
$$;

create or replace function public.my_facilitator_permissions()
returns text[] language sql stable security definer set search_path = public as $$
  select case
    when public.has_role('admin') or public.has_role('coordinator') then array['teams','mentors','judges']
    else coalesce((select perms from public.facilitator_permissions where user_id = auth.uid()), '{}')
  end;
$$;

create or replace function public.set_facilitator_permissions(p_user_id uuid, p_perms text[])
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not (public.has_role('admin') or public.has_role('coordinator')) then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل');
  end if;
  if not public.user_has_role(p_user_id, 'facilitator') then
    return jsonb_build_object('success', false, 'error', 'المستخدم ليس ميسّرًا');
  end if;
  if not (coalesce(p_perms, '{}') <@ array['teams','mentors','judges']::text[]) then
    return jsonb_build_object('success', false, 'error', 'صلاحية غير معروفة');
  end if;
  insert into public.facilitator_permissions (user_id, perms, updated_at, updated_by)
  values (p_user_id, coalesce(p_perms, '{}'), now(), auth.uid())
  on conflict (user_id) do update set perms = excluded.perms, updated_at = now(), updated_by = auth.uid();
  return jsonb_build_object('success', true);
end $$;

-- ---------- الاعتماد مع الصلاحيات ----------
drop function if exists public.approve_facilitator_application(uuid, uuid[]);
create function public.approve_facilitator_application(
  p_application_id uuid, p_track_ids uuid[] default null,
  p_permissions text[] default array['teams','mentors','judges'])
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_app record; v_role int; v_tracks uuid[];
begin
  if not (public.has_role('admin') or public.has_role('coordinator')) then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل');
  end if;
  if coalesce(array_length(p_permissions, 1), 0) = 0 then
    return jsonb_build_object('success', false, 'error', 'اختر صلاحية واحدة على الأقل');
  end if;
  if not (p_permissions <@ array['teams','mentors','judges']::text[]) then
    return jsonb_build_object('success', false, 'error', 'صلاحية غير معروفة');
  end if;
  select * into v_app from public.facilitator_applications where id = p_application_id;
  if v_app.id is null then
    return jsonb_build_object('success', false, 'error', 'الطلب غير موجود');
  end if;
  if exists (select 1 from public.team_members where user_id = v_app.user_id) then
    return jsonb_build_object('success', false, 'error', 'المتقدم عضو في فريق مشارك — لا يمكن اعتماده ميسّرًا');
  end if;

  select id into v_role from public.roles where key = 'facilitator';
  insert into public.user_roles (user_id, role_id) values (v_app.user_id, v_role)
  on conflict (user_id, role_id, track_id) do nothing;

  insert into public.facilitator_permissions (user_id, perms, updated_at, updated_by)
  values (v_app.user_id, p_permissions, now(), auth.uid())
  on conflict (user_id) do update set perms = excluded.perms, updated_at = now(), updated_by = auth.uid();

  v_tracks := coalesce(p_track_ids, '{}'::uuid[]);
  insert into public.facilitator_tracks (facilitator_user_id, track_id, created_by)
  select v_app.user_id, t, auth.uid() from unnest(v_tracks) t
  where not exists (select 1 from public.facilitator_tracks ft
                    where ft.facilitator_user_id = v_app.user_id and ft.track_id = t);

  update public.facilitator_applications
  set status = 'approved', reviewed_by = auth.uid(), reviewed_at = now(), rejection_reason = null
  where id = p_application_id;

  insert into public.notifications (user_id, title, body, link)
  values (v_app.user_id, 'تم اعتمادك ميسّرًا في هاكثون السيرة النبوية',
          'يمكنك الآن الدخول إلى صفحة الميسّر للقيام بالمهام المسندة إليك.', 'facilitator.html');
  return jsonb_build_object('success', true);
end $$;

-- ---------- الدوال القائمة: الفحص بالصلاحية ----------
create or replace function public.record_attendance(p_session_id uuid, p_user_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_name text;
  v_already boolean;
begin
  if not public.fac_can('teams') then
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
end $$;

create or replace function public.set_mentor_presence(p_user_id uuid, p_present boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.fac_can('mentors') then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل');
  end if;
  if not public.user_has_role(p_user_id, 'mentor') then
    return jsonb_build_object('success', false, 'error', 'المستخدم ليس مرشدًا');
  end if;
  perform set_config('app.mentor_presence_rpc', 'on', true);
  update public.profiles
  set mentor_present = p_present,
      mentor_present_at = case when p_present then now() else null end
  where id = p_user_id;
  return jsonb_build_object('success', true, 'present', p_present);
end $$;

create or replace function public.facilitator_roster(p_track_id uuid default null)
returns table (user_id uuid, full_name text, is_leader boolean, team_id uuid, team_name text,
               team_code text, track_id uuid, track_name text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.fac_can('teams') then
    raise exception 'غير مخوّل';
  end if;
  return query
  select tm.user_id, p.full_name, tm.is_leader, t.id, t.team_name, t.team_code, t.track_id, tr.name_ar
  from public.team_members tm
  join public.teams t on t.id = tm.team_id and t.status = 'confirmed'
  join public.profiles p on p.id = tm.user_id
  left join public.tracks tr on tr.id = t.track_id
  where p_track_id is null or t.track_id = p_track_id
  order by tr.name_ar, t.team_name, tm.is_leader desc, p.full_name;
end $$;

create or replace function public.facilitator_mentors()
returns table (id uuid, full_name text, specialization text, organization text,
               mentor_present boolean, mentor_present_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.fac_can('mentors') then
    raise exception 'غير مخوّل';
  end if;
  return query
  select p.id, p.full_name, p.specialization, p.organization, p.mentor_present, p.mentor_present_at
  from public.profiles p
  where public.user_has_role(p.id, 'mentor') and coalesce(p.is_active, true)
  order by p.full_name;
end $$;

-- ---------- تحضير المحكّمين (تسجيل فقط) ----------
alter table public.profiles add column if not exists judge_present_at timestamptz;

create or replace function public.guard_judge_presence()
returns trigger language plpgsql as $$
begin
  if new.judge_present_at is distinct from old.judge_present_at
     and coalesce(current_setting('app.judge_presence_rpc', true), '') <> 'on'
     and auth.uid() is not null then
    new.judge_present_at := old.judge_present_at;
  end if;
  return new;
end $$;
drop trigger if exists trg_guard_judge_presence on public.profiles;
create trigger trg_guard_judge_presence before update on public.profiles
  for each row execute function public.guard_judge_presence();

create or replace function public.is_judge_present_today(p_user_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select judge_present_at is not null
       and (judge_present_at at time zone 'Asia/Riyadh')::date = (now() at time zone 'Asia/Riyadh')::date
     from public.profiles where id = p_user_id), false);
$$;

create or replace function public.set_judge_presence(p_user_id uuid, p_present boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.fac_can('judges') then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل');
  end if;
  if not public.user_has_role(p_user_id, 'judge') then
    return jsonb_build_object('success', false, 'error', 'المستخدم ليس محكّمًا');
  end if;
  perform set_config('app.judge_presence_rpc', 'on', true);
  update public.profiles
  set judge_present_at = case when p_present then now() else null end
  where id = p_user_id;
  return jsonb_build_object('success', true, 'present', p_present);
end $$;

create or replace function public.facilitator_judges()
returns table (id uuid, full_name text, specialization text, organization text, judge_present_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.fac_can('judges') then
    raise exception 'غير مخوّل';
  end if;
  return query
  select p.id, p.full_name, p.specialization, p.organization, p.judge_present_at
  from public.profiles p
  where public.user_has_role(p.id, 'judge') and coalesce(p.is_active, true)
  order by p.full_name;
end $$;

-- ---------- سياسات حضور الفرق ----------
drop policy if exists prep_attendance_insert_own on public.prep_attendance;
create policy prep_attendance_insert_staff on public.prep_attendance
  for insert with check (public.fac_can('teams'));
drop policy if exists prep_attendance_delete_facilitator on public.prep_attendance;
create policy prep_attendance_delete_facilitator on public.prep_attendance
  for delete using (public.fac_can('teams'));

-- ---------- الصلاحيات ----------
revoke execute on function public.fac_can(text) from public, anon;
revoke execute on function public.my_facilitator_permissions() from public, anon;
revoke execute on function public.set_facilitator_permissions(uuid, text[]) from public, anon;
revoke execute on function public.approve_facilitator_application(uuid, uuid[], text[]) from public, anon;
revoke execute on function public.set_judge_presence(uuid, boolean) from public, anon;
revoke execute on function public.facilitator_judges() from public, anon;
revoke execute on function public.is_judge_present_today(uuid) from public, anon;
grant execute on function public.fac_can(text) to authenticated;
grant execute on function public.my_facilitator_permissions() to authenticated;
grant execute on function public.set_facilitator_permissions(uuid, text[]) to authenticated;
grant execute on function public.approve_facilitator_application(uuid, uuid[], text[]) to authenticated;
grant execute on function public.set_judge_presence(uuid, boolean) to authenticated;
grant execute on function public.facilitator_judges() to authenticated;
grant execute on function public.is_judge_present_today(uuid) to authenticated;
