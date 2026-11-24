-- ============================================================
-- إشعارات كاملة لعملية الإرشاد (الفريق + المرشد، حجز وإلغاء)
-- ============================================================
-- يُطبّق بعد 24_fix_booking_reuse.sql
-- ============================================================

-- تحديث: إشعار الحجز يصل الآن للفريق وللمرشد معًا
create or replace function public.notify_mentor_booking()
returns trigger as $$
declare
  v_team_name text;
  v_mentor_id uuid;
  v_mentor_name text;
  v_slot_time timestamptz;
begin
  select team_name into v_team_name from public.teams where id = new.team_id;
  select mentor_user_id, start_time into v_mentor_id, v_slot_time from public.mentor_slots where id = new.slot_id;
  select full_name into v_mentor_name from public.profiles where id = v_mentor_id;

  -- إشعار لكل أعضاء الفريق
  insert into public.notifications (user_id, title, body)
  select tm.user_id, '🎓 تم حجز موعد إرشاد', 'فريقكم "' || v_team_name || '" حجز موعد مع ' || coalesce(v_mentor_name,'مرشد')
  from public.team_members tm where tm.team_id = new.team_id;

  -- إشعار للمرشد نفسه
  if v_mentor_id is not null then
    insert into public.notifications (user_id, title, body)
    values (v_mentor_id, '📥 لديك حجز إرشاد جديد', 'فريق "' || v_team_name || '" حجز موعدك — راجع لوحتك للتأكيد');
  end if;

  return new;
end;
$$ language plpgsql security definer set search_path = public;

-- جديد: إشعار عند إلغاء موعد إرشاد (لكلا الطرفين)
create or replace function public.notify_mentor_booking_cancelled()
returns trigger as $$
declare
  v_team_name text;
  v_mentor_id uuid;
begin
  if new.status = 'cancelled' and old.status <> 'cancelled' then
    select team_name into v_team_name from public.teams where id = new.team_id;
    select mentor_user_id into v_mentor_id from public.mentor_slots where id = new.slot_id;

    insert into public.notifications (user_id, title, body)
    select tm.user_id, '⚠ تم إلغاء موعد إرشاد', 'تم إلغاء موعد فريقكم "' || v_team_name || '"'
    from public.team_members tm where tm.team_id = new.team_id;

    if v_mentor_id is not null then
      insert into public.notifications (user_id, title, body)
      values (v_mentor_id, '⚠ تم إلغاء حجز', 'فريق "' || v_team_name || '" ألغى موعده معك');
    end if;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_notify_mentor_booking_cancelled on public.mentor_bookings;
create trigger trg_notify_mentor_booking_cancelled
  after update on public.mentor_bookings
  for each row execute function public.notify_mentor_booking_cancelled();
