-- ============================================================
-- تسجيل الحضور الفعلي عبر مسح QR (للإداري/المنسق)
-- ============================================================
-- يُطبّق بعد 14_notifications.sql
-- ============================================================

create or replace function public.record_attendance(
  p_session_id uuid,
  p_user_id uuid
) returns jsonb as $$
declare
  v_name text;
  v_already boolean;
begin
  if not (public.has_role('admin') or public.has_role('coordinator')) then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل لتسجيل الحضور');
  end if;

  select full_name into v_name from public.profiles where id = p_user_id;
  if v_name is null then
    return jsonb_build_object('success', false, 'error', 'رمز غير معروف — تأكد من صحة الرمز الممسوح');
  end if;

  select exists(
    select 1 from public.prep_attendance where session_id = p_session_id and user_id = p_user_id
  ) into v_already;

  insert into public.prep_attendance (session_id, user_id)
  values (p_session_id, p_user_id)
  on conflict (session_id, user_id) do nothing;

  return jsonb_build_object('success', true, 'name', v_name, 'already_checked_in', v_already);
end;
$$ language plpgsql security definer set search_path = public;

-- نفس الفكرة لتسجيل حضور الفعاليات العامة (events)
create or replace function public.record_event_attendance(
  p_event_id uuid,
  p_user_id uuid
) returns jsonb as $$
declare
  v_name text;
  v_already boolean;
begin
  if not (public.has_role('admin') or public.has_role('coordinator')) then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل لتسجيل الحضور');
  end if;

  select full_name into v_name from public.profiles where id = p_user_id;
  if v_name is null then
    return jsonb_build_object('success', false, 'error', 'رمز غير معروف — تأكد من صحة الرمز الممسوح');
  end if;

  select exists(
    select 1 from public.event_attendance where event_id = p_event_id and user_id = p_user_id
  ) into v_already;

  insert into public.event_attendance (event_id, user_id)
  values (p_event_id, p_user_id)
  on conflict (event_id, user_id) do nothing;

  return jsonb_build_object('success', true, 'name', v_name, 'already_checked_in', v_already);
end;
$$ language plpgsql security definer set search_path = public;
