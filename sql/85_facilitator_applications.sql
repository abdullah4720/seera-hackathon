-- ============================================================
-- 85) طلبات الانضمام كميسّر + قائمة المشاركين للميسّر
-- ------------------------------------------------------------
-- • جدول facilitator_applications: يُكتب فقط عبر الدالة
--   submit_facilitator_application (لا سياسة إدراج/تعديل مباشرة)،
--   ويقرؤه صاحبه والإدارة.
-- • approve_facilitator_application: تمنح دور facilitator فقط
--   (لا منسّق ولا أدمن)، وتربط المسارات المختارة، وتُشعر المتقدم.
-- • facilitator_roster: قائمة المشاركين المؤكَّدين (الاسم، الفريق،
--   المسار فقط — بلا جوال أو بريد) للميسّر والإدارة. سياسة teams لا
--   تسمح للميسّر بقراءة الفرق، فكانت قوائم الحضور تظهر فارغة له.
-- لا تغيير على سياسات RLS القائمة.
-- ============================================================

create table if not exists public.facilitator_applications (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null unique references public.profiles(id) on delete cascade,
  organization       text,
  current_position   text,
  preferred_track_id uuid references public.tracks(id) on delete set null,
  availability       text[] not null default '{}',
  experience         text,
  status             text not null default 'pending'
                     check (status in ('pending','approved','rejected')),
  rejection_reason   text,
  reviewed_by        uuid references public.profiles(id),
  reviewed_at        timestamptz,
  created_at         timestamptz not null default now()
);

alter table public.facilitator_applications enable row level security;

drop policy if exists facilitator_applications_select_own_or_admin on public.facilitator_applications;
create policy facilitator_applications_select_own_or_admin on public.facilitator_applications
  for select using (user_id = auth.uid() or public.has_role('admin') or public.has_role('coordinator'));

-- ---------- تقديم الطلب ----------
create or replace function public.submit_facilitator_application(
  p_organization text, p_position text, p_track_id uuid,
  p_availability text[], p_experience text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_status text;
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'سجّل الدخول أولًا');
  end if;
  -- منع تعارض المصالح: عضو فريق مشارك لا يكون ميسّرًا بنفس الحساب
  if exists (select 1 from public.team_members where user_id = v_uid) then
    return jsonb_build_object('success', false, 'error',
      'هذا الحساب مسجَّل كعضو في أحد الفرق المشاركة، ولا يمكن التقديم كميسّر بنفس الحساب');
  end if;
  if public.user_has_role(v_uid, 'facilitator') then
    return jsonb_build_object('success', false, 'error', 'حسابك ميسّر معتمد مسبقًا');
  end if;
  if coalesce(array_length(p_availability, 1), 0) = 0 then
    return jsonb_build_object('success', false, 'error', 'اختر يومًا واحدًا على الأقل من أيام التواجد');
  end if;

  select status into v_status from public.facilitator_applications where user_id = v_uid;
  if v_status = 'pending' then
    return jsonb_build_object('success', false, 'error', 'لديك طلب قيد المراجعة');
  end if;

  insert into public.facilitator_applications
    (user_id, organization, current_position, preferred_track_id, availability, experience, status)
  values (v_uid, nullif(btrim(p_organization), ''), nullif(btrim(p_position), ''), p_track_id,
          p_availability, nullif(btrim(p_experience), ''), 'pending')
  on conflict (user_id) do update set
    organization = excluded.organization, current_position = excluded.current_position,
    preferred_track_id = excluded.preferred_track_id, availability = excluded.availability,
    experience = excluded.experience, status = 'pending', rejection_reason = null,
    reviewed_by = null, reviewed_at = null, created_at = now();

  if nullif(btrim(p_organization), '') is not null then
    update public.profiles set organization = btrim(p_organization) where id = v_uid;
  end if;

  -- إشعار الإدارة داخل المنصة
  insert into public.notifications (user_id, title, body, link)
  select distinct ur.user_id, 'طلب انضمام ميسّر جديد',
         'وصل طلب انضمام ميسّر من ' || coalesce((select full_name from public.profiles where id = v_uid), 'مستخدم') || '.',
         'admin.html'
  from public.user_roles ur join public.roles r on r.id = ur.role_id
  where r.key = 'admin';

  return jsonb_build_object('success', true);
