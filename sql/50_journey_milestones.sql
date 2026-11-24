-- ============================================================
-- نظام "رحلتك بالهاكثون" — خطوات مرنة يديرها الإداري بالكامل
-- ============================================================
-- يُطبّق بعد 49_final_tracks_copy.sql
--
-- الفكرة: بدل خطوات ثابتة بالكود، جدول يحدد فيه الإداري أي
-- خطوات تظهر، بأي ترتيب، بأي تسمية وأيقونة — لكن "شرط الإنجاز"
-- نفسه يُختار من قائمة أنواع فحص جاهزة وموثوقة (مو نص حر يكتبه
-- الإداري، لتفادي كسر النظام بشرط خاطئ)
-- ============================================================

create table public.journey_milestones (
  id uuid primary key default gen_random_uuid(),
  check_type text not null check (check_type in (
    'profile_complete',   -- الملف الشخصي مكتمل (كل الحقول معبّأة)
    'team_formed',        -- عضو بفريق (2 أعضاء فأكثر)
    'idea_submitted',     -- تم تقديم فكرة المشروع
    'file_uploaded',      -- تم إرفاق ملف/رابط للمشروع
    'mentor_booked',      -- تم حجز موعد إرشاد واحد على الأقل
    'prep_attended',      -- حضر جلسة تحضير واحدة على الأقل
    'survey_answered'     -- أجاب على استبيان واحد على الأقل
  )),
  label_ar text not null,
  description text,
  icon text not null default 'circle-check',
  display_order int default 0,
  is_active boolean default true,
  created_at timestamptz default now()
);

alter table public.journey_milestones enable row level security;

create policy "journey_milestones_select_all" on public.journey_milestones
  for select using (true);

create policy "journey_milestones_admin_manage" on public.journey_milestones
  for all using (public.has_role('admin') or public.has_role('coordinator'));

-- ------------------------------------------------------------
-- تعبئة الخطوات الافتراضية (قابلة للتعديل/الحذف/إعادة الترتيب
-- بالكامل من لوحة التحكم لاحقًا)
-- ------------------------------------------------------------
insert into public.journey_milestones (check_type, label_ar, description, icon, display_order) values
  ('profile_complete', 'أكمل ملفك الشخصي', 'عبّئ كل بياناتك من تبويب "ملفي الشخصي"', 'user-round', 1),
  ('team_formed', 'كوّن فريقك', 'انضم لفريق أو أنشئ فريقك الخاص', 'users-round', 2),
  ('idea_submitted', 'قدّم فكرة مشروعك', 'أضف عنوان ووصف فكرتك من تبويب "فريقي"', 'lightbulb', 3),
  ('file_uploaded', 'أرفق ملف مشروعك', 'ارفع ملف أو رابط يوضّح فكرتك بالتفصيل', 'paperclip', 4),
  ('mentor_booked', 'احجز جلسة إرشاد', 'استفد من خبرة أحد المرشدين', 'graduation-cap', 5)
on conflict do nothing;
