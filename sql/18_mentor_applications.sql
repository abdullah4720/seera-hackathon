-- ============================================================
-- تخصص المرشد + نظام طلبات الانضمام كمرشد
-- ============================================================
-- يُطبّق بعد 17_fix_platform_settings.sql
-- ============================================================

-- ------------------------------------------------------------
-- 1. حقل التخصص (bio موجود مسبقًا للنبذة التعريفية)
-- ------------------------------------------------------------
alter table public.profiles add column if not exists specialization text;

-- ------------------------------------------------------------
-- 2. جدول طلبات الانضمام كمرشد (يحتاج اعتماد الإداري)
-- ------------------------------------------------------------
create table public.mentor_applications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  specialization text not null,
  bio text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz default now(),
  unique(user_id)
);
alter table public.mentor_applications enable row level security;

create policy "mentor_applications_select_own_or_admin" on public.mentor_applications
  for select using (user_id = auth.uid() or public.has_role('admin') or public.has_role('coordinator'));
create policy "mentor_applications_insert_own" on public.mentor_applications
  for insert with check (user_id = auth.uid());
create policy "mentor_applications_admin_manage" on public.mentor_applications
  for update using (public.has_role('admin') or public.has_role('coordinator'));

-- ------------------------------------------------------------
-- 3. دالة اعتماد طلب الانضمام (تمنح دور مرشد + تنسخ التخصص للملف الشخصي)
-- ------------------------------------------------------------
create or replace function public.approve_mentor_application(p_application_id uuid)
returns jsonb as $$
declare
  v_app record;
  v_mentor_role_id int;
begin
  if not (public.has_role('admin') or public.has_role('coordinator')) then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل');
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
begin
  if not (public.has_role('admin') or public.has_role('coordinator')) then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل');
  end if;

  update public.mentor_applications
  set status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now()
  where id = p_application_id;

  return jsonb_build_object('success', true);
end;
$$ language plpgsql security definer set search_path = public;
