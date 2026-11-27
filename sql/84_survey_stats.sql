-- ============================================================
-- 84) إحصاءات الاستبيانات وتصدير الإجابات (منقولة من ابتكار إنفاذ)
--   تشديد: get_survey_stats مقصورة على الإدارة والمنسّق.
-- ============================================================
create or replace view public.survey_answers_flat with (security_invoker = on) as
select s.id as survey_id, s.title as "الاستبيان", s.target_stage as "المرحلة", r.id as response_id, r.user_id,
       p.full_name as "المشارك", q.value ->> 'id' as question_id,
       coalesce(q.value ->> 'text', q.value ->> 'label', q.value ->> 'q', q.value ->> 'question_ar') as "السؤال",
       coalesce(q.value ->> 'type', 'text') as "نوع_السؤال",
       r.answers_json ->> coalesce(q.value ->> 'id', '') as "الإجابة",
       r.nps_score as "درجة_التوصية", r.submitted_at as "وقت_الإجابة"
from public.surveys s
join public.survey_responses r on r.survey_id = s.id
left join public.profiles p on p.id = r.user_id
cross join lateral jsonb_array_elements(case jsonb_typeof(s.questions_json) when 'array' then s.questions_json else '[]'::jsonb end) q(value)
order by s.title, r.submitted_at, q.value ->> 'id';

create or replace view public.survey_summary with (security_invoker = on) as
select survey_id, "الاستبيان", question_id, "السؤال", "نوع_السؤال",
       count(*) filter (where "الإجابة" is not null and btrim("الإجابة") <> '') as "عدد_الإجابات",
       round(avg(nullif(regexp_replace(coalesce("الإجابة", ''), '[^0-9.]', '', 'g'), '')::numeric)
             filter (where "الإجابة" ~ '^[0-9]+(\.[0-9]+)?$'), 2) as "المتوسط",
       min(nullif(regexp_replace(coalesce("الإجابة", ''), '[^0-9.]', '', 'g'), '')::numeric)
             filter (where "الإجابة" ~ '^[0-9]+(\.[0-9]+)?$') as "الأدنى",
       max(nullif(regexp_replace(coalesce("الإجابة", ''), '[^0-9.]', '', 'g'), '')::numeric)
             filter (where "الإجابة" ~ '^[0-9]+(\.[0-9]+)?$') as "الأعلى"
from public.survey_answers_flat
group by survey_id, "الاستبيان", question_id, "السؤال", "نوع_السؤال"
order by "الاستبيان", question_id;

create or replace function public.get_survey_stats()
returns json language plpgsql security definer set search_path = public as $$
declare v json;
begin
  if not (public.has_role('admin') or public.has_role('coordinator')) then
    return json_build_object('error', 'صلاحية غير كافية');
  end if;
  select json_build_object(
    'surveys', (select count(*) from public.surveys),
    'active', (select count(*) from public.surveys where is_active),
    'responses', (select count(*) from public.survey_responses),
    'respondents', (select count(distinct user_id) from public.survey_responses),
    'response_rate', (select case when tot = 0 then 0 else round(resp::numeric / tot * 100) end
                      from (select (select count(distinct user_id) from public.survey_responses) as resp,
                                   (select count(distinct tm.user_id) from public.team_members tm) as tot) x),
    'nps_avg', (select round(avg(nps_score), 2) from public.survey_responses where nps_score is not null),
    'promoters', (select count(*) from public.survey_responses where nps_score >= 9),
    'passives', (select count(*) from public.survey_responses where nps_score between 7 and 8),
    'detractors', (select count(*) from public.survey_responses where nps_score is not null and nps_score <= 6),
    'nps', (select case when n = 0 then null else round((pro - det)::numeric / n * 100) end
            from (select count(*) filter (where nps_score is not null) as n,
                         count(*) filter (where nps_score >= 9) as pro,
                         count(*) filter (where nps_score <= 6 and nps_score is not null) as det
                  from public.survey_responses) y),
    'by_survey', (select coalesce(json_agg(x), '[]'::json) from (
                    select s.title as name, count(distinct r.user_id) as respondents, round(avg(r.nps_score), 2) as avg_nps
                    from public.surveys s left join public.survey_responses r on r.survey_id = s.id
                    group by s.id, s.title) x),
    'top_questions', (select coalesce(json_agg(x), '[]'::json) from (
                    select "السؤال" as question, "المتوسط" as avg_score, "عدد_الإجابات" as answers
                    from public.survey_summary where "المتوسط" is not null
                    order by "المتوسط" desc limit 8) x)
  ) into v;
  return v;
exception when others then
  return json_build_object('error', SQLERRM);
end;
$$;
