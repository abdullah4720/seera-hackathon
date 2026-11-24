-- ============================================================
-- 67: حقول نموذج التسليم الخاصة بهاكثون السيرة النبوية
-- شغّله فقط إن كنت شغّلت الملف 47 قبل تحديثه (أي ظهرت لك حقول
-- السجل التجاري وبراءة الاختراع في نموذج التسليم).
-- آمن للتكرار، ولا يغيّر أي جدول أو سياسة RLS — بيانات فقط.
-- ============================================================

-- إزالة الحقول الموروثة من برنامج سابق (تجارية/براءات)
delete from public.submission_field_definitions
where field_key in (
  'project_domain', 'has_commercial_registration', 'has_patent',
  'potential_applications', 'received_prior_support',
  'prior_support_details', 'funding_entity'
);

-- الحقول المناسبة للهاكثون (تُحدَّث إن وُجدت)
insert into public.submission_field_definitions (field_key, label_ar, field_type, options, is_required, display_order) values
  ('digital_format', 'نوع المنتج الرقمي', 'select', '["تطبيق جوال","موقع أو منصة ويب","لعبة تفاعلية","تجربة واقع افتراضي/معزز","محتوى مرئي أو صوتي","أداة ذكاء اصطناعي","أخرى"]'::jsonb, true, 1),
  ('seerah_focus', 'المحطة أو الجانب من السيرة النبوية الذي يتناوله المشروع', 'text', null, true, 2),
  ('target_audience', 'الفئة المستهدفة', 'text', null, true, 3),
  ('content_sources', 'المصادر الموثوقة المعتمدة في محتوى المشروع (كتب السيرة والمراجع)', 'textarea', null, true, 4),
  ('expected_impact', 'الأثر التربوي أو المعرفي المتوقع للمشروع', 'textarea', null, true, 5),
  ('has_prototype', 'هل يوجد نموذج أولي رقمي قابل للتجربة؟', 'boolean', null, true, 6),
  ('prototype_link', 'رابط النموذج الأولي (إن وُجد)', 'text', null, false, 7)
on conflict (field_key) do update set
  label_ar = excluded.label_ar,
  field_type = excluded.field_type,
  options = excluded.options,
  is_required = excluded.is_required,
  display_order = excluded.display_order,
  is_active = true;
