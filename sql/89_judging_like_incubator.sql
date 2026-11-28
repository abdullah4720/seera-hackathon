-- ============================================================
-- 89) تحكيم على نمط «حاضنة ابتكار 5» (بلا فترات زمنية)
-- ------------------------------------------------------------
-- • مسودة ثم إرسال نهائي: المسودة تُحفظ في judge_evaluations.draft_scores
--   ولا تدخل جدول scores إلا عند الإرسال النهائي، فتبقى كل عروض النتائج
--   القائمة (final_rankings، judging_summary، judging_progress، ...)
--   تحسب الإرسال النهائي وحده تلقائيًا. بعد الإرسال لا تعديل إلا إذا
--   أعاد المدير فتح التقييم (admin_delete_judge_evaluation).
-- • الكتابة على scores صارت عبر save_evaluation وحدها (أو المدير).
-- • قفل الجولة كاملة (judging_rounds.is_locked) يوقف أي حفظ أو إرسال.
-- • اعتذار مشروع عن التحكيم في جولة (judging_withdrawals).
-- • judge_projects: مشاريع الجولة للمحكّم (المُسندة له وكل المشاريع
--   للاطلاع) مع الوصف والتسليمات وأسماء الأعضاء — بلا جوال ولا بريد.
--   سياسة teams لا تسمح للمحكّم بقراءة الفرق، فكانت أسماء الفرق تصل فارغة.
-- • reassign_judge: الاستبدال صار عبر عضوية اللجنة مع نقل ترتيب العرض،
--   ويبقى ما قيّمه المحكّم الأصلي معه (كان يضاعف عدد المحكّمين للمشروع).
-- اعتماد اللجنة لكل فريق باقٍ كما هو.
-- ============================================================

alter table public.judging_rounds add column if not exists is_locked boolean not null default false;
alter table public.judging_rounds add column if not exists locked_at timestamptz;

create table if not exists public.judge_evaluations (
  id            uuid primary key default gen_random_uuid(),
  judge_user_id uuid not null references public.profiles(id) on delete cascade,
  team_id       uuid not null references public.teams(id) on delete cascade,
  round_id      uuid not null references public.judging_rounds(id) on delete cascade,
  draft_scores  jsonb not null default '{}'::jsonb,
  overall_note  text,
  is_submitted  boolean not null default false,
  submitted_at  timestamptz,
  updated_at    timestamptz not null default now(),
  unique (judge_user_id, team_id, round_id)
);
alter table public.judge_evaluations enable row level security;
create policy judge_evaluations_select_own_or_admin on public.judge_evaluations
  for select using (judge_user_id = auth.uid() or public.has_role('admin') or public.has_role('coordinator'));

create table if not exists public.judging_withdrawals (
  team_id      uuid not null references public.teams(id) on delete cascade,
  round_id     uuid not null references public.judging_rounds(id) on delete cascade,
  reason       text,
  withdrawn_at timestamptz not null default now(),
  withdrawn_by uuid references public.profiles(id),
  primary key (team_id, round_id)
);
alter table public.judging_withdrawals enable row level security;
create policy judging_withdrawals_select_staff on public.judging_withdrawals
  for select using (public.has_role('admin') or public.has_role('coordinator') or public.has_role('judge'));

-- ---------- حارس الكتابة على الدرجات ----------
create or replace function public.guard_scores_write()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_round uuid := coalesce(new.round_id, old.round_id); v_staff boolean;
begin
  if auth.uid() is null then return coalesce(new, old); end if;   -- الخادم/المهام
  v_staff := public.has_role('admin') or public.has_role('coordinator');
  if not v_staff and coalesce(current_setting('app.eval_rpc', true), '') <> 'on' then
    raise exception 'التقييم يُحفظ من صفحة المحكّم فقط';
  end if;
  if not v_staff and exists (select 1 from public.judging_rounds where id = v_round and is_locked) then
    raise exception 'التحكيم مقفل لهذه الجولة';
  end if;
  return coalesce(new, old);
