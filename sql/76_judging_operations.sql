-- ============================================================
-- 76) عمليات التحكيم والنتائج (منقولة من ابتكار إنفاذ)
--   تكوين اللجان، الإسناد للجنة، التوزيع الآلي، ترتيب العرض،
--   حذف تقييم مع الأرشفة، الترتيب النهائي، إعلان النتائج، الحفل.
--   تعديل واحد عن إنفاذ: المشروع يُؤخذ من آخر نسخة مقدَّمة
--   (لا يُشترط is_final)، وعرض my_judging_position مقصور على الفريق والإدارة.
-- ============================================================

insert into public.platform_settings (key, value) values
  ('rankings_published', 'false'), ('winners_round_id', '')
on conflict (key) do nothing;

-- ---------- إسناد لجنة لمشروع ----------
create or replace function public.assign_committee_to_team(p_committee_id uuid, p_team_id uuid, p_round_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_existing uuid; v_existing_n text; v_scored boolean; v_team text; v_added int := 0; r record;
begin
  if not (public.has_role('admin') or public.has_role('coordinator')) then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل');
  end if;
  select team_name into v_team from public.teams where id = p_team_id;

  select distinct a.committee_id into v_existing from public.judge_assignments a
  where a.team_id = p_team_id and a.round_id = p_round_id
    and a.committee_id is not null and a.committee_id <> p_committee_id
  limit 1;

  if v_existing is not null then
    select exists (select 1 from public.scores s where s.team_id = p_team_id and s.round_id = p_round_id) into v_scored;
    select name_ar into v_existing_n from public.judging_committees where id = v_existing;
    if v_scored then
      return jsonb_build_object('success', false,
        'error', 'فريق «' || coalesce(v_team, '؟') || '» تحكّمه ' || coalesce(v_existing_n, 'لجنة أخرى')
                 || ' وبدأ التقييم فعلًا — لا يمكن تغيير اللجنة',
        'team', v_team, 'current_committee', v_existing_n);
    end if;
    delete from public.judge_assignments
    where team_id = p_team_id and round_id = p_round_id and committee_id = v_existing;
  end if;

  for r in select cm.judge_user_id from public.committee_members cm where cm.committee_id = p_committee_id loop
    insert into public.judge_assignments (judge_user_id, team_id, round_id, committee_id, has_conflict, conflict_reason)
    select r.judge_user_id, p_team_id, p_round_id, p_committee_id, coalesce(c.has_conflict, false),
           case when c.has_conflict then 'الجهة نفسها' end
    from (select exists (
            select 1 from public.profiles jp
            join public.team_members tm on tm.team_id = p_team_id
            join public.profiles pp on pp.id = tm.user_id
            where jp.id = r.judge_user_id and jp.organization is not null
              and nullif(btrim(jp.organization), '') = nullif(btrim(pp.organization), '')) as has_conflict) c
    on conflict (judge_user_id, team_id, round_id) do update set committee_id = excluded.committee_id;
    v_added := v_added + 1;
  end loop;

  return jsonb_build_object('success', true, 'judges_assigned', v_added, 'replaced', v_existing is not null);
end;
$$;

-- ---------- تكوين اللجان آليًا ----------
create or replace function public.auto_form_committees(p_size integer default 3, p_per_track boolean default false, p_clear_existing boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_track record; v_judges uuid[]; v_count int; v_n int; v_i int; v_j int; v_cid uuid;
        v_committees int := 0; v_placed int := 0;
begin
  if not (public.has_role('admin') or public.has_role('coordinator')) then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل');
  end if;
  if p_size < 1 then return jsonb_build_object('success', false, 'error', 'حجم اللجنة واحد فأكثر'); end if;

  if p_clear_existing then
    delete from public.judging_committees c
    where not exists (select 1 from public.judge_assignments a where a.committee_id = c.id);
  end if;

  if not p_per_track then
    select array_agg(p.id order by p.full_name) into v_judges
    from public.profiles p
    join public.user_roles ur on ur.user_id = p.id
    join public.roles r on r.id = ur.role_id and r.key = 'judge'
    where coalesce(p.is_active, true)
      and not exists (select 1 from public.committee_members cm where cm.judge_user_id = p.id);
    if v_judges is null then return jsonb_build_object('success', false, 'error', 'لا محكّمين بلا لجنة'); end if;

    v_count := array_length(v_judges, 1);
    v_n := greatest(1, v_count / p_size);
    for v_i in 1..v_n loop
      insert into public.judging_committees (name_ar, track_id, created_by)
      values ('لجنة ' || v_i, null, auth.uid()) returning id into v_cid;
      v_committees := v_committees + 1;
      for v_j in 0..(v_count - 1) loop
        if (v_j % v_n) + 1 = v_i then
          insert into public.committee_members (committee_id, judge_user_id)
          values (v_cid, v_judges[v_j + 1]) on conflict (judge_user_id) do nothing;
          v_placed := v_placed + 1;
        end if;
      end loop;
    end loop;
    return jsonb_build_object('success', true, 'committees_created', v_committees, 'judges_placed', v_placed);
  end if;

  for v_track in select t.id, t.name_ar from public.tracks t where t.is_active order by t.display_order loop
    select array_agg(x.id order by x.fit desc, x.full_name) into v_judges
    from (select p.id, p.full_name, public.judge_track_score(p.id, v_track.id) as fit
          from public.profiles p
          join public.user_roles ur on ur.user_id = p.id
          join public.roles r on r.id = ur.role_id and r.key = 'judge'
          where coalesce(p.is_active, true)
            and not exists (select 1 from public.committee_members cm where cm.judge_user_id = p.id)
            and public.judge_track_score(p.id, v_track.id) >= coalesce((
                  select max(public.judge_track_score(p.id, t2.id)) from public.tracks t2 where t2.is_active), 0)) x;
    if v_judges is null then continue; end if;
    v_count := array_length(v_judges, 1);
    if v_count = 0 then continue; end if;
    v_n := greatest(1, v_count / p_size);
    for v_i in 1..v_n loop
      insert into public.judging_committees (name_ar, track_id, created_by)
      values (v_track.name_ar || ' — لجنة ' || v_i, v_track.id, auth.uid()) returning id into v_cid;
      v_committees := v_committees + 1;
      for v_j in 0..(v_count - 1) loop
        if (v_j % v_n) + 1 = v_i then
          insert into public.committee_members (committee_id, judge_user_id)
          values (v_cid, v_judges[v_j + 1]) on conflict (judge_user_id) do nothing;
          v_placed := v_placed + 1;
        end if;
      end loop;
    end loop;
  end loop;

  select array_agg(p.id order by p.full_name) into v_judges
  from public.profiles p
  join public.user_roles ur on ur.user_id = p.id
  join public.roles r on r.id = ur.role_id and r.key = 'judge'
  where coalesce(p.is_active, true)
    and not exists (select 1 from public.committee_members cm where cm.judge_user_id = p.id);
  if v_judges is not null and array_length(v_judges, 1) > 0 then
    insert into public.judging_committees (name_ar, track_id, created_by)
    values ('لجنة عامة', null, auth.uid()) returning id into v_cid;
    v_committees := v_committees + 1;
    for v_j in 1..array_length(v_judges, 1) loop
      insert into public.committee_members (committee_id, judge_user_id)
      values (v_cid, v_judges[v_j]) on conflict (judge_user_id) do nothing;
      v_placed := v_placed + 1;
    end loop;
  end if;

  return jsonb_build_object('success', true, 'committees_created', v_committees, 'judges_placed', v_placed);
end;
$$;

-- ---------- توزيع المشاريع على اللجان بالتساوي ----------
create or replace function public.auto_assign_projects(p_round_id uuid, p_replace boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_track record; v_coms uuid[]; v_teams uuid[]; v_general boolean; v_i int; v_pick uuid;
        v_gcount int := 0; v_assigned int := 0; v_skipped int := 0; v_load jsonb := '{}'::jsonb;
begin
  if not (public.has_role('admin') or public.has_role('coordinator')) then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل');
  end if;
  if p_round_id is null then return jsonb_build_object('success', false, 'error', 'الجولة مطلوبة'); end if;

  if not p_replace then
    select coalesce(jsonb_object_agg(c.id::text, cnt), '{}'::jsonb) into v_load
    from public.judging_committees c
    left join lateral (select count(distinct a.team_id) as cnt from public.judge_assignments a
                       where a.committee_id = c.id and a.round_id = p_round_id) x on true;
  end if;

  for v_track in select t.id, t.name_ar from public.tracks t where t.is_active order by t.display_order loop
    select array_agg(c.id order by c.name_ar) into v_coms from public.judging_committees c
    where c.is_active and c.track_id = v_track.id
      and exists (select 1 from public.committee_members m where m.committee_id = c.id);
    v_general := false;
    if v_coms is null then
      select array_agg(c.id order by c.name_ar) into v_coms from public.judging_committees c
      where c.is_active and c.track_id is null
        and exists (select 1 from public.committee_members m where m.committee_id = c.id);
      v_general := true;
    end if;
    if v_coms is null then continue; end if;

    select array_agg(t.id order by t.team_name) into v_teams from public.teams t
    where t.status = 'confirmed' and t.track_id = v_track.id
      and exists (select 1 from public.submissions s where s.team_id = t.id);
    if v_teams is null then continue; end if;

    for v_i in 1..array_length(v_teams, 1) loop
      if exists (select 1 from public.scores s where s.team_id = v_teams[v_i] and s.round_id = p_round_id) then
        v_skipped := v_skipped + 1; continue;
      end if;
      if p_replace then
        delete from public.judge_assignments a where a.team_id = v_teams[v_i] and a.round_id = p_round_id;
      elsif exists (select 1 from public.judge_assignments a where a.team_id = v_teams[v_i] and a.round_id = p_round_id) then
        continue;
      end if;

      select c into v_pick from unnest(v_coms) as c
      order by coalesce((v_load ->> c::text)::int, 0),
               ((v_gcount + array_position(v_coms, c)) % array_length(v_coms, 1))
      limit 1;

      perform public.assign_committee_to_team(v_pick, v_teams[v_i], p_round_id);
      v_load := jsonb_set(v_load, array[v_pick::text], to_jsonb(coalesce((v_load ->> v_pick::text)::int, 0) + 1));
      v_assigned := v_assigned + 1;
      if v_general then v_gcount := v_gcount + 1; end if;
    end loop;
  end loop;

  return jsonb_build_object('success', true, 'projects_assigned', v_assigned, 'skipped_scored', v_skipped, 'load', v_load);
end;
$$;

create or replace function public.auto_distribute_committees(p_round_id uuid, p_track_id uuid default null, p_replace boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_committees uuid[]; v_teams uuid[]; v_i int := 1; v_team uuid; v_total int := 0;
begin
  if not (public.has_role('admin') or public.has_role('coordinator')) then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل');
  end if;
  select array_agg(c.id order by c.name_ar) into v_committees from public.judging_committees c
  where c.is_active and (p_track_id is null or c.track_id = p_track_id or c.track_id is null);
  if v_committees is null or array_length(v_committees, 1) = 0 then
    return jsonb_build_object('success', false, 'error', 'لا لجان مفعّلة');
  end if;
  select array_agg(t.id order by t.team_name) into v_teams from public.teams t
  where t.status = 'confirmed' and (p_track_id is null or t.track_id = p_track_id)
    and exists (select 1 from public.submissions s where s.team_id = t.id);
  if v_teams is null or array_length(v_teams, 1) = 0 then
    return jsonb_build_object('success', false, 'error', 'لا مشاريع مقدَّمة');
  end if;
  if p_replace then
    delete from public.judge_assignments a
    where a.round_id = p_round_id and a.team_id = any(v_teams)
      and not exists (select 1 from public.scores s where s.team_id = a.team_id and s.round_id = a.round_id);
  end if;
  foreach v_team in array v_teams loop
    perform public.assign_committee_to_team(v_committees[((v_i - 1) % array_length(v_committees, 1)) + 1], v_team, p_round_id);
    v_i := v_i + 1; v_total := v_total + 1;
  end loop;
  return jsonb_build_object('success', true, 'teams', v_total, 'committees', array_length(v_committees, 1));
end;
$$;

-- ---------- إسناد المحكّمين فرديًا (دون لجان) بالتساوي ----------
create or replace function public.auto_assign_judges(p_round_id uuid, p_judges_per_team integer default 3, p_dry_run boolean default true)
returns table("الفريق" text, "المحكّم" text, "الحالة" text)
language plpgsql security definer set search_path = public as $$
declare v_ids uuid[] := '{}'; v_names text[] := '{}'; v_orgs text[] := '{}'; v_load int[] := '{}';
        v_team record; v_needed int; v_best int; v_k int; v_reason text; v_taken uuid[];
begin
  if auth.uid() is null then
    return query select 'خطأ'::text, 'لا توجد جلسة مستخدم — شغّل هذه العملية من لوحة التحكم'::text, '🔴'::text; return;
  end if;
  if not (public.has_role('admin') or public.has_role('coordinator')) then
    return query select 'خطأ'::text, 'هذا الحساب ليس إداريًا ولا منسّقًا'::text, '🔴'::text; return;
  end if;
  if p_judges_per_team < 1 or p_judges_per_team > 10 then
    return query select 'خطأ'::text, 'عدد المحكّمين يجب أن يكون بين 1 و10'::text, '🔴'::text; return;
  end if;
  if not exists (select 1 from public.judging_rounds where id = p_round_id) then
    return query select 'خطأ'::text, 'الجولة غير موجودة'::text, '🔴'::text; return;
  end if;

  select array_agg(x.id order by x.id), array_agg(x.full_name order by x.id),
         array_agg(coalesce(lower(btrim(x.organization)), '') order by x.id), array_agg(x.cur order by x.id)
    into v_ids, v_names, v_orgs, v_load
  from (select distinct p.id, p.full_name, p.organization,
               (select count(*)::int from public.judge_assignments ja
                where ja.judge_user_id = p.id and ja.round_id = p_round_id) as cur
        from public.profiles p
        join public.user_roles ur on ur.user_id = p.id
        join public.roles r on r.id = ur.role_id
        where r.key = 'judge' and coalesce(p.is_active, true)) x;

  if v_ids is null or array_length(v_ids, 1) is null then
    return query select 'خطأ'::text, 'لا يوجد محكّمون نشطون — أضفهم من تبويب إدارة المحكّمين'::text, '🔴'::text; return;
  end if;

  for v_team in
    select t.id, t.team_name,
           coalesce(array_agg(distinct lower(btrim(pm.organization)))
             filter (where pm.organization is not null and btrim(pm.organization) <> ''), '{}') as orgs
    from public.teams t
    join public.team_members tm on tm.team_id = t.id
    join public.profiles pm on pm.id = tm.user_id
    where t.status = 'confirmed'
    group by t.id, t.team_name order by t.team_name
  loop
    select coalesce(array_agg(ja.judge_user_id), '{}') into v_taken from public.judge_assignments ja
    where ja.team_id = v_team.id and ja.round_id = p_round_id;
    v_needed := p_judges_per_team - coalesce(array_length(v_taken, 1), 0);
    while v_needed > 0 loop
      v_best := null;
      for v_k in 1 .. array_length(v_ids, 1) loop
        if not (v_ids[v_k] = any(v_taken)) then
          if v_best is null or v_load[v_k] < v_load[v_best] then v_best := v_k; end if;
        end if;
      end loop;
      exit when v_best is null;
      v_reason := case when v_orgs[v_best] <> '' and v_orgs[v_best] = any(v_team.orgs)
                       then 'المحكّم من جهة أحد أعضاء الفريق' end;
      if not p_dry_run then
        insert into public.judge_assignments (judge_user_id, team_id, round_id, has_conflict, conflict_reason)
        values (v_ids[v_best], v_team.id, p_round_id, v_reason is not null, v_reason)
        on conflict (judge_user_id, team_id, round_id) do nothing;
      end if;
      v_load[v_best] := v_load[v_best] + 1;
      v_taken := array_append(v_taken, v_ids[v_best]);
      return query select v_team.team_name, v_names[v_best],
        case when v_reason is not null then '⚠️ ' || v_reason when p_dry_run then 'معاينة' else 'أُسند' end;
      v_needed := v_needed - 1;
    end loop;
  end loop;
  return;
end;
$$;

-- ---------- ترتيب العرض داخل اللجنة ----------
create or replace function public.renumber_committee_order(p_committee_id uuid default null, p_round_id uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_updated int := 0;
begin
  if not (public.has_role('admin') or public.has_role('coordinator')) then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل');
  end if;
  with teams_ordered as (
    select distinct on (a.committee_id, a.round_id, a.team_id) a.committee_id, a.round_id, a.team_id, t.team_code, t.team_name
    from public.judge_assignments a join public.teams t on t.id = a.team_id
    where a.committee_id is not null
      and (p_committee_id is null or a.committee_id = p_committee_id)
      and (p_round_id is null or a.round_id = p_round_id)
  ), ordered as (
    select committee_id, round_id, team_id,
           row_number() over (partition by committee_id, round_id
             order by nullif(regexp_replace(coalesce(team_code,''), '\D', '', 'g'), '')::bigint nulls last,
                      team_code, team_name) as rn
    from teams_ordered
  )
  update public.judge_assignments a set judging_order = o.rn
  from ordered o
  where a.committee_id = o.committee_id and a.round_id = o.round_id and a.team_id = o.team_id
    and a.judging_order is distinct from o.rn;
  get diagnostics v_updated = row_count;
  return jsonb_build_object('success', true, 'updated', v_updated);
end;
$$;

create or replace function public.set_judging_order(p_team_id uuid, p_round_id uuid, p_new_pos integer)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_com uuid; v_old int; v_max int;
begin
  if not (public.has_role('admin') or public.has_role('coordinator')) then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل');
  end if;
  select committee_id, judging_order into v_com, v_old from public.judge_assignments
  where team_id = p_team_id and round_id = p_round_id and committee_id is not null limit 1;
  if v_com is null then return jsonb_build_object('success', false, 'error', 'المشروع غير مسنَد للجنة'); end if;
  select count(distinct team_id) into v_max from public.judge_assignments where committee_id = v_com and round_id = p_round_id;
  if p_new_pos < 1 or p_new_pos > v_max then
    return jsonb_build_object('success', false, 'error', format('الترتيب يجب أن يكون بين 1 و %s', v_max));
  end if;
  if v_old = p_new_pos then return jsonb_build_object('success', true, 'unchanged', true); end if;
  if p_new_pos < v_old then
    update public.judge_assignments set judging_order = judging_order + 1
    where committee_id = v_com and round_id = p_round_id and judging_order >= p_new_pos and judging_order < v_old;
  else
    update public.judge_assignments set judging_order = judging_order - 1
    where committee_id = v_com and round_id = p_round_id and judging_order > v_old and judging_order <= p_new_pos;
  end if;
  update public.judge_assignments set judging_order = p_new_pos where team_id = p_team_id and round_id = p_round_id;
  return jsonb_build_object('success', true, 'from', v_old, 'to', p_new_pos);
end;
$$;

create or replace function public.sync_committee_assignments(p_committee_id uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_removed int := 0; v_added int := 0; r record;
begin
  if auth.uid() is not null and not (public.has_role('admin') or public.has_role('coordinator')) then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل');
  end if;
  delete from public.judge_assignments a
  where (p_committee_id is null or a.committee_id = p_committee_id) and a.committee_id is not null
    and not exists (select 1 from public.committee_members cm
                    where cm.judge_user_id = a.judge_user_id and cm.committee_id = a.committee_id)
    and not public.assignment_has_scores(a.judge_user_id, a.team_id, a.round_id);
  get diagnostics v_removed = row_count;
  for r in
    select distinct cm.judge_user_id, a.team_id, a.round_id, a.committee_id
    from public.committee_members cm join public.judge_assignments a on a.committee_id = cm.committee_id
    where (p_committee_id is null or cm.committee_id = p_committee_id)
      and not exists (select 1 from public.judge_assignments x
                      where x.judge_user_id = cm.judge_user_id and x.team_id = a.team_id and x.round_id = a.round_id)
  loop
    begin
      insert into public.judge_assignments (judge_user_id, team_id, round_id, committee_id)
      values (r.judge_user_id, r.team_id, r.round_id, r.committee_id);
      v_added := v_added + 1;
    exception when others then null;
    end;
  end loop;
  return jsonb_build_object('removed', v_removed, 'added', v_added);
end;
$$;

-- ---------- حذف تقييم محكّم مع الأرشفة ----------
create or replace function public.admin_delete_judge_evaluation(p_judge_id uuid, p_team_id uuid, p_round_id uuid, p_reason text)
returns json language plpgsql security definer set search_path = public as $$
declare v_count int;
begin
  if not (public.has_role('admin') or public.has_role('coordinator')) then
    return json_build_object('success', false, 'error', 'صلاحية غير كافية');
  end if;
  if p_reason is null or btrim(p_reason) = '' then
    return json_build_object('success', false, 'error', 'سبب الحذف إلزامي');
  end if;
  insert into public.scores_deleted_archive
    (original_id, judge_user_id, team_id, round_id, criteria_id, score, comments, submitted_at, deleted_by, deletion_reason)
  select s.id, s.judge_user_id, s.team_id, s.round_id, s.criteria_id, s.score, s.comments, s.submitted_at, auth.uid(), btrim(p_reason)
  from public.scores s where s.judge_user_id = p_judge_id and s.team_id = p_team_id and s.round_id = p_round_id;
  get diagnostics v_count = row_count;
  if v_count = 0 then
    return json_build_object('success', false, 'error', 'لا توجد درجات لهذا المحكّم على هذا الفريق');
  end if;
  delete from public.scores where judge_user_id = p_judge_id and team_id = p_team_id and round_id = p_round_id;
  return json_build_object('success', true, 'deleted_count', v_count);
end;
$$;

-- ---------- العروض ----------
create or replace view public.final_rankings with (security_invoker = on) as
with judge_avg as (
  select s.team_id, s.round_id, s.judge_user_id,
         sum(s.score * jc.weight) / nullif(sum(jc.weight), 0) as avg_score,
         count(*) as criteria_scored
  from public.scores s join public.judging_criteria jc on jc.id = s.criteria_id
  group by s.team_id, s.round_id, s.judge_user_id
), team_agg as (
  select ja.team_id, ja.round_id,
         round(avg(ja.avg_score), 3) as final_score,
         count(*) as judges_count,
         round(coalesce(max(ja.avg_score) - min(ja.avg_score), 0), 2) as spread,
         bool_or(ja.criteria_scored < (select count(*) from public.judging_criteria c where c.round_id = ja.round_id)) as has_partial
  from judge_avg ja group by ja.team_id, ja.round_id
)
select t.id as team_id, t.team_name, t.track_id, tr.name_ar as track_name,
       jr.id as round_id, jr.name_ar as round_name, jr.round_order,
       sub.title as project_title,
       ta.final_score, ta.judges_count, ta.spread, ta.has_partial,
       app.status as approval_status, app.approved_at,
       case when app.status = 'approved' then rank() over (partition by jr.id, t.track_id order by ta.final_score desc nulls last, ta.spread) end as rank_in_track,
       case when app.status = 'approved' then rank() over (partition by jr.id order by ta.final_score desc nulls last, ta.spread) end as rank_overall
from team_agg ta
join public.teams t on t.id = ta.team_id
join public.judging_rounds jr on jr.id = ta.round_id
left join public.tracks tr on tr.id = t.track_id
left join lateral (select s.title, s.description from public.submissions s where s.team_id = t.id
                   order by s.is_final desc, s.version desc nulls last limit 1) sub on true
left join public.judging_approvals app on app.team_id = ta.team_id and app.round_id = ta.round_id
where t.status = 'confirmed';

create or replace view public.judging_summary with (security_invoker = on) as
with judge_avg as (
  select s.team_id, s.round_id, s.judge_user_id,
         sum(s.score * jc.weight) / nullif(sum(jc.weight), 0) as judge_average
  from public.scores s join public.judging_criteria jc on jc.id = s.criteria_id
  group by s.team_id, s.round_id, s.judge_user_id
), assigned as (
  select team_id, round_id, count(*) filter (where has_conflict = false) as assigned_count
  from public.judge_assignments group by team_id, round_id
)
select t.id as team_id, jr.id as round_id, t.team_name, tr.name_ar as track_name, jr.name_ar as round_name, jr.round_order,
       coalesce(a.assigned_count, 0) as assigned_judges,
       count(ja.judge_user_id) as submitted_judges,
       round(avg(ja.judge_average), 2) as weighted_average,
       round(max(ja.judge_average) - min(ja.judge_average), 2) as judges_spread,
       app.status as approval_status, app.approved_at, app.note as approval_note
from public.teams t
join public.tracks tr on tr.id = t.track_id
cross join public.judging_rounds jr
left join judge_avg ja on ja.team_id = t.id and ja.round_id = jr.id
left join assigned a on a.team_id = t.id and a.round_id = jr.id
left join public.judging_approvals app on app.team_id = t.id and app.round_id = jr.id
group by t.id, jr.id, t.team_name, tr.name_ar, jr.name_ar, jr.round_order, a.assigned_count, app.status, app.approved_at, app.note
having coalesce(a.assigned_count, 0) > 0 or count(ja.judge_user_id) > 0;

create or replace view public.judging_progress with (security_invoker = on) as
select t.id as team_id, t.team_name as "الفريق", t.team_code as "رمز_الفريق", tr.name_ar as "المسار",
       sub.title as "المشروع", r.name_ar as "الجولة", r.id as round_id,
       (select min(a2.judging_order) from public.judge_assignments a2 where a2.team_id = t.id and a2.round_id = r.id) as "الترتيب",
       (select string_agg(distinct c.name_ar, ' · ') from public.judge_assignments a2
          join public.judging_committees c on c.id = a2.committee_id
        where a2.team_id = t.id and a2.round_id = r.id) as "اللجنة",
       (select count(distinct a2.judge_user_id) from public.judge_assignments a2 where a2.team_id = t.id and a2.round_id = r.id) as "محكّمون_مسنَدون",
       (select count(distinct s2.judge_user_id) from public.scores s2 where s2.team_id = t.id and s2.round_id = r.id) as "محكّمون_قيّموا",
       case
         when (select count(*) from public.judge_assignments a3 where a3.team_id = t.id and a3.round_id = r.id) = 0 then 'لم يُسنَد'
         when (select count(distinct s3.judge_user_id) from public.scores s3 where s3.team_id = t.id and s3.round_id = r.id) = 0 then 'لم يبدأ'
         when (select count(distinct s4.judge_user_id) from public.scores s4 where s4.team_id = t.id and s4.round_id = r.id)
            < (select count(distinct a4.judge_user_id) from public.judge_assignments a4 where a4.team_id = t.id and a4.round_id = r.id) then 'جزئي'
         else 'مكتمل' end as "الحالة",
       (select round(avg(s5.score), 2) from public.scores s5 where s5.team_id = t.id and s5.round_id = r.id) as "متوسط_الدرجة",
       (select bool_or(a5.has_conflict) from public.judge_assignments a5 where a5.team_id = t.id and a5.round_id = r.id) as "فيه_تعارض"
from public.teams t
left join public.tracks tr on tr.id = t.track_id
left join lateral (select s.title from public.submissions s where s.team_id = t.id order by s.version desc nulls last limit 1) sub on true
cross join public.judging_rounds r
where t.status = 'confirmed' and r.is_active;

create or replace view public.judge_workload with (security_invoker = on) as
select p.id as judge_id, p.full_name as judge_name, p.email, p.specialization, p.organization,
       coalesce(p.is_active, true) as is_active,
       jr.id as round_id, jr.name_ar as round_name, jr.is_active as round_active,
       x.assigned as assigned_teams, x.scored as scored_teams, x.conflicts as conflict_teams,
       case when x.assigned = 0 then 0 else round(x.scored::numeric / x.assigned * 100) end as progress_pct,
       (select round(avg(s.score), 2) from public.scores s where s.judge_user_id = p.id and s.round_id = jr.id) as avg_score,
       (select max(s.submitted_at) from public.scores s where s.judge_user_id = p.id and s.round_id = jr.id) as last_activity,
       p.full_name as "المحكّم", p.organization as "الجهة",
       (select string_agg(distinct c.name_ar, ' · ') from public.committee_members cm
          join public.judging_committees c on c.id = cm.committee_id where cm.judge_user_id = p.id) as "اللجان",
       x.assigned as "مشاريع_مسنَدة", x.scored as "مشاريع_قيّمها",
       greatest(x.assigned - x.scored, 0) as "متبقية", x.conflicts as "حالات_تعارض",
       case when x.assigned = 0 then 'بلا إسناد' when x.scored = 0 then 'لم يبدأ'
            when x.scored < x.assigned then 'جارٍ' else 'أنهى' end as "الحالة"
from public.profiles p
join public.user_roles ur on ur.user_id = p.id
join public.roles r on r.id = ur.role_id and r.key = 'judge'
cross join public.judging_rounds jr
cross join lateral (
  select (select count(distinct a.team_id) from public.judge_assignments a where a.judge_user_id = p.id and a.round_id = jr.id) as assigned,
         (select count(distinct s.team_id) from public.scores s where s.judge_user_id = p.id and s.round_id = jr.id) as scored,
         (select count(*) filter (where a.has_conflict) from public.judge_assignments a where a.judge_user_id = p.id and a.round_id = jr.id) as conflicts
) x;

create or replace view public.judge_track_fit with (security_invoker = on) as
select p.id as judge_id, p.full_name as "المحكّم", p.specialization as "التخصص",
       t.id as track_id, t.name_ar as "المسار", public.judge_track_score(p.id, t.id) as "الملاءمة"
from public.profiles p
join public.user_roles ur on ur.user_id = p.id
join public.roles r on r.id = ur.role_id and r.key = 'judge'
cross join public.tracks t
where coalesce(p.is_active, true) and t.is_active;

create or replace view public.results_export with (security_invoker = on) as
select jr.name_ar as "الجولة", t.team_name as "الفريق", tr.name_ar as "المسار", sub.title as "المشروع",
       pj.full_name as "المحكّم", jc.name_ar as "المعيار", jc.weight as "الوزن", jc.max_score as "الأقصى",
       s.score as "الدرجة", s.comments as "الملاحظات", s.submitted_at as "وقت_التقييم", app.status as "حالة_الاعتماد"
from public.scores s
join public.judging_rounds jr on jr.id = s.round_id
join public.teams t on t.id = s.team_id
left join public.tracks tr on tr.id = t.track_id
left join lateral (select x.title from public.submissions x where x.team_id = t.id order by x.version desc nulls last limit 1) sub on true
join public.profiles pj on pj.id = s.judge_user_id
join public.judging_criteria jc on jc.id = s.criteria_id
left join public.judging_approvals app on app.team_id = t.id and app.round_id = s.round_id;

-- موقع الفريق في طابور التحكيم: يراه أعضاء الفريق والإدارة فقط
create or replace view public.my_judging_position as
select a.team_id, a.round_id, c.name_ar as "اللجنة", min(a.judging_order) as "ترتيبي",
       (select count(distinct x.team_id) from public.judge_assignments x
        where x.committee_id = a.committee_id and x.round_id = a.round_id) as "إجمالي_اللجنة",
       case
         when (select count(distinct s.judge_user_id) from public.scores s where s.team_id = a.team_id and s.round_id = a.round_id)
            >= (select count(distinct y.judge_user_id) from public.judge_assignments y where y.team_id = a.team_id and y.round_id = a.round_id)
           then 'اكتمل التحكيم'
         when exists (select 1 from public.scores s where s.team_id = a.team_id and s.round_id = a.round_id) then 'قيد التحكيم'
         else 'بانتظار الدور' end as "الحالة"
from public.judge_assignments a
join public.judging_committees c on c.id = a.committee_id
join public.judging_rounds r on r.id = a.round_id
where a.committee_id is not null and r.is_active
  and (public.is_team_member(a.team_id) or public.has_role('admin') or public.has_role('coordinator'))
group by a.team_id, a.round_id, a.committee_id, c.name_ar;
revoke all on public.my_judging_position from anon;

revoke select on public.final_rankings, public.judging_summary, public.judging_progress,
  public.judge_workload, public.judge_track_fit, public.results_export from anon;

-- ---------- إعلان النتائج ----------
create or replace function public.publish_rankings(p_published boolean)
returns json language plpgsql security definer set search_path = public as $$
begin
  if not public.has_role('admin') then
    return json_build_object('success', false, 'error', 'إعلان النتائج للإداري وحده');
  end if;
  insert into public.platform_settings (key, value) values ('rankings_published', case when p_published then 'true' else 'false' end)
  on conflict (key) do update set value = excluded.value;
  return json_build_object('success', true, 'published', p_published);
end;
$$;

create or replace function public.get_public_rankings(p_round_id uuid default null)
returns table("المسار" text, "المركز" integer, "الفريق" text, "المشروع" text, "النتيجة" numeric, "عدد_المحكمين" integer)
language plpgsql security definer set search_path = public as $$
begin
  if coalesce((select value from public.platform_settings where key = 'rankings_published'), 'false') <> 'true' then return; end if;
  return query
  select fr.track_name, fr.rank_in_track::int, fr.team_name, coalesce(fr.project_title, '—'), fr.final_score, fr.judges_count::int
  from public.final_rankings fr
  where fr.approval_status = 'approved' and fr.rank_in_track is not null
    and (p_round_id is null or fr.round_id = p_round_id)
  order by fr.track_name, fr.rank_in_track;
end;
$$;

create or replace function public.get_winners()
returns table("المسار" text, "الفريق" text, "المشروع" text, "الوصف" text)
language plpgsql security definer set search_path = public as $$
declare v_round uuid;
begin
  if coalesce((select value from public.platform_settings where key = 'rankings_published'), 'false') <> 'true' then return; end if;
  select nullif(btrim(value), '')::uuid into v_round from public.platform_settings where key = 'winners_round_id';
  if v_round is null then
    select fr.round_id into v_round from public.final_rankings fr
    join public.judging_rounds jr on jr.id = fr.round_id
    where fr.approval_status = 'approved' order by jr.round_order desc limit 1;
  end if;
  if v_round is null then return; end if;
  return query
  select fr.track_name, fr.team_name, coalesce(fr.project_title, ''),
         coalesce(left((select s.description from public.submissions s where s.team_id = fr.team_id
                         order by s.is_final desc, s.version desc nulls last limit 1), 180), '')
  from public.final_rankings fr
  where fr.approval_status = 'approved' and fr.rank_in_track = 1 and fr.round_id = v_round
  order by fr.track_name;
exception when others then return;
end;
$$;

create or replace function public.get_ceremony_stats()
returns json language plpgsql security definer set search_path = public as $$
declare v json;
begin
  select json_build_object(
    'participants', (select count(distinct tm.user_id) from public.team_members tm
                     join public.teams t on t.id = tm.team_id where t.status = 'confirmed'),
    'projects', (select count(distinct team_id) from public.submissions),
    'tracks', (select count(*) from public.tracks where is_active),
    'mentorship_sessions', (select count(*) from public.mentor_bookings where status <> 'cancelled'),
    'mentors', (select count(*) from public.user_roles ur join public.roles r on r.id = ur.role_id where r.key = 'mentor'),
    'judges', (select count(*) from public.user_roles ur join public.roles r on r.id = ur.role_id where r.key = 'judge'),
    'teams', (select count(*) from public.teams where status = 'confirmed'),
    'mentorship_hours', (select coalesce(round(sum(extract(epoch from (s.end_time - s.start_time)) / 3600.0)), 0)
                         from public.mentor_bookings b join public.mentor_slots s on s.id = b.slot_id
                         where b.status <> 'cancelled'),
    'published', coalesce((select value from public.platform_settings where key = 'rankings_published'), 'false') = 'true'
  ) into v;
  return v;
end;
$$;

create or replace function public.get_live_stats()
returns json language plpgsql security definer set search_path = public as $$
declare v_teams int; v_participants int; v_tracks int; v_projects int; v_judges int;
        v_expected int; v_done int; v_published boolean;
begin
  select count(*) into v_teams from public.teams where status = 'confirmed';
  select count(distinct tm.user_id) into v_participants from public.team_members tm
    join public.teams t on t.id = tm.team_id where t.status = 'confirmed';
  select count(*) into v_tracks from public.tracks where is_active;
  select count(distinct s.team_id) into v_projects from public.submissions s
    join public.teams t on t.id = s.team_id where t.status = 'confirmed';
  select count(distinct p.id) into v_judges from public.profiles p
    join public.user_roles ur on ur.user_id = p.id join public.roles r on r.id = ur.role_id
    where r.key = 'judge' and coalesce(p.is_active, true);
  select count(*) into v_expected from public.judge_assignments;
  select count(*) into v_done from (select distinct judge_user_id, team_id, round_id from public.scores) x;
  select coalesce(value, 'false') = 'true' into v_published from public.platform_settings where key = 'rankings_published';
  return json_build_object(
    'teams', coalesce(v_teams, 0), 'participants', coalesce(v_participants, 0),
    'tracks', coalesce(v_tracks, 0), 'projects', coalesce(v_projects, 0), 'judges', coalesce(v_judges, 0),
    'judging_pct', case when coalesce(v_expected, 0) = 0 then null else round(v_done::numeric / v_expected * 100) end,
    'published', coalesce(v_published, false));
end;
$$;

-- صفحات النتائج والحفل عامة (أرقام إجمالية + الفائزون بعد الإعلان فقط)
grant execute on function public.get_public_rankings(uuid), public.get_winners(),
  public.get_ceremony_stats(), public.get_live_stats() to anon, authenticated;
-- عمليات الإدارة لا تُستدعى دون تسجيل دخول
revoke execute on function public.assign_committee_to_team(uuid, uuid, uuid), public.auto_form_committees(integer, boolean, boolean),
  public.auto_assign_projects(uuid, boolean), public.auto_distribute_committees(uuid, uuid, boolean),
  public.auto_assign_judges(uuid, integer, boolean), public.renumber_committee_order(uuid, uuid),
  public.set_judging_order(uuid, uuid, integer), public.sync_committee_assignments(uuid),
  public.admin_delete_judge_evaluation(uuid, uuid, uuid, text), public.publish_rankings(boolean) from anon;
