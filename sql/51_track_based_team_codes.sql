-- ============================================================
-- ترميز الفرق المرتبط بالمسار (مثال: RHL-001, BSM-002)
-- ============================================================
-- يُطبّق بعد 50_journey_milestones.sql
--
-- الفكرة: كل مسار له "رمز قصير" (يُدار من لوحة التحكم)، وكل
-- فريق يأخذ رمزًا يبدأ برمز مساره + رقم تسلسلي مستقل داخل
-- ذلك المسار فقط — يعني تقدر تعرف مسار الفريق من كوده مباشرة،
-- ويسهل فرز/تجميع الفرق حسب المسار بأي جدول أو تصدير Excel
-- ============================================================

-- ------------------------------------------------------------
-- 1. عمود "رمز المسار" — يُدار من لوحة التحكم بصفحة المسارات
-- ------------------------------------------------------------
alter table public.tracks add column if not exists track_code text;

-- تعبئة أولية لرمز كل مسار (قابلة للتعديل لاحقًا
-- من لوحة التحكم بالكامل)
update public.tracks set track_code = 'RHL' where name_ar = 'رحلة السيرة النبوية' and track_code is null;
update public.tracks set track_code = 'BSM' where name_ar = 'البصمة الرقمية في السيرة النبوية' and track_code is null;

-- أي مسار ما زال بلا رمز (تجريبي أو مضاف يدويًا) ياخذ رمز افتراضي
-- من أول 3 حروف باسمه (يقدر الإداري يغيّره لاحقًا من الواجهة)
update public.tracks set track_code = upper(left(regexp_replace(name_ar, '[^a-zA-Z]', '', 'g'), 3))
where track_code is null or track_code = '';
update public.tracks set track_code = 'TRK' where track_code is null or track_code = '';

-- ------------------------------------------------------------
-- 2. دالة توليد الرمز — مرتبط بالمسار مع تسلسل مستقل لكل مسار
--    (مع قفل صف المسار لمنع تكرار الرمز عند تسجيل متزامن)
-- ------------------------------------------------------------
create or replace function public.generate_team_code()
returns trigger as $$
declare
  v_prefix text;
  v_next_num int;
begin
  if new.team_code is not null then
    return new;
  end if;

  -- قفل صف المسار أثناء العملية لضمان عدم تكرار الرقم عند تسجيل متزامن
  select coalesce(track_code, 'TRK') into v_prefix
  from public.tracks where id = new.track_id for update;

  if v_prefix is null then
    v_prefix := 'TRK';
  end if;

  select count(*) + 1 into v_next_num
  from public.teams t
  join public.tracks tr on tr.id = t.track_id
  where tr.track_code = v_prefix;

  new.team_code := v_prefix || '-' || lpad(v_next_num::text, 3, '0');
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_generate_team_code on public.teams;
create trigger trg_generate_team_code
  before insert on public.teams
  for each row execute function public.generate_team_code();

-- ------------------------------------------------------------
-- 3. اختياري: إعادة ترميز الفرق الموجودة بالنظام الجديد
--    ⚠️ نفّذ هذا فقط لو رموز الفرق الحالية (ENF-XXX) لسا ما
--    اتشاركت مع المشاركين أو بمطبوعات/شهادات — غيّر الرمز يكسر
--    أي مرجع سابق له
-- ------------------------------------------------------------
/*
do $$
declare
  r record;
  v_prefix text;
  v_next_num int;
begin
  for r in (select id, track_id from public.teams order by created_at) loop
    select coalesce(track_code,'TRK') into v_prefix from public.tracks where id = r.track_id;
    select count(*) into v_next_num
    from public.teams t join public.tracks tr on tr.id = t.track_id
    where tr.track_code = v_prefix and t.created_at <= (select created_at from public.teams where id = r.id);
    update public.teams set team_code = v_prefix || '-' || lpad(v_next_num::text, 3, '0') where id = r.id;
  end loop;
end $$;
*/

-- تحقق من النتيجة
select tr.track_code, t.team_code, t.team_name
from public.teams t join public.tracks tr on tr.id = t.track_id
order by tr.track_code, t.team_code;