end $$;
drop trigger if exists trg_guard_scores_write on public.scores;
create trigger trg_guard_scores_write before insert or update or delete on public.scores
  for each row execute function public.guard_scores_write();

-- ---------- حفظ التقييم (مسودة أو نهائي) ----------
create or replace function public.save_evaluation(
  p_round_id uuid, p_team_id uuid, p_scores jsonb, p_note text, p_submit boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid(); v_round record; v_eval record; v_key text; v_val numeric;
  v_crit record; v_missing int; v_total numeric;
begin
  if v_uid is null then return jsonb_build_object('success', false, 'error', 'سجّل الدخول أولًا'); end if;
  if not exists (select 1 from public.judge_assignments
                 where judge_user_id = v_uid and team_id = p_team_id and round_id = p_round_id) then
    return jsonb_build_object('success', false, 'error', 'هذا المشروع غير مُسند إليك في هذه الجولة');
  end if;
  if exists (select 1 from public.judge_assignments
             where judge_user_id = v_uid and team_id = p_team_id and round_id = p_round_id and has_conflict) then
    return jsonb_build_object('success', false, 'error', 'لديك تعارض مصالح مع هذا الفريق — تواصل مع الإدارة');
  end if;
  select * into v_round from public.judging_rounds where id = p_round_id;
  if v_round.id is null or not v_round.is_active then
    return jsonb_build_object('success', false, 'error', 'الجولة غير نشطة');
  end if;
  if v_round.is_locked then
    return jsonb_build_object('success', false, 'error', 'التحكيم مقفل لهذه الجولة — لا يمكن الحفظ أو الإرسال');
  end if;
  if v_round.results_published then
    return jsonb_build_object('success', false, 'error', 'نُشرت نتائج هذه الجولة — التعديل مقفل');
  end if;
  if exists (select 1 from public.judging_withdrawals where team_id = p_team_id and round_id = p_round_id) then
    return jsonb_build_object('success', false, 'error', 'اعتذر هذا المشروع عن التحكيم في هذه الجولة');
  end if;
  if exists (select 1 from public.judging_approvals where team_id = p_team_id and round_id = p_round_id and status = 'approved') then
    return jsonb_build_object('success', false, 'error', 'اعتمدت اللجنة نتيجة هذا الفريق — التعديل مقفل');
  end if;
  select * into v_eval from public.judge_evaluations
  where judge_user_id = v_uid and team_id = p_team_id and round_id = p_round_id;
  if v_eval.is_submitted then
    return jsonb_build_object('success', false, 'error', 'أرسلت تقييمك النهائي لهذا المشروع — لا يمكن تعديله');
  end if;

  -- التحقق من الدرجات: مفاتيح معايير الجولة، وقيم صحيحة من 1 إلى الأقصى
  for v_key, v_val in select key, (value #>> '{}')::numeric from jsonb_each(coalesce(p_scores, '{}'::jsonb)) loop
    select * into v_crit from public.judging_criteria where id = v_key::uuid and round_id = p_round_id;
    if v_crit.id is null then
      return jsonb_build_object('success', false, 'error', 'معيار غير معروف في هذه الجولة');
    end if;
    if v_val is null or v_val <> trunc(v_val) or v_val < 1 or v_val > coalesce(v_crit.max_score, 5) then
      return jsonb_build_object('success', false, 'error', 'درجة غير صحيحة للمعيار «' || v_crit.name_ar || '»');
    end if;
  end loop;

  if p_submit then
    select count(*) into v_missing from public.judging_criteria c
    where c.round_id = p_round_id and not (coalesce(p_scores, '{}'::jsonb) ? c.id::text);
    if v_missing > 0 then
      return jsonb_build_object('success', false, 'error', 'اختر درجة لكل المعايير قبل الإرسال النهائي');
    end if;
    perform set_config('app.eval_rpc', 'on', true);
    insert into public.scores (judge_user_id, team_id, round_id, criteria_id, score, comments)
    select v_uid, p_team_id, p_round_id, c.id, (p_scores ->> c.id::text)::numeric, nullif(btrim(p_note), '')
    from public.judging_criteria c where c.round_id = p_round_id
    on conflict (judge_user_id, team_id, round_id, criteria_id)
    do update set score = excluded.score, comments = excluded.comments, submitted_at = now();
    perform set_config('app.eval_rpc', 'off', true);
  end if;

  insert into public.judge_evaluations (judge_user_id, team_id, round_id, draft_scores, overall_note, is_submitted, submitted_at, updated_at)
  values (v_uid, p_team_id, p_round_id, coalesce(p_scores, '{}'::jsonb), nullif(btrim(p_note), ''), p_submit,
          case when p_submit then now() end, now())
  on conflict (judge_user_id, team_id, round_id) do update set
    draft_scores = excluded.draft_scores, overall_note = excluded.overall_note,
    is_submitted = excluded.is_submitted, submitted_at = excluded.submitted_at, updated_at = now();

  select round(100 * sum((p_scores ->> c.id::text)::numeric / coalesce(nullif(c.max_score, 0), 5) * c.weight)
               / nullif(sum(c.weight), 0), 1)
  into v_total from public.judging_criteria c
  where c.round_id = p_round_id and p_scores ? c.id::text;

  return jsonb_build_object('success', true, 'submitted', p_submit, 'total', v_total);
end $$;

-- ---------- إعادة فتح التقييم = حذف الإرسال النهائي مع الأرشفة ----------
create or replace function public.admin_delete_judge_evaluation(p_judge_id uuid, p_team_id uuid, p_round_id uuid, p_reason text)
returns json language plpgsql security definer set search_path = public as $$
declare v_count int; v_draft jsonb;
begin
  if not (public.has_role('admin') or public.has_role('coordinator')) then
    return json_build_object('success', false, 'error', 'صلاحية غير كافية');
  end if;
  if p_reason is null or btrim(p_reason) = '' then
    return json_build_object('success', false, 'error', 'سبب الحذف إلزامي');
  end if;
  select coalesce(jsonb_object_agg(s.criteria_id::text, s.score), '{}'::jsonb) into v_draft
  from public.scores s where s.judge_user_id = p_judge_id and s.team_id = p_team_id and s.round_id = p_round_id;
  insert into public.scores_deleted_archive
    (original_id, judge_user_id, team_id, round_id, criteria_id, score, comments, submitted_at, deleted_by, deletion_reason)
  select s.id, s.judge_user_id, s.team_id, s.round_id, s.criteria_id, s.score, s.comments, s.submitted_at, auth.uid(), btrim(p_reason)
  from public.scores s where s.judge_user_id = p_judge_id and s.team_id = p_team_id and s.round_id = p_round_id;
  get diagnostics v_count = row_count;
  if v_count = 0 and not exists (select 1 from public.judge_evaluations
      where judge_user_id = p_judge_id and team_id = p_team_id and round_id = p_round_id and is_submitted) then
    return json_build_object('success', false, 'error', 'لا يوجد تقييم نهائي لهذا المحكّم على هذا الفريق');
  end if;
  delete from public.scores where judge_user_id = p_judge_id and team_id = p_team_id and round_id = p_round_id;
  -- يعود التقييم مسودة بدرجاته السابقة ليعدّلها المحكّم ويرسله من جديد
  update public.judge_evaluations
  set is_submitted = false, submitted_at = null, updated_at = now(),
      draft_scores = case when v_draft = '{}'::jsonb then draft_scores else v_draft end
  where judge_user_id = p_judge_id and team_id = p_team_id and round_id = p_round_id;
  return json_build_object('success', true, 'deleted_count', v_count);
end $$;

-- ---------- قفل الجولة ----------
create or replace function public.set_round_lock(p_round_id uuid, p_locked boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not (public.has_role('admin') or public.has_role('coordinator')) then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل');
  end if;
  update public.judging_rounds set is_locked = p_locked, locked_at = case when p_locked then now() end
  where id = p_round_id;
  if not found then return jsonb_build_object('success', false, 'error', 'الجولة غير موجودة'); end if;
  return jsonb_build_object('success', true, 'locked', p_locked);
end $$;

-- ---------- اعتذار مشروع عن التحكيم ----------
create or replace function public.set_team_withdrawal(p_team_id uuid, p_round_id uuid, p_withdrawn boolean, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not (public.has_role('admin') or public.has_role('coordinator')) then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل');
  end if;
  if p_withdrawn then
    insert into public.judging_withdrawals (team_id, round_id, reason, withdrawn_by)
    values (p_team_id, p_round_id, nullif(btrim(p_reason), ''), auth.uid())
    on conflict (team_id, round_id) do update set reason = excluded.reason, withdrawn_at = now(), withdrawn_by = auth.uid();
  else
    delete from public.judging_withdrawals where team_id = p_team_id and round_id = p_round_id;
  end if;
  return jsonb_build_object('success', true, 'withdrawn', p_withdrawn);
end $$;

-- ---------- مشاريع الجولة للمحكّم ----------
create or replace function public.judge_projects(p_round_id uuid)
returns table (team_id uuid, team_name text, team_code text, track_id uuid, track_name text,
               project_title text, project_description text, project_file_url text,
               is_assigned boolean, has_conflict boolean, committee_name text, judging_order int,
               withdrawn boolean, approved boolean, members jsonb, deliverables jsonb)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.has_role('judge') or public.has_role('admin') or public.has_role('coordinator')) then
    raise exception 'غير مخوّل';
  end if;
  return query
  select t.id, t.team_name, t.team_code, t.track_id, tr.name_ar,
         sub.title, sub.description, sub.file_url,
         (my.team_id is not null), coalesce(my.has_conflict, false),
         (select c.name_ar from public.judge_assignments a join public.judging_committees c on c.id = a.committee_id
           where a.team_id = t.id and a.round_id = p_round_id and a.committee_id is not null limit 1),
         (select min(a.judging_order) from public.judge_assignments a where a.team_id = t.id and a.round_id = p_round_id)::int,
         exists (select 1 from public.judging_withdrawals w where w.team_id = t.id and w.round_id = p_round_id),
         exists (select 1 from public.judging_approvals ap where ap.team_id = t.id and ap.round_id = p_round_id and ap.status = 'approved'),
         coalesce((select jsonb_agg(jsonb_build_object('name', p.full_name, 'is_leader', tm.is_leader) order by tm.is_leader desc, p.full_name)
                   from public.team_members tm join public.profiles p on p.id = tm.user_id where tm.team_id = t.id), '[]'::jsonb),
         coalesce((select jsonb_agg(jsonb_build_object('title', d.title, 'file_name', ds.file_name, 'file_url', ds.file_url,
                                                       'submitted_at', ds.submitted_at) order by d.sort_order, d.title)
                   from public.deliverable_submissions ds join public.deliverables d on d.id = ds.deliverable_id
                   where ds.team_id = t.id), '[]'::jsonb)
  from public.teams t
  left join public.tracks tr on tr.id = t.track_id
  left join lateral (select s.title, s.description, s.file_url from public.submissions s
                     where s.team_id = t.id order by s.is_final desc, s.version desc nulls last limit 1) sub on true
  left join lateral (select a.team_id, a.has_conflict from public.judge_assignments a
                     where a.team_id = t.id and a.round_id = p_round_id and a.judge_user_id = auth.uid() limit 1) my on true
  where t.status = 'confirmed'
    and exists (select 1 from public.judge_assignments a where a.team_id = t.id and a.round_id = p_round_id)
  order by (my.team_id is null), tr.name_ar, t.team_name;
end $$;

-- ---------- استبدال محكّم عبر اللجنة ----------
create or replace function public.reassign_judge(p_old_judge_id uuid, p_new_judge_id uuid, p_round_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_com uuid; v_moved int := 0; v_kept int := 0; v_n int;
begin
  if not (public.has_role('admin') or public.has_role('coordinator')) then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل');
  end if;
  if p_old_judge_id = p_new_judge_id then
    return jsonb_build_object('success', false, 'error', 'اختر محكّمًا مختلفًا');
  end if;
  if not public.user_has_role(p_new_judge_id, 'judge') then
    return jsonb_build_object('success', false, 'error', 'البديل ليس محكّمًا');
  end if;

  select count(distinct team_id) into v_kept from public.judge_assignments a
  where a.judge_user_id = p_old_judge_id and a.round_id = p_round_id
    and public.assignment_has_scores(p_old_judge_id, a.team_id, p_round_id);

  -- 1) اللجان: البديل يحلّ محلّ الأصلي في عضوية كل لجنة له بمشاريع هذه الجولة
  for v_com in select distinct cm.committee_id from public.committee_members cm
               where cm.judge_user_id = p_old_judge_id
                 and exists (select 1 from public.judge_assignments a where a.committee_id = cm.committee_id and a.round_id = p_round_id)
  loop
    select count(distinct a.team_id) into v_n from public.judge_assignments a
    where a.committee_id = v_com and a.round_id = p_round_id and a.judge_user_id = p_old_judge_id
      and not public.assignment_has_scores(p_old_judge_id, a.team_id, p_round_id);
    v_moved := v_moved + v_n;
    delete from public.committee_members where committee_id = v_com and judge_user_id = p_old_judge_id;
    insert into public.committee_members (committee_id, judge_user_id) values (v_com, p_new_judge_id)
    on conflict do nothing;
    -- ما قيّمه الأصلي يبقى له: لا يُضاف البديل عليه (منعًا لمحكّم زائد)
    delete from public.judge_assignments a
    where a.judge_user_id = p_new_judge_id and a.committee_id = v_com and a.round_id = p_round_id
      and public.assignment_has_scores(p_old_judge_id, a.team_id, p_round_id)
      and not public.assignment_has_scores(p_new_judge_id, a.team_id, p_round_id);
  end loop;

  -- 2) إسنادات بلا لجنة: تُنقل غير المقيَّمة فقط
  with moved as (
    delete from public.judge_assignments a
    where a.judge_user_id = p_old_judge_id and a.round_id = p_round_id and a.committee_id is null
      and not public.assignment_has_scores(p_old_judge_id, a.team_id, p_round_id)
    returning a.team_id, a.judging_order
  )
  insert into public.judge_assignments (judge_user_id, team_id, round_id, judging_order)
  select p_new_judge_id, m.team_id, p_round_id, m.judging_order from moved m
  on conflict (judge_user_id, team_id, round_id) do nothing;
  get diagnostics v_n = row_count;
  v_moved := v_moved + v_n;

  -- 3) ترتيب العرض يُنسخ من ترتيب المشروع في لجنته
  update public.judge_assignments a set judging_order = x.ord
  from (select team_id, min(judging_order) ord from public.judge_assignments
        where round_id = p_round_id and judging_order is not null group by team_id) x
  where a.judge_user_id = p_new_judge_id and a.round_id = p_round_id and a.team_id = x.team_id
    and a.judging_order is distinct from x.ord;

  return jsonb_build_object('success', true, 'reassigned_count', v_moved, 'kept_count', v_kept);
end $$;

revoke execute on function public.save_evaluation(uuid, uuid, jsonb, text, boolean) from public, anon;
revoke execute on function public.set_round_lock(uuid, boolean) from public, anon;
revoke execute on function public.set_team_withdrawal(uuid, uuid, boolean, text) from public, anon;
revoke execute on function public.judge_projects(uuid) from public, anon;
grant execute on function public.save_evaluation(uuid, uuid, jsonb, text, boolean) to authenticated;
grant execute on function public.set_round_lock(uuid, boolean) to authenticated;
grant execute on function public.set_team_withdrawal(uuid, uuid, boolean, text) to authenticated;
grant execute on function public.judge_projects(uuid) to authenticated;
