-- ============================================================
-- 88) تسمية «الميسّر» صارت «المنظّم» في النصوص الظاهرة فقط
-- ------------------------------------------------------------
-- المفتاح الداخلي للدور يبقى facilitator، وكذلك أسماء الجداول والدوال
-- والصفحات (facilitator.html / facilitator-apply.html)، فلا يتأثر أي ربط.
-- يُحدَّث الاسم العربي للدور ورسائل دوال طلبات الانضمام والصلاحيات.
-- ============================================================
do $$
declare f record; d text;
begin
  for f in select oid from pg_proc where pronamespace='public'::regnamespace
           and proname in ('approve_facilitator_application','reject_facilitator_application','set_facilitator_permissions','submit_facilitator_application')
  loop
    d := pg_get_functiondef(f.oid);
    d := replace(d, 'ميسّرًا', 'منظّمًا');
    d := replace(d, 'ميسّر', 'منظّم');
    d := replace(d, 'صفحة المنظّم', 'صفحة المنظّمين');
    execute d;
  end loop;
end $$;
update public.roles set name_ar = 'منظّم' where key = 'facilitator';
