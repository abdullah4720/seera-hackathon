-- ============================================================
-- إصلاح جذري ثانٍ: أسماء المرشدين ما زالت لا تبان
-- ============================================================
-- يُطبّق بعد 58_fix_mentor_profile_visibility.sql
--
-- السبب الحقيقي (اكتُشف بعد تطبيق الإصلاح الأول وعدم نجاحه):
-- سياسة profiles_select_mentors_public تتحقق من دور الشخص عبر
-- استعلام فرعي عادي على جدول user_roles — لكن user_roles نفسه
-- مقفول بحيث لا يقدر أي مستخدم يشوف صفوف غيره (إلا الأدمن).
-- فالاستعلام الفرعي يفشل بصمت لأي مشارك عادي، حتى لو المرشد
-- فعليًا عنده الدور — لأن RLS يطبَّق على الاستعلام الفرعي نفسه
-- بنفس صلاحيات المستخدم الحالي.
--
-- الحل: دالة بصلاحيات مرتفعة (security definer) تتجاوز هالقفل
-- تحديدًا لفحص "هل هذا الشخص عنده دور معيّن؟" بس — بدون فتح أي
-- بيانات حساسة ثانية بجدول user_roles.
-- ============================================================

create or replace function public.user_has_role(p_target_user_id uuid, p_role_key text)
returns boolean as $$
  select exists (
    select 1 from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where ur.user_id = p_target_user_id and r.key = p_role_key
  );
$$ language sql security definer stable set search_path = public;

grant execute on function public.user_has_role(uuid, text) to anon, authenticated;

-- إعادة بناء السياسة باستخدام الدالة الجديدة بدل الاستعلام الفرعي المباشر
drop policy if exists "profiles_select_mentors_public" on public.profiles;

create policy "profiles_select_mentors_public" on public.profiles
  for select using (
    public.user_has_role(profiles.id, 'mentor')
  );
