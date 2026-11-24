-- ============================================================
-- إصلاح: سياسات إدراج أكثر ثباتًا (auth.uid() بدل auth.role())
-- ============================================================
-- يُطبّق بعد 07_manual_confirm.sql
-- ============================================================

-- teams: إعادة إنشاء سياسة الإدراج
drop policy if exists "teams_insert_authenticated" on public.teams;
create policy "teams_insert_authenticated" on public.teams
  for insert with check (auth.uid() is not null);

-- team_members: تأكيد نفس المنطق (لا تغيير بالشرط لكن نعيد إنشاءها للتأكد)
drop policy if exists "team_members_insert" on public.team_members;
create policy "team_members_insert" on public.team_members
  for insert with check (
    (user_id = auth.uid() and auth.uid() is not null) or public.has_role('admin')
  );

-- submissions: نفس المبدأ للتأكد من عدم وجود مشكلة مشابهة لاحقًا
drop policy if exists "submissions_insert_team_member" on public.submissions;
create policy "submissions_insert_team_member" on public.submissions
  for insert with check (public.is_team_member(team_id) and auth.uid() is not null);

-- ------------------------------------------------------------
-- تحقق سريع بعد التطبيق: شغّل هذا وأنت مسجّل دخول بالتطبيق
-- (من المتصفح مباشرة عبر console، أو تجاهله إذا اختبرت بالواجهة)
-- select auth.uid();  -- يجب ألا يكون NULL أثناء وجود جلسة فعّالة
-- ------------------------------------------------------------
