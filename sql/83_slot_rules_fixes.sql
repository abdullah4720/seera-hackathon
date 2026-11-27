-- ============================================================
-- 83) تصحيحات مواعيد الإرشاد
--   • إلغاء المرشد لحجزٍ يُبقي الموعد مغلقًا (المرشد غير متاح فيه)،
--     وإلغاء الفريق أو الإدارة يعيده متاحًا لفرق أخرى.
--   • فحص «أيام الإرشاد» عند تغيّر وقت الموعد فقط، لا عند تحديث حالة
--     الحجز — كان يُفشل الحجز/الإلغاء لمواعيد أُنشئت قبل ضبط الجدول.
-- ============================================================
create or replace function public.sync_slot_booked_status()
returns trigger as $$
declare v_mentor uuid;
begin
  if TG_OP = 'INSERT' then
    update public.mentor_slots set is_booked = true where id = new.slot_id;
    return new;
  elsif TG_OP = 'DELETE' then
    update public.mentor_slots set is_booked = false where id = old.slot_id;
    return old;
  elsif TG_OP = 'UPDATE' and new.status = 'cancelled' and old.status <> 'cancelled' then
    select mentor_user_id into v_mentor from public.mentor_slots where id = new.slot_id;
    if v_mentor is distinct from auth.uid() then
      update public.mentor_slots set is_booked = false where id = new.slot_id;
    end if;
    return new;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

create or replace function public.enforce_mentorship_hours()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.has_role('admin') or public.has_role('coordinator') then return new; end if;
  if tg_op = 'UPDATE' and new.start_time is not distinct from old.start_time
     and new.end_time is not distinct from old.end_time then
    return new;
  end if;
  if exists (select 1 from public.program_days where phase = 'mentorship') then
    if not exists (select 1 from public.program_days
                   where phase = 'mentorship' and new.start_time >= starts_at and new.end_time <= ends_at) then
      raise exception 'الموعد خارج أيام الإرشاد المحددة';
    end if;
  end if;
  return new;
end;
$$;
