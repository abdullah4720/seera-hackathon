-- ============================================================
-- 74) تحضير المرشدين وربطه بالمواعيد الظاهرة للمشاركين
--     (منقول من منصة ابتكار إنفاذ مع تشديد التحقق من جهة الخادم)
-- ------------------------------------------------------------
-- • المنظّم (admin / coordinator / facilitator) يسجّل حضور المرشد يوميًا.
-- • الحضور صالح لليوم نفسه فقط بتوقيت الرياض، ويُصفَّر تلقائيًا في اليوم التالي.
-- • مواعيد المرشد لا تظهر للفرق ولا يمكن حجزها إلا إذا سُجّل حضوره اليوم.
-- • الإعداد mentor_presence_required ('true' / 'false') يتيح إيقاف الربط عند الحاجة.
-- • لا تغيير على أي سياسة RLS قائمة.
-- ============================================================

alter table public.profiles add column if not exists mentor_present boolean not null default false;
alter table public.profiles add column if not exists mentor_present_at timestamptz;

insert into public.platform_settings (key, value)
values ('mentor_presence_required', 'true')
on conflict (key) do nothing;

-- هل المرشد حاضر اليوم؟
create or replace function public.is_mentor_present_today(p_user_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((
    select mentor_present
       and mentor_present_at is not null
       and (mentor_present_at at time zone 'Asia/Riyadh')::date = (now() at time zone 'Asia/Riyadh')::date
    from public.profiles where id = p_user_id), false);
$$;
grant execute on function public.is_mentor_present_today(uuid) to authenticated;

-- هل الربط بالحضور مفعّل؟
create or replace function public.mentor_presence_required()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select lower(btrim(value)) from public.platform_settings where key = 'mentor_presence_required'), 'true') <> 'false';
$$;
grant execute on function public.mentor_presence_required() to authenticated;

-- تسجيل الحضور أو إلغاؤه (للمنظّمين فقط)
create or replace function public.set_mentor_presence(p_user_id uuid, p_present boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not exists (
    select 1 from public.user_roles ur join public.roles r on r.id = ur.role_id
    where ur.user_id = auth.uid() and r.key in ('admin','coordinator','facilitator')
  ) then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل');
  end if;
  if not exists (
    select 1 from public.user_roles ur join public.roles r on r.id = ur.role_id
    where ur.user_id = p_user_id and r.key = 'mentor'
  ) then
    return jsonb_build_object('success', false, 'error', 'المستخدم ليس مرشدًا');
  end if;

  perform set_config('app.mentor_presence_rpc', 'on', true);
  update public.profiles
  set mentor_present = p_present,
      mentor_present_at = case when p_present then now() else null end
  where id = p_user_id;

  return jsonb_build_object('success', true, 'present', p_present);
end;
$$;
revoke execute on function public.set_mentor_presence(uuid, boolean) from anon;
grant execute on function public.set_mentor_presence(uuid, boolean) to authenticated;

-- حماية: المستخدم يستطيع تعديل ملفه الشخصي، فنمنع تغيير حقلي الحضور إلا عبر الدالة أعلاه
create or replace function public.guard_mentor_presence()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (new.mentor_present is distinct from old.mentor_present
      or new.mentor_present_at is distinct from old.mentor_present_at)
     and coalesce(current_setting('app.mentor_presence_rpc', true), '') <> 'on'
     and auth.uid() is not null then
    new.mentor_present := old.mentor_present;
    new.mentor_present_at := old.mentor_present_at;
  end if;
  return new;
end;
$$;
create or replace trigger trg_guard_mentor_presence before update on public.profiles
  for each row execute function public.guard_mentor_presence();

-- منع الحجز على موعد مرشد غير حاضر اليوم (من جهة الخادم، لا الواجهة فقط)
-- الإدارة والمنسّق مستثنيان ليتمكنا من الحجز نيابة عن الفرق.
create or replace function public.check_mentor_presence_on_booking()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_mentor uuid;
begin
  if not public.mentor_presence_required() then return new; end if;
  if public.has_role('admin') or public.has_role('coordinator') then return new; end if;
  select mentor_user_id into v_mentor from public.mentor_slots where id = new.slot_id;
  if v_mentor is not null and not public.is_mentor_present_today(v_mentor) then
    raise exception 'هذا الموعد غير متاح حاليًا: لم يُسجَّل حضور المرشد اليوم';
  end if;
  return new;
end;
$$;
create or replace trigger trg_check_mentor_presence before insert on public.mentor_bookings
  for each row execute function public.check_mentor_presence_on_booking();
