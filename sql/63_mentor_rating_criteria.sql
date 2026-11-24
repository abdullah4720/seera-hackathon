-- ============================================================
-- تطوير نظام تقييم المرشد: معيار إضافي لملاءمة التخصص
-- ============================================================
-- يُطبّق بعد 62_merge_events_into_prep.sql
--
-- الجدول أصلًا فيه حقل "comment" لم يكن يُستخدم بالواجهة إطلاقًا.
-- هذا الملف يضيف معيار ثانٍ رقمي (ملاءمة التخصص) بجانب المعيار
-- الأصلي (مدى الاستفادة)، فيصير التقييم بمعيارين + ملاحظة نصية.
-- ============================================================

alter table public.mentor_ratings add column if not exists specialty_fit_rating int check (specialty_fit_rating between 1 and 5);

comment on column public.mentor_ratings.rating is 'مدى الاستفادة من الجلسة (1-5)';
comment on column public.mentor_ratings.specialty_fit_rating is 'مدى ملاءمة تخصص المرشد لاحتياج الفريق (1-5)';
comment on column public.mentor_ratings.comment is 'ملاحظات إضافية حرة (اختياري)';
