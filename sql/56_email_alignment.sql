-- ============================================================
-- محاذاة المحتوى الإضافي بالإيميل (يمين / وسط)
-- ============================================================
-- يُطبّق بعد 55_email_body_content.sql
-- ============================================================

alter table public.email_templates add column if not exists body_alignment text default 'right' check (body_alignment in ('right','center'));
