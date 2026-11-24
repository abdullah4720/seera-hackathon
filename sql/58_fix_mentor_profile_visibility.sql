-- ============================================================
-- إصلاح: أسماء المرشدين ما تبان إلا لمن عنده دور مرشد بنفسه
-- ============================================================
-- يُطبّق بعد 57_smart_join_flow.sql
--
-- السبب الجذري: السياسة الحالية (profiles_select_own_or_admin)
-- تفحص دور "الشخص اللي يشاهد" (has_role('mentor')) — مو دور
-- الشخص المعروض. فمشارك عادي (بدون دور مرشد) يفشل بكل شروطها
-- لما يحاول يشوف بروفايل مرشد ثاني.
--
-- الحل: سياسة منفصلة تسمح لأي مستخدم مسجّل يشوف بروفايل *أي
-- شخص عنده دور مرشد* — بغض النظر عن دور المُشاهِد نفسه. كانت
-- معرَّفة سابقًا (ملف 13) لكن يبدو ما انطبّقت فعليًا على قاعدة
-- البيانات الحالية، فنعيد تفعيلها هنا بشكل مضمون.
-- ============================================================

drop policy if exists "profiles_select_mentors_public" on public.profiles;

create policy "profiles_select_mentors_public" on public.profiles
  for select using (
    exists (
      select 1 from public.user_roles ur
      join public.roles r on r.id = ur.role_id
      where ur.user_id = profiles.id and r.key = 'mentor'
    )
  );

-- تحقق من النتيجة: هذا الاستعلام يفترض يرجّع كل المرشدين
-- (شغّله من حساب Supabase الإداري للتأكد إن السياسة فعّالة)
select p.full_name, p.id
from public.profiles p
join public.user_roles ur on ur.user_id = p.id
join public.roles r on r.id = ur.role_id
where r.key = 'mentor';
