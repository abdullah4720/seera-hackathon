-- ============================================================
-- منصة هاكثون السيرة النبوية - إنشاء تلقائي للملف الشخصي عند التسجيل
-- ============================================================
-- يُطبّق بعد 05_announcements.sql
-- الغرض: تجاوز مشاكل RLS/توقيت الجلسة عند التسجيل، عبر إنشاء
-- صف profiles ودور participant تلقائيًا فور إنشاء المستخدم بـ auth.users
-- ============================================================

create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, full_name, email, phone, organization)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)),
    new.email,
    new.raw_user_meta_data->>'phone',
    new.raw_user_meta_data->>'organization'
  )
  on conflict (id) do nothing;

  insert into public.user_roles (user_id, role_id)
  select new.id, id from public.roles where key = 'participant'
  on conflict (user_id, role_id, track_id) do nothing;

  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ------------------------------------------------------------
-- ملاحظة مهمة: هذا الـ trigger يغني عن الإدخال اليدوي لجدول
-- profiles من الواجهة الأمامية بعد signUp — إن كان الكود الحالي
-- يسوي insert يدوي لنفس الجدول، شيله بعد تطبيق هذا الملف.
-- ------------------------------------------------------------
