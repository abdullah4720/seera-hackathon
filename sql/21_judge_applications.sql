-- ============================================================
-- نظام طلبات الانضمام كمحكّم (مطابق لنظام المرشدين)
-- ============================================================
-- يُطبّق بعد 20_mentor_track_link.sql
-- ============================================================

create table public.judge_applications (
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
alter table public.judge_applications enable row level security;

create policy "judge_applications_select_own_or_admin" on public.judge_applications
  for select using (user_id = auth.uid() or public.has_role('admin') or public.has_role('coordinator'));
create policy "judge_applications_insert_own" on public.judge_applications
  for insert with check (user_id = auth.uid());
create policy "judge_applications_admin_manage" on public.judge_applications
  for update using (public.has_role('admin') or public.has_role('coordinator'));

create or replace function public.approve_judge_application(p_application_id uuid)
returns jsonb as $$
declare
  v_app record;
  v_judge_role_id int;
begin
  if not (public.has_role('admin') or public.has_role('coordinator')) then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل');
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
begin
  if not (public.has_role('admin') or public.has_role('coordinator')) then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل');
  end if;

  update public.judge_applications
  set status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now()
  where id = p_application_id;

  return jsonb_build_object('success', true);
end;
$$ language plpgsql security definer set search_path = public;
