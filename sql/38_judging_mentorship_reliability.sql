-- ============================================================
-- نظام موثوقية وخلافة للإرشاد والتحكيم + حقول مهنية إضافية
-- ============================================================
-- يُطبّق بعد 37_unify_mentorship_judging_permissions.sql
-- ============================================================

-- ------------------------------------------------------------
-- 1. المسمى الوظيفي (يرفع مصداقية المرشد/المحكّم أمام الفرق)
-- ------------------------------------------------------------
alter table public.profiles add column if not exists current_position text;

-- ------------------------------------------------------------
-- 2. استبدال محكّم بالكامل (خلافة) — ينقل كل تعييناته لمحكّم آخر
--    بجولة معيّنة، ويعيد فحص تعارض المصالح تلقائيًا للمحكّم الجديد
-- ------------------------------------------------------------
create or replace function public.reassign_judge(
  p_old_judge_id uuid,
  p_new_judge_id uuid,
  p_round_id uuid
) returns jsonb as $$
declare
  v_team_id uuid;
  v_count int := 0;
begin
  if not (public.has_role('admin') or public.has_role('coordinator')) then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل');
  end if;

  for v_team_id in (
    select team_id from public.judge_assignments
    where judge_user_id = p_old_judge_id and round_id = p_round_id
  ) loop
    delete from public.judge_assignments
    where judge_user_id = p_old_judge_id and team_id = v_team_id and round_id = p_round_id;

    insert into public.judge_assignments (judge_user_id, team_id, round_id)
    values (p_new_judge_id, v_team_id, p_round_id)
    on conflict (judge_user_id, team_id, round_id) do nothing;

    v_count := v_count + 1;
  end loop;

  return jsonb_build_object('success', true, 'reassigned_count', v_count);
end;
$$ language plpgsql security definer set search_path = public;

-- ------------------------------------------------------------
-- 3. تعطيل مرشد مؤقتًا — يلغي كل مواعيده المستقبلية دفعة وحدة
--    (يُشعِر الفرق المتأثرة تلقائيًا عبر trigger الإلغاء الموجود أصلًا)
-- ------------------------------------------------------------
create or replace function public.cancel_mentor_future_bookings(p_mentor_id uuid)
returns jsonb as $$
declare
  v_count int;
begin
  if not (public.has_role('admin') or public.has_role('coordinator')) then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل');
  end if;

  update public.mentor_bookings mb
  set status = 'cancelled'
  from public.mentor_slots ms
  where mb.slot_id = ms.id
    and ms.mentor_user_id = p_mentor_id
    and ms.start_time > now()
    and mb.status not in ('cancelled','completed');

  get diagnostics v_count = row_count;
  return jsonb_build_object('success', true, 'cancelled_count', v_count);
end;
$$ language plpgsql security definer set search_path = public;

-- ------------------------------------------------------------
-- 4. منع تعديل الدرجات بعد نشر النتائج (موثوقية النتائج المعلنة)
-- ------------------------------------------------------------
create or replace function public.upsert_scores_guarded(
  p_round_id uuid,
  p_team_id uuid,
  p_rows jsonb
) returns jsonb as $$
declare
  v_published boolean;
  v_row jsonb;
begin
  select results_published into v_published from public.judging_rounds where id = p_round_id;
  if v_published then
    return jsonb_build_object('success', false, 'error', 'تم نشر النتائج بالفعل — التعديل مقفل الآن');
  end if;

  for v_row in select * from jsonb_array_elements(p_rows) loop
    insert into public.scores (judge_user_id, team_id, round_id, criteria_id, score, comments)
    values (
      auth.uid(), p_team_id, p_round_id,
      (v_row->>'criteria_id')::uuid,
      (v_row->>'score')::numeric,
      v_row->>'comments'
    )
    on conflict (judge_user_id, team_id, round_id, criteria_id)
    do update set score = excluded.score, comments = excluded.comments, submitted_at = now();
  end loop;

  return jsonb_build_object('success', true);
end;
$$ language plpgsql security definer set search_path = public;
