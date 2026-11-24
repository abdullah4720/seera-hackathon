-- ============================================================
-- 68: إخضاع شاشات العرض (Views) الإدارية لسياسات RLS
-- بدونه: أي شخص يملك المفتاح العام يقرأ أسماء وإيميلات المشاركين
-- ودرجات التحكيم قبل النشر. بعده: الإدارة والمنسق يرونها كما هي، وغيرهم لا.
-- يتطلب PostgreSQL 15+ (متوفر في Supabase).
-- ============================================================
alter view public.team_scores_summary set (security_invoker = true);
alter view public.dashboard_stats set (security_invoker = true);
alter view public.satisfaction_by_stage set (security_invoker = true);
alter view public.user_attendance_summary set (security_invoker = true);
alter view public.certificate_status_matrix set (security_invoker = true);
revoke select on public.team_scores_summary, public.dashboard_stats, public.satisfaction_by_stage, public.user_attendance_summary, public.certificate_status_matrix from anon;
