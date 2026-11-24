-- ============================================================
-- قائمة المشاركين المستوردة (Excel) — قبل التسجيل الذاتي
-- ============================================================
-- يُطبّق بعد 18_mentor_applications.sql
-- الغرض: استيراد أسماء مشاركين معروفة مسبقًا (من نموذج خارجي مثلاً)
-- تظهر بدليل المشاركين حتى لو صاحبها ما سوّى حساب بالمنصة بعد
-- ============================================================

create table public.participant_roster (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  email text,
  phone text,
  organization text,
  track_name text,
  imported_at timestamptz default now(),
  imported_by uuid references public.profiles(id)
);
create index idx_participant_roster_email on public.participant_roster(email);

alter table public.participant_roster enable row level security;

create policy "participant_roster_admin_manage" on public.participant_roster
  for all using (public.has_role('admin') or public.has_role('coordinator'));
