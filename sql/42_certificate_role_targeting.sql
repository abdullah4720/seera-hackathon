-- ============================================================
-- تصنيف أنواع الشهادات حسب الفئة المستهدفة (مشارك/مرشد/محكّم)
-- ============================================================
-- يُطبّق بعد 41_certificate_status_matrix.sql
-- ============================================================

alter table public.certificate_types add column if not exists role_key text;
-- القيم الممكنة: 'participant' | 'mentor' | 'judge' | null (عام لكل الأدوار)

comment on column public.certificate_types.role_key is
  'الفئة المستهدفة بهذا النوع من الشهادات — تُعرض للمستخدم فقط إن كانت تخص دوره';
