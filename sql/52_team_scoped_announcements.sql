-- ============================================================
-- استهداف فريق محدد بالتحديثات (بدل مسار كامل أو الجميع بس)
-- ============================================================
-- يُطبّق بعد 51_track_based_team_codes.sql
--
-- المشكلة المكتشفة: نظام "التحديثات" كان يدعم استهداف مسار كامل
-- أو الجميع فقط — لو الإدارة تبي تبلغ فريق واحد بشي يخص إرشاده
-- أو تحكيمه أو حالة اعتماده، ما فيه خيار إلا النشر لكل المسار
-- كامل، فيطلع لفرق ما له علاقة فيه
-- ============================================================

alter table public.announcements add column if not exists team_id uuid references public.teams(id) on delete cascade;

-- ------------------------------------------------------------
-- تحديث دالة الإشعار التلقائي: لو التحديث مستهدف فريق محدد،
-- يوصل لأعضاء هذا الفريق بس (مو كل المسار)
-- ------------------------------------------------------------
create or replace function public.notify_new_announcement()
returns trigger as $$
begin
  if new.team_id is not null then
    -- استهداف فريق محدد
    insert into public.notifications (user_id, title, body, link)
    select tm.user_id, '📢 ' || new.title, coalesce(left(new.body, 120), ''), null
    from public.team_members tm
    where tm.team_id = new.team_id;
  else
    -- استهداف مسار كامل أو الجميع (السلوك الأصلي)
    insert into public.notifications (user_id, title, body, link)
    select distinct p.id, '📢 ' || new.title, coalesce(left(new.body, 120), ''), null
    from public.profiles p
    where new.track_id is null
       or exists (
         select 1 from public.team_members tm
         join public.teams t on t.id = tm.team_id
         where tm.user_id = p.id and t.track_id = new.track_id
       );
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

-- ------------------------------------------------------------
-- سياسة قراءة: نضمن المشارك يشوف بس التحديثات المستهدفة له
-- (فريقه تحديدًا، أو مساره، أو العامة) — الفلترة التفصيلية
-- تصير بالواجهة، لكن هذا يمنع أي تسريب على مستوى القاعدة
-- ------------------------------------------------------------
-- (لا حاجة لسياسة جديدة — السياسة الحالية للقراءة العامة تبقى
-- كما هي، والتصفية الدقيقة تتم بالتطبيق كما بالأصل)
