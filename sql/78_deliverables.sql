-- ============================================================
-- 78) التسليمات المطلوبة من الفرق (منقولة من ابتكار إنفاذ)
--   الإدارة تحدد المطلوبات (عرض تقديمي، فيديو...)، والفريق يرفع ملفه،
--   والمحكّمون يرونها مرتّبة حسب لجانهم.
--   تشديد عن إنفاذ: الرفع إلى التخزين مقصور على مجلد فريق المستخدم.
-- ============================================================

create table if not exists public.deliverables (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  due_at timestamptz,
  is_required boolean default true,
  is_open boolean default true,
  allowed_types text,
  max_size_mb integer default 25,
  track_id uuid references public.tracks(id) on delete cascade,
  sort_order integer default 0,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz default now()
);

create table if not exists public.deliverable_submissions (
  id uuid primary key default gen_random_uuid(),
  deliverable_id uuid not null references public.deliverables(id) on delete cascade,
  team_id uuid not null references public.teams(id) on delete cascade,
  file_url text not null,
  file_name text,
  file_size_kb integer,
  note text,
  submitted_by uuid references public.profiles(id) on delete set null,
  submitted_at timestamptz default now(),
  review_status text default 'pending' check (review_status in ('pending','accepted','rejected')),
  review_note text,
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  unique (deliverable_id, team_id)
);

alter table public.deliverables enable row level security;
alter table public.deliverable_submissions enable row level security;

do $$ begin
  if not exists (select 1 from pg_policy where polname='deliverables_select' and polrelid='public.deliverables'::regclass) then
    create policy deliverables_select on public.deliverables for select using (auth.uid() is not null);
    create policy deliverables_manage on public.deliverables for all
      using (public.has_role('admin') or public.has_role('coordinator'))
      with check (public.has_role('admin') or public.has_role('coordinator'));
  end if;
  if not exists (select 1 from pg_policy where polname='deliv_sub_select' and polrelid='public.deliverable_submissions'::regclass) then
    create policy deliv_sub_select on public.deliverable_submissions for select
      using (public.is_team_member(team_id) or public.has_role('admin') or public.has_role('coordinator') or public.has_role('judge'));
    create policy deliv_sub_insert on public.deliverable_submissions for insert
      with check (public.is_team_member(team_id)
                  and exists (select 1 from public.deliverables d where d.id = deliverable_id and d.is_open));
    create policy deliv_sub_update on public.deliverable_submissions for update
      using ((public.is_team_member(team_id) and exists (select 1 from public.deliverables d where d.id = deliverable_id and d.is_open))
             or public.has_role('admin') or public.has_role('coordinator'));
    create policy deliv_sub_delete on public.deliverable_submissions for delete
      using ((public.is_team_member(team_id) and exists (select 1 from public.deliverables d where d.id = deliverable_id and d.is_open))
             or public.has_role('admin') or public.has_role('coordinator'));
  end if;
end $$;

-- التخزين: مجلد لكل فريق ‎{team_id}/{deliverable_id}/ملف‎
insert into storage.buckets (id, name, public, file_size_limit)
values ('deliverables', 'deliverables', true, 52428800)
on conflict (id) do nothing;

do $$ begin
  if not exists (select 1 from pg_policy where polname='deliverables_storage_select' and polrelid='storage.objects'::regclass) then
    create policy deliverables_storage_select on storage.objects for select using (bucket_id = 'deliverables');
    create policy deliverables_storage_insert on storage.objects for insert
      with check (bucket_id = 'deliverables' and auth.uid() is not null
                  and ((storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$'
                       and public.is_team_member(((storage.foldername(name))[1])::uuid)
                       or public.has_role('admin') or public.has_role('coordinator')));
    create policy deliverables_storage_update on storage.objects for update
      using (bucket_id = 'deliverables' and auth.uid() is not null
             and ((storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$'
                  and public.is_team_member(((storage.foldername(name))[1])::uuid)
                  or public.has_role('admin') or public.has_role('coordinator')));
    create policy deliverables_storage_delete on storage.objects for delete
      using (bucket_id = 'deliverables' and (public.has_role('admin') or public.has_role('coordinator')));
  end if;
end $$;

create or replace view public.deliverables_status with (security_invoker = on) as
select d.id as deliverable_id, d.title as deliverable_title, d.due_at, d.is_required, d.is_open,
       t.id as team_id, t.team_name, t.track_id, tr.name_ar as track_name,
       s.id as submission_id, s.file_url, s.file_name, s.submitted_at, s.review_status, s.review_note,
       case when s.id is null and d.due_at is not null and now() > d.due_at then 'متأخر'
            when s.id is null then 'لم يُسلَّم'
            when s.review_status = 'accepted' then 'مقبول'
            when s.review_status = 'rejected' then 'مرفوض'
            else 'بانتظار المراجعة' end as "الحالة"
from public.deliverables d
cross join public.teams t
left join public.tracks tr on tr.id = t.track_id
left join public.deliverable_submissions s on s.deliverable_id = d.id and s.team_id = t.id
where t.status = 'confirmed' and (d.track_id is null or d.track_id = t.track_id);

create or replace view public.deliverables_by_committee with (security_invoker = on) as
select ds.id as submission_id, d.id as deliverable_id, d.title as "التسليم", d.is_required as "إلزامي",
       t.id as team_id, t.team_name as "الفريق", t.team_code as "رمز_الفريق", tr.name_ar as "المسار",
       c.id as committee_id, c.name_ar as "اللجنة", a.judging_order as "ترتيب_التحكيم",
       ds.file_url as "رابط_الملف", ds.file_name as "اسم_الملف", ds.file_size_kb as "الحجم_كيلوبايت",
       ds.note as "ملاحظة_الفريق", ds.review_status as "حالة_المراجعة", ds.submitted_at as "وقت_التسليم"
from public.deliverable_submissions ds
join public.deliverables d on d.id = ds.deliverable_id
join public.teams t on t.id = ds.team_id
left join public.tracks tr on tr.id = t.track_id
left join lateral (select distinct a2.committee_id, a2.judging_order from public.judge_assignments a2
                   where a2.team_id = t.id and a2.committee_id is not null limit 1) a on true
left join public.judging_committees c on c.id = a.committee_id
order by c.name_ar, a.judging_order, t.team_code, d.sort_order;

revoke select on public.deliverables_status, public.deliverables_by_committee from anon;
