-- ============================================================
-- 87) خصوصية المرشدين
-- ------------------------------------------------------------
-- كانت السياسة profiles_select_mentors_public تكشف صف المرشد كاملًا
-- في profiles (ومنه الجوال والبريد ورقم الهوية) لأي زائر حتى بلا
-- تسجيل دخول.
-- • حُذفت السياسة.
-- • mentor_cards(ids): تعيد للمستخدم المسجَّل الحقول العامة فقط
--   (الاسم، التخصص، المنصب، الجهة، النبذة، النشاط، الحضور)، وتستخدمها
--   صفحة المشارك لعرض المرشدين في المواعيد والحجوزات.
-- • من يحتاج بيانات التواصل (المدير، المنسّق، الميسّر، المرشد، المحكّم)
--   يقرأ profiles كما كان عبر سياسة profiles_select_own_or_admin.
-- • عضو الفريق يرى زملاءه كما كان (profiles_select_teammates).
-- ============================================================

create or replace function public.mentor_cards(p_ids uuid[])
returns table (id uuid, full_name text, specialization text, current_position text,
               organization text, bio text, is_active boolean,
               mentor_present boolean, mentor_present_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then
    raise exception 'سجّل الدخول أولًا';
  end if;
  return query
  select p.id, p.full_name, p.specialization, p.current_position, p.organization, p.bio,
         coalesce(p.is_active, true), p.mentor_present, p.mentor_present_at
  from public.profiles p
  where p.id = any(coalesce(p_ids, '{}'::uuid[]))
    and public.user_has_role(p.id, 'mentor');
end $$;
revoke execute on function public.mentor_cards(uuid[]) from public, anon;
grant execute on function public.mentor_cards(uuid[]) to authenticated;

drop policy if exists profiles_select_mentors_public on public.profiles;

-- عرض الإجابات لا يُقرأ إلا بعد الدخول (كان مفتوحًا لـ anon، مقيَّد بـ RLS)
revoke select on public.survey_answers_flat from anon;
