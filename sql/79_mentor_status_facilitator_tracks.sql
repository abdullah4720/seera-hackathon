-- ============================================================
-- 79) تعطيل المرشد مؤقتًا + ربط الميسّرين بالمسارات (منقول من ابتكار إنفاذ)
--   في إنفاذ يعدّل المدير ملف المرشد مباشرة؛ هنا عبر دالة خادم
--   مقصورة على الإدارة، فلا تتغير سياسات RLS لجدول profiles.
-- ============================================================

alter table public.profiles add column if not exists deactivated_at timestamptz;
alter table public.profiles add column if not exists deactivated_by uuid references public.profiles(id) on delete set null;
alter table public.profiles add column if not exists deactivation_reason text;

create or replace function public.set_mentor_active(p_user_id uuid, p_active boolean, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not (public.has_role('admin') or public.has_role('coordinator')) then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل');
  end if;
  if not exists (select 1 from public.user_roles ur join public.roles r on r.id = ur.role_id
                 where ur.user_id = p_user_id and r.key = 'mentor') then
    return jsonb_build_object('success', false, 'error', 'المستخدم ليس مرشدًا');
  end if;
  if not p_active and coalesce(btrim(p_reason), '') = '' then
    return jsonb_build_object('success', false, 'error', 'سبب التعطيل إلزامي');
  end if;
  update public.profiles
  set is_active = p_active,
      deactivated_at = case when p_active then null else now() end,
      deactivation_reason = case when p_active then null else btrim(p_reason) end,
      deactivated_by = case when p_active then null else auth.uid() end
  where id = p_user_id;
  return jsonb_build_object('success', true, 'active', p_active);
end;
$$;
revoke execute on function public.set_mentor_active(uuid, boolean, text) from anon;

create table if not exists public.facilitator_tracks (
  id uuid primary key default gen_random_uuid(),
  facilitator_user_id uuid not null references public.profiles(id) on delete cascade,
  track_id uuid not null references public.tracks(id) on delete cascade,
  created_at timestamptz default now(),
  created_by uuid references public.profiles(id) on delete set null,
  unique (facilitator_user_id, track_id)
);
alter table public.facilitator_tracks enable row level security;
do $$ begin
  if not exists (select 1 from pg_policy where polname='fac_tracks_select' and polrelid='public.facilitator_tracks'::regclass) then
    create policy fac_tracks_select on public.facilitator_tracks for select using (auth.uid() is not null);
    create policy fac_tracks_manage on public.facilitator_tracks for all
      using (public.has_role('admin') or public.has_role('coordinator'))
      with check (public.has_role('admin') or public.has_role('coordinator'));
  end if;
end $$;

create or replace function public.my_facilitator_tracks()
returns setof uuid language sql stable security definer set search_path = public as $$
  select track_id from public.facilitator_tracks where facilitator_user_id = auth.uid();
$$;

create or replace view public.facilitator_assignments with (security_invoker = on) as
select p.id as facilitator_id, p.full_name as "الميسّر", p.email as "البريد",
       coalesce(string_agg(t.name_ar, ' · ' order by t.display_order), 'كل المسارات') as "المسارات",
       count(ft.id) as "عدد_المسارات"
from public.profiles p
join public.user_roles ur on ur.user_id = p.id
join public.roles r on r.id = ur.role_id and r.key = 'facilitator'
left join public.facilitator_tracks ft on ft.facilitator_user_id = p.id
left join public.tracks t on t.id = ft.track_id
where coalesce(p.is_active, true)
group by p.id, p.full_name, p.email
order by p.full_name;
revoke select on public.facilitator_assignments from anon;
