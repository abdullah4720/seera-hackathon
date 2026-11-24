-- ============================================================
-- قالب بريد إلكتروني قابل للتخصيص من لوحة التحكم (صف واحد)
-- ============================================================
-- يُطبّق بعد 53_track_details.sql
--
-- الدالة السحابية (send-email-notification) تقرأ من هذا الجدول
-- بدل نص مكتوب بالكود مباشرة — تقدر تغيّر الصياغة بدون نشر أي
-- كود جديد أو لمس الدالة السحابية إطلاقًا
-- ============================================================

create table public.email_templates (
  id uuid primary key default gen_random_uuid(),
  greeting_text text not null default 'مرحبًا {{name}}،',
  footer_org_text text not null default 'هاكثون السيرة النبوية — جامعة القصيم',
  button_text text not null default 'فتح المنصة',
  updated_at timestamptz default now()
);

alter table public.email_templates enable row level security;

create policy "email_templates_select_all" on public.email_templates
  for select using (true);

create policy "email_templates_admin_manage" on public.email_templates
  for all using (public.has_role('admin') or public.has_role('coordinator'));

-- صف افتراضي واحد (القالب الوحيد بالمنصة)
insert into public.email_templates (greeting_text, footer_org_text, button_text)
values ('مرحبًا {{name}}،', 'هاكثون السيرة النبوية — جامعة القصيم', 'فتح المنصة')
on conflict do nothing;
