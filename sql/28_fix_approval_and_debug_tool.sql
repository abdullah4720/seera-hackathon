-- ============================================================
-- تقوية فحص الصلاحيات بدوال الاعتماد + أداة تشخيص دائمة
-- ============================================================
-- يُطبّق بعد 27_fix_user_roles_permissions.sql
-- ============================================================

-- ------------------------------------------------------------
-- 1. إعادة تعريف دوال الاعتماد/الرفض بفحص مباشر (بدون طبقة وسيطة)
-- ------------------------------------------------------------
create or replace function public.approve_mentor_application(p_application_id uuid)
returns jsonb as $$
declare
  v_app record;
  v_mentor_role_id int;
  v_is_authorized boolean;
begin
  select exists(
    select 1 from public.user_roles ur join public.roles r on r.id = ur.role_id
    where ur.user_id = auth.uid() and r.key in ('admin','coordinator')
  ) into v_is_authorized;

  if not v_is_authorized then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل', 'debug_uid', auth.uid());
  end if;

  select * into v_app from public.mentor_applications where id = p_application_id;
  if v_app.id is null then
    return jsonb_build_object('success', false, 'error', 'الطلب غير موجود');
  end if;

  select id into v_mentor_role_id from public.roles where key = 'mentor';

  insert into public.user_roles (user_id, role_id)
  values (v_app.user_id, v_mentor_role_id)
  on conflict (user_id, role_id, track_id) do nothing;

  update public.profiles
  set specialization = v_app.specialization,
      bio = coalesce(v_app.bio, bio)
  where id = v_app.user_id;

  update public.mentor_applications
  set status = 'approved', reviewed_by = auth.uid(), reviewed_at = now()
  where id = p_application_id;

  return jsonb_build_object('success', true);
end;
$$ language plpgsql security definer set search_path = public;

create or replace function public.reject_mentor_application(p_application_id uuid)
returns jsonb as $$
declare
  v_is_authorized boolean;
begin
  select exists(
    select 1 from public.user_roles ur join public.roles r on r.id = ur.role_id
    where ur.user_id = auth.uid() and r.key in ('admin','coordinator')
  ) into v_is_authorized;

  if not v_is_authorized then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل', 'debug_uid', auth.uid());
  end if;

  update public.mentor_applications
  set status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now()
  where id = p_application_id;

  return jsonb_build_object('success', true);
end;
$$ language plpgsql security definer set search_path = public;

create or replace function public.approve_judge_application(p_application_id uuid)
returns jsonb as $$
declare
  v_app record;
  v_judge_role_id int;
  v_is_authorized boolean;
begin
  select exists(
    select 1 from public.user_roles ur join public.roles r on r.id = ur.role_id
    where ur.user_id = auth.uid() and r.key in ('admin','coordinator')
  ) into v_is_authorized;

  if not v_is_authorized then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل', 'debug_uid', auth.uid());
  end if;

  select * into v_app from public.judge_applications where id = p_application_id;
  if v_app.id is null then
    return jsonb_build_object('success', false, 'error', 'الطلب غير موجود');
  end if;

  select id into v_judge_role_id from public.roles where key = 'judge';

  insert into public.user_roles (user_id, role_id)
  values (v_app.user_id, v_judge_role_id)
  on conflict (user_id, role_id, track_id) do nothing;

  update public.profiles
  set specialization = v_app.specialization,
      bio = coalesce(v_app.bio, bio)
  where id = v_app.user_id;

  update public.judge_applications
  set status = 'approved', reviewed_by = auth.uid(), reviewed_at = now()
  where id = p_application_id;

  return jsonb_build_object('success', true);
end;
$$ language plpgsql security definer set search_path = public;

create or replace function public.reject_judge_application(p_application_id uuid)
returns jsonb as $$
declare
  v_is_authorized boolean;
begin
  select exists(
    select 1 from public.user_roles ur join public.roles r on r.id = ur.role_id
    where ur.user_id = auth.uid() and r.key in ('admin','coordinator')
  ) into v_is_authorized;

  if not v_is_authorized then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل', 'debug_uid', auth.uid());
  end if;

  update public.judge_applications
  set status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now()
  where id = p_application_id;

  return jsonb_build_object('success', true);
end;
$$ language plpgsql security definer set search_path = public;

-- ------------------------------------------------------------
-- 2. دالة تشخيص دائمة: "من أنا وشو أدواري بنظر النظام؟"
-- ------------------------------------------------------------
create or replace function public.debug_my_access()
returns jsonb as $$
declare
  v_uid uuid := auth.uid();
  v_email text;
  v_roles text[];
begin
  select email into v_email from public.profiles where id = v_uid;
  select array_agg(r.key) into v_roles
  from public.user_roles ur join public.roles r on r.id = ur.role_id
  where ur.user_id = v_uid;

  return jsonb_build_object(
    'uid', v_uid,
    'email', v_email,
    'roles', coalesce(v_roles, array[]::text[]),
    'is_admin_or_coordinator', coalesce(v_roles && array['admin','coordinator'], false)
  );
end;
$$ language plpgsql security definer set search_path = public;
