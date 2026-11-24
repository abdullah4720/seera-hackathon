-- ============================================================
-- التحكم بسعة المسار + تفعيل يوم/جلسة التحضير النشطة
-- ============================================================
-- يُطبّق بعد 31_program_schedule.sql
-- ============================================================

-- ------------------------------------------------------------
-- 1. سعة المسار القصوى (تُغلق تلقائيًا عند الاكتمال)
-- ------------------------------------------------------------
alter table public.tracks add column if not exists max_participants int;

-- دالة: تحسب عدد المسجلين الفعلي بمسار معيّن (كل أعضاء كل الفرق بهذا المسار)
create or replace function public.get_track_participant_count(p_track_id uuid)
returns int as $$
  select count(distinct tm.user_id)
  from public.team_members tm
  join public.teams t on t.id = tm.team_id
  where t.track_id = p_track_id;
$$ language sql security definer stable set search_path = public;

-- trigger: يغلق التسجيل تلقائيًا بالمسار عند وصول السعة القصوى
create or replace function public.auto_close_track_on_capacity()
returns trigger as $$
declare
  v_track_id uuid;
  v_max int;
  v_count int;
begin
  select track_id into v_track_id from public.teams where id = new.team_id;
  select max_participants into v_max from public.tracks where id = v_track_id;

  if v_max is not null then
    v_count := public.get_track_participant_count(v_track_id);
    if v_count >= v_max then
      update public.tracks set registration_open = false where id = v_track_id;
    end if;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_auto_close_track on public.team_members;
create trigger trg_auto_close_track
  after insert on public.team_members
  for each row execute function public.auto_close_track_on_capacity();

-- ------------------------------------------------------------
-- 2. تفعيل جلسة/يوم تحضير نشط لكل مسار (للتحكم بمن يقدر الميسّر يسجّله)
-- ------------------------------------------------------------
alter table public.prep_sessions add column if not exists is_checkin_active boolean default false;

-- دالة: تفعيل جلسة معيّنة تلقائيًا تلغي تفعيل أي جلسة أخرى بنفس المسار
create or replace function public.activate_prep_session(p_session_id uuid)
returns jsonb as $$
declare
  v_track_id uuid;
begin
  if not (public.has_role('admin') or public.has_role('coordinator')) then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل');
  end if;

  select track_id into v_track_id from public.prep_sessions where id = p_session_id;

  -- إلغاء تفعيل كل الجلسات الأخرى بنفس المسار (أو العامة إن كان track_id فارغ)
  update public.prep_sessions
  set is_checkin_active = false
  where (track_id = v_track_id or (track_id is null and v_track_id is null))
    and id <> p_session_id;

  update public.prep_sessions set is_checkin_active = true where id = p_session_id;

  return jsonb_build_object('success', true);
end;
$$ language plpgsql security definer set search_path = public;

create or replace function public.deactivate_prep_session(p_session_id uuid)
returns jsonb as $$
begin
  if not (public.has_role('admin') or public.has_role('coordinator')) then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل');
  end if;
  update public.prep_sessions set is_checkin_active = false where id = p_session_id;
  return jsonb_build_object('success', true);
end;
$$ language plpgsql security definer set search_path = public;
