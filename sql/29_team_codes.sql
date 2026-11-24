-- ============================================================
-- ترميز تلقائي للفرق/المشاريع (مثال: ENF-001, ENF-002...)
-- ============================================================
-- يُطبّق بعد 28_fix_approval_and_debug_tool.sql
-- ============================================================

-- تسلسل الترقيم
create sequence if not exists public.team_code_seq start 1;

-- عمود الرمز
alter table public.teams add column if not exists team_code text unique;

-- دالة توليد الرمز تلقائيًا عند إنشاء فريق جديد
create or replace function public.generate_team_code()
returns trigger as $$
begin
  if new.team_code is null then
    new.team_code := 'ENF-' || lpad(nextval('public.team_code_seq')::text, 3, '0');
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_generate_team_code on public.teams;
create trigger trg_generate_team_code
  before insert on public.teams
  for each row execute function public.generate_team_code();

-- ترميز الفرق الموجودة مسبقًا (حسب تاريخ الإنشاء)
do $$
declare
  r record;
begin
  for r in (select id from public.teams where team_code is null order by created_at) loop
    update public.teams set team_code = 'ENF-' || lpad(nextval('public.team_code_seq')::text, 3, '0') where id = r.id;
  end loop;
end $$;