end $$;

-- ---------- الاعتماد ----------
create or replace function public.approve_facilitator_application(p_application_id uuid, p_track_ids uuid[] default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_app record; v_role int; v_tracks uuid[];
begin
  if not (public.has_role('admin') or public.has_role('coordinator')) then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل');
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

  v_tracks := coalesce(p_track_ids,
                case when v_app.preferred_track_id is null then '{}'::uuid[] else array[v_app.preferred_track_id] end);
  insert into public.facilitator_tracks (facilitator_user_id, track_id, created_by)
  select v_app.user_id, t, auth.uid() from unnest(v_tracks) t
  where not exists (select 1 from public.facilitator_tracks ft
                    where ft.facilitator_user_id = v_app.user_id and ft.track_id = t);

  update public.facilitator_applications
  set status = 'approved', reviewed_by = auth.uid(), reviewed_at = now(), rejection_reason = null
  where id = p_application_id;

  insert into public.notifications (user_id, title, body, link)
  values (v_app.user_id, 'تم اعتمادك ميسّرًا في هاكثون السيرة النبوية',
          'يمكنك الآن الدخول إلى صفحة الميسّر لتسجيل الحضور ومتابعة الفرق.', 'facilitator.html');

  return jsonb_build_object('success', true);
end $$;

-- ---------- الرفض ----------
create or replace function public.reject_facilitator_application(p_application_id uuid, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid;
begin
  if not (public.has_role('admin') or public.has_role('coordinator')) then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل');
  end if;
  update public.facilitator_applications
  set status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now(), rejection_reason = nullif(btrim(p_reason), '')
  where id = p_application_id
  returning user_id into v_uid;
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'الطلب غير موجود');
  end if;
  insert into public.notifications (user_id, title, body)
  values (v_uid, 'بخصوص طلب الانضمام ميسّرًا',
          'نشكر اهتمامك، ولم يتم اعتماد طلبك هذه المرة.'
          || coalesce(chr(10) || 'السبب: ' || nullif(btrim(p_reason), ''), ''));
  return jsonb_build_object('success', true);
end $$;

-- ---------- قائمة المشاركين للميسّر (بلا جوال ولا بريد) ----------
create or replace function public.facilitator_roster(p_track_id uuid default null)
returns table (user_id uuid, full_name text, is_leader boolean, team_id uuid, team_name text,
               team_code text, track_id uuid, track_name text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.has_role('facilitator') or public.has_role('admin') or public.has_role('coordinator')) then
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

-- لا تُستدعى إلا لمستخدم مسجّل
revoke execute on function public.submit_facilitator_application(text, text, uuid, text[], text) from public, anon;
revoke execute on function public.approve_facilitator_application(uuid, uuid[]) from public, anon;
revoke execute on function public.reject_facilitator_application(uuid, text) from public, anon;
revoke execute on function public.facilitator_roster(uuid) from public, anon;
grant execute on function public.submit_facilitator_application(text, text, uuid, text[], text) to authenticated;
grant execute on function public.approve_facilitator_application(uuid, uuid[]) to authenticated;
grant execute on function public.reject_facilitator_application(uuid, text) to authenticated;
grant execute on function public.facilitator_roster(uuid) to authenticated;

-- ---------- قائمة المرشدين لصفحة الميسّر (تحضير المرشدين) ----------
-- سياسة user_roles لا تُظهر للميسّر أدوار غيره، فكانت قائمة المرشدين
-- تظهر فارغة له. هذه الدالة تعيد المرشدين النشطين بالحقول اللازمة فقط.
create or replace function public.facilitator_mentors()
returns table (id uuid, full_name text, specialization text, organization text,
               mentor_present boolean, mentor_present_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.has_role('facilitator') or public.has_role('admin') or public.has_role('coordinator')) then
    raise exception 'غير مخوّل';
  end if;
  return query
  select p.id, p.full_name, p.specialization, p.organization, p.mentor_present, p.mentor_present_at
  from public.profiles p
  where public.user_has_role(p.id, 'mentor') and coalesce(p.is_active, true)
  order by p.full_name;
end $$;
revoke execute on function public.facilitator_mentors() from public, anon;
grant execute on function public.facilitator_mentors() to authenticated;
