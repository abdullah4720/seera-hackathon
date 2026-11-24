-- ============================================================
-- منصة هاكثون السيرة النبوية - بيانات أولية (Seed Data)
-- ============================================================
-- يُطبّق بعد 03_functions.sql
-- كل هذه القيم قابلة للتعديل لاحقًا من لوحة التحكم
-- ============================================================

-- الأدوار الأساسية
insert into public.roles (key, name_ar, name_en) values
  ('participant', 'مشارك', 'Participant'),
  ('mentor', 'مرشد', 'Mentor'),
  ('judge', 'محكّم', 'Judge'),
  ('coordinator', 'منسق', 'Coordinator'),
  ('admin', 'مدير النظام', 'Admin')
on conflict (key) do nothing;

-- المسارات (من نشرة البرنامج)
insert into public.tracks (name_ar, name_en, description, max_team_size, min_team_size, display_order) values
  ('رحلة السيرة النبوية', 'Prophetic Biography Journey',
   'مشاريع رقمية تأخذ المتلقي في رحلة تفاعلية عبر محطات السيرة النبوية ومواقفها بلغة العصر.', 5, 2, 1),
  ('البصمة الرقمية في السيرة النبوية', 'Digital Imprint in the Prophetic Biography',
   'حلول وأدوات رقمية مبتكرة تُجسّد المعاني التربوية والإنسانية للسيرة النبوية بأساليب إبداعية تفاعلية.', 5, 2, 2);

-- أنواع الشهادات
insert into public.certificate_types (key, name_ar, min_attendance_pct, requires_survey) values
  ('participation', 'شهادة مشاركة', 50, true),
  ('mentor', 'شهادة تقدير للمرشدين', 0, false),
  ('judge', 'شهادة تقدير للمحكّمين', 0, false),
  ('winner', 'شهادة الفوز', 0, false);

-- جولة التحكيم
insert into public.judging_rounds (name_ar, round_order, is_active) values
  ('التحكيم النهائي', 1, false);

-- معايير التحكيم (مقياس 1-5) — تُعدَّل من لوحة التحكم
insert into public.judging_criteria (round_id, name_ar, description, weight, max_score, display_order)
select id, 'الأصالة والإبداع في الفكرة', 'جِدّة الفكرة وأسلوب تقديم السيرة النبوية بطريقة إبداعية غير تقليدية', 20, 5, 1
  from public.judging_rounds where round_order = 1
union all
select id, 'دقة المحتوى وارتباطه بالسيرة النبوية', 'سلامة المحتوى ودقته ووضوح ارتباطه بالمواقف والقيم النبوية', 25, 5, 2
  from public.judging_rounds where round_order = 1
union all
select id, 'الجودة التقنية والتنفيذ', 'جودة التنفيذ الرقمي ونضج النموذج الأولي وسهولة الاستخدام', 20, 5, 3
  from public.judging_rounds where round_order = 1
union all
select id, 'الأثر التربوي والإنساني', 'قدرة المشروع على إيصال المعاني التربوية والإنسانية للفئة المستهدفة', 20, 5, 4
  from public.judging_rounds where round_order = 1
union all
select id, 'جودة العرض التقديمي', 'وضوح العرض وتنظيمه وقدرة الفريق على الإقناع', 15, 5, 5
  from public.judging_rounds where round_order = 1;

-- استبيان رضا (مرحلة ختامية)
insert into public.surveys (title, target_stage, questions_json, gates_certificate_type_id)
select
  'استبيان تقييم هاكثون السيرة النبوية',
  'closing',
  '[
    {"id": "q1", "type": "nps", "question_ar": "ما مدى احتمالية ترشيحك لهذا البرنامج لزميل؟"},
    {"id": "q2", "type": "rating", "question_ar": "تقييمك لجودة البرامج التدريبية"},
    {"id": "q3", "type": "rating", "question_ar": "تقييمك لتجربة الإرشاد"},
    {"id": "q4", "type": "rating", "question_ar": "تقييمك لتنظيم يوم التحكيم"},
    {"id": "q5", "type": "text", "question_ar": "أبرز الملاحظات أو المقترحات للتحسين"}
  ]'::jsonb,
  ct.id
from public.certificate_types ct where ct.key = 'participation';
