-- ============================================================
-- نظام حقول ديناميكي لنموذج المشروع (الفرز الأولي)
-- ============================================================
-- يُطبّق بعد 46_visibility_and_enhancements.sql
--
-- الفكرة: بدل حقول ثابتة بالكود، جدول تعريف حقول يديره الإداري
-- بالكامل (إضافة/حذف/تعديل/إعادة ترتيب)، والإجابات تُخزَّن
-- بعمود JSONB واحد على submissions — مرن بدون أي migration جديد
-- كل ما تحتاج تضيف حقل
-- ============================================================

create table public.submission_field_definitions (
  id uuid primary key default gen_random_uuid(),
  field_key text not null unique,           -- معرّف فريد بالإنجليزي (project_domain مثلاً)
  label_ar text not null,                    -- التسمية المعروضة
  field_type text not null check (field_type in ('text','textarea','number','boolean','select')),
  options jsonb,                             -- لقوائم select: ["خيار 1","خيار 2"]
  is_required boolean default false,
  display_order int default 0,
  is_active boolean default true,
  created_at timestamptz default now()
);

alter table public.submission_field_definitions enable row level security;

create policy "submission_fields_select_all" on public.submission_field_definitions
  for select using (true);

create policy "submission_fields_admin_manage" on public.submission_field_definitions
  for all using (public.has_role('admin') or public.has_role('coordinator'));

-- ------------------------------------------------------------
-- عمود تخزين إجابات الحقول الديناميكية على المشروع
-- ------------------------------------------------------------
alter table public.submissions add column if not exists custom_fields jsonb default '{}'::jsonb;

-- ------------------------------------------------------------
-- تعبئة الحقول المطلوبة بالبداية (قابلة للتعديل/الحذف لاحقًا
-- بالكامل من لوحة التحكم)
-- ------------------------------------------------------------
insert into public.submission_field_definitions (field_key, label_ar, field_type, options, is_required, display_order) values
  ('digital_format', 'نوع المنتج الرقمي', 'select', '["تطبيق جوال","موقع أو منصة ويب","لعبة تفاعلية","تجربة واقع افتراضي/معزز","محتوى مرئي أو صوتي","أداة ذكاء اصطناعي","أخرى"]'::jsonb, true, 1),
  ('seerah_focus', 'المحطة أو الجانب من السيرة النبوية الذي يتناوله المشروع', 'text', null, true, 2),
  ('target_audience', 'الفئة المستهدفة', 'text', null, true, 3),
  ('content_sources', 'المصادر الموثوقة المعتمدة في محتوى المشروع (كتب السيرة والمراجع)', 'textarea', null, true, 4),
  ('expected_impact', 'الأثر التربوي أو المعرفي المتوقع للمشروع', 'textarea', null, true, 5),
  ('has_prototype', 'هل يوجد نموذج أولي رقمي قابل للتجربة؟', 'boolean', null, true, 6),
  ('prototype_link', 'رابط النموذج الأولي (إن وُجد)', 'text', null, false, 7)
on conflict (field_key) do nothing;
