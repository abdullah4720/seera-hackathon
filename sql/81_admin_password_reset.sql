-- ============================================================
-- 81) إعادة تعيين كلمة المرور من لوحة التحكم — بلا إيميل (منقول من إنفاذ)
--   1) المدير/المنسّق يفتح «نافذة إعادة تعيين» للمستخدم (السبب إلزامي).
--   2) المستخدم يفتح «تفعيل أول مرة» ويُدخل بريده وجواله المسجّلين
--      وكلمة مرور جديدة.
--   تشديد عن إنفاذ: النافذة تنتهي بعد 48 ساعة، ورسالة الفشل موحّدة
--   فلا تكشف وجود الحسابات، وتُغلق النافذة بعد الاستخدام.
-- ============================================================

alter table public.profiles add column if not exists reset_requested_at timestamptz;
alter table public.profiles add column if not exists reset_requested_by uuid references public.profiles(id) on delete set null;
alter table public.profiles add column if not exists reset_reason text;

alter table public.profiles drop constraint if exists profiles_activation_status_check;
alter table public.profiles add constraint profiles_activation_status_check
  check (activation_status in ('pending','active','reset_requested'));

create or replace function public.request_password_reset(p_user_id uuid, p_reason text)
returns json language plpgsql security definer set search_path = public as $$
declare v_name text;
begin
  if not (public.has_role('admin') or public.has_role('coordinator')) then
    return json_build_object('success', false, 'error', 'صلاحية غير كافية');
  end if;
  if p_reason is null or btrim(p_reason) = '' then
    return json_build_object('success', false, 'error', 'سبب إعادة التعيين إلزامي');
  end if;
  -- لا تُفتح نافذة لحساب إداري من غير مدير
  if (public.user_has_role(p_user_id, 'admin') or public.user_has_role(p_user_id, 'coordinator'))
     and not public.has_role('admin') then
    return json_build_object('success', false, 'error', 'إعادة تعيين الحسابات الإدارية للمدير فقط');
  end if;
  select full_name into v_name from public.profiles where id = p_user_id;
  if v_name is null then return json_build_object('success', false, 'error', 'المستخدم غير موجود'); end if;
  update public.profiles set activation_status = 'reset_requested', reset_requested_at = now(),
         reset_requested_by = auth.uid(), reset_reason = btrim(p_reason)
  where id = p_user_id;
  return json_build_object('success', true, 'name', v_name);
end;
$$;

create or replace function public.cancel_password_reset(p_user_id uuid)
returns json language plpgsql security definer set search_path = public as $$
begin
  if not (public.has_role('admin') or public.has_role('coordinator')) then
    return json_build_object('success', false, 'error', 'صلاحية غير كافية');
  end if;
  update public.profiles set activation_status = case when activated_at is null then 'pending' else 'active' end,
         reset_requested_at = null, reset_requested_by = null, reset_reason = null
  where id = p_user_id and activation_status = 'reset_requested';
  return json_build_object('success', true);
end;
$$;
revoke execute on function public.request_password_reset(uuid, text), public.cancel_password_reset(uuid) from anon;

-- التفعيل الأول أو إعادة التعيين المفتوحة (48 ساعة) ببريد وجوال متطابقين
create or replace function public.activate_imported_account(p_email text, p_phone text, p_new_password text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_uid uuid; v_status text; v_stored text; v_activated timestamptz; v_reset_at timestamptz; v_ok boolean;
begin
  if length(coalesce(p_new_password, '')) < 6 then
    return jsonb_build_object('success', false, 'error', 'كلمة المرور يجب ألا تقل عن ستة أحرف');
  end if;

  select p.id, p.activation_status, p.phone, p.activated_at, p.reset_requested_at
    into v_uid, v_status, v_stored, v_activated, v_reset_at
  from public.profiles p where lower(p.email) = lower(btrim(p_email));

  v_ok := v_uid is not null
    and ((v_status = 'pending' and v_activated is null)
         or (v_status = 'reset_requested' and v_reset_at > now() - interval '48 hours'))
    and public.normalize_phone(v_stored) is not null
    and public.normalize_phone(v_stored) = public.normalize_phone(p_phone);

  -- رسالة موحّدة لكل حالات الفشل حتى لا تُكشف الحسابات
  if not coalesce(v_ok, false) then
    return jsonb_build_object('success', false,
      'error', 'تعذّر التفعيل: تأكد من البريد ورقم الجوال المسجَّلين، أو اطلب من المنظمين فتح نافذة إعادة تعيين');
  end if;

  update auth.users
  set encrypted_password = crypt(p_new_password, gen_salt('bf')),
      email_confirmed_at = coalesce(email_confirmed_at, now()),
      updated_at = now()
  where id = v_uid;

  update public.profiles
  set activation_status = 'active', activated_at = coalesce(activated_at, now()),
      reset_requested_at = null, reset_requested_by = null, reset_reason = null
  where id = v_uid;
  return jsonb_build_object('success', true);
end;
$$;
grant execute on function public.activate_imported_account(text, text, text) to anon, authenticated;
