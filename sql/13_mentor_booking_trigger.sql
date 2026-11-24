-- ============================================================
-- إصلاح: تحديث تلقائي لحالة حجز موعد الإرشاد (is_booked)
-- ============================================================
-- يُطبّق بعد 12_projects_showcase.sql
-- المشكلة: المشارك لا يملك صلاحية تعديل mentor_slots مباشرة (محصورة بالمرشد/الإداري)
-- الحل: trigger بصلاحيات النظام يحدّث الحالة تلقائيًا عند الحجز أو الإلغاء
-- ============================================================

create or replace function public.sync_slot_booked_status()
returns trigger as $$
begin
  if TG_OP = 'INSERT' then
    update public.mentor_slots set is_booked = true where id = new.slot_id;
    return new;
  elsif TG_OP = 'DELETE' then
    update public.mentor_slots set is_booked = false where id = old.slot_id;
    return old;
  elsif TG_OP = 'UPDATE' and new.status = 'cancelled' and old.status <> 'cancelled' then
    update public.mentor_slots set is_booked = false where id = new.slot_id;
    return new;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_sync_slot_booked_insert on public.mentor_bookings;
create trigger trg_sync_slot_booked_insert
  after insert on public.mentor_bookings
  for each row execute function public.sync_slot_booked_status();

drop trigger if exists trg_sync_slot_booked_delete on public.mentor_bookings;
create trigger trg_sync_slot_booked_delete
  after delete on public.mentor_bookings
  for each row execute function public.sync_slot_booked_status();

drop trigger if exists trg_sync_slot_booked_update on public.mentor_bookings;
create trigger trg_sync_slot_booked_update
  after update on public.mentor_bookings
  for each row execute function public.sync_slot_booked_status();

-- ------------------------------------------------------------
-- السماح لأي مستخدم مسجّل بمشاهدة الملفات الأساسية للمرشدين
-- (لازمة عشان المشارك يشوف اسم المرشد قبل ما يحجز موعد)
-- ------------------------------------------------------------
create policy "profiles_select_mentors_public" on public.profiles
  for select using (
    exists (
      select 1 from public.user_roles ur join public.roles r on r.id = ur.role_id
      where ur.user_id = profiles.id and r.key = 'mentor'
    )
  );
