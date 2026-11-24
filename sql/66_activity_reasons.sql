-- ============================================================
-- سجل النشاط بالسبب: تخزين سبب رفض طلبات المرشدين والمحكّمين
-- ============================================================
-- يُطبّق بعد 65_fix_certificate_eligibility_leak.sql
-- ============================================================

alter table public.mentor_applications add column if not exists rejection_reason text;
alter table public.judge_applications add column if not exists rejection_reason text;

create or replace function public.reject_mentor_application(p_application_id uuid, p_reason text default null)
returns jsonb as $$
declare
  v_is_authorized boolean;
begin
  select exists(
    select 1 from public.user_roles ur join public.roles r on r.id = ur.role_id
    where ur.user_id = auth.uid() and r.key in ('admin','coordinator')
  ) into v_is_authorized;

  if not v_is_authorized then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل');
  end if;

  update public.mentor_applications
  set status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now(), rejection_reason = p_reason
  where id = p_application_id;

  return jsonb_build_object('success', true);
end;
$$ language plpgsql security definer set search_path = public;

create or replace function public.reject_judge_application(p_application_id uuid, p_reason text default null)
returns jsonb as $$
declare
  v_is_authorized boolean;
begin
  select exists(
    select 1 from public.user_roles ur join public.roles r on r.id = ur.role_id
    where ur.user_id = auth.uid() and r.key in ('admin','coordinator')
  ) into v_is_authorized;

  if not v_is_authorized then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل');
  end if;

  update public.judge_applications
  set status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now(), rejection_reason = p_reason
  where id = p_application_id;

  return jsonb_build_object('success', true);
end;
$$ language plpgsql security definer set search_path = public;
