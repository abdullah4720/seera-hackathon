-- ============================================================
-- بيانات شخصية إضافية للمشاركين عند التسجيل
-- ============================================================
-- يُطبّق بعد 33_complete_registration_phase.sql
-- ============================================================

alter table public.profiles add column if not exists category text;        -- طالب / خريج / عضو هيئة تدريس / أخرى
alter table public.profiles add column if not exists city text;
alter table public.profiles add column if not exists age_range text;       -- مدى العمر
alter table public.profiles add column if not exists gender text;          -- ذكر / أنثى
alter table public.profiles add column if not exists project_role text;    -- دور المشارك المتوقع بالمشروع
-- ملاحظة: عمود organization (الجهة) موجود مسبقًا بالجدول، لا حاجة لعمود جديد له
