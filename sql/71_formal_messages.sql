-- ============================================================
-- 71: صياغة رسمية موحّدة بالعربية الفصحى لجميع الرسائل
--  • نفس البنية: عنوان قصير بلا رموز تعبيرية + نص يبدأ بـ«نفيدكم/يسرّنا/نذكّركم»
--  • التواريخ والأوقات بتوقيت مكة المكرمة وبأسماء الأيام والأشهر العربية
--    (كان وقت التذكير يُكتب بتوقيت UTC فيتأخر 3 ساعات)
--  • لا يغيّر أي جدول أو سياسة RLS — نصوص الدوال فقط
-- ============================================================

-- تاريخ ووقت بالعربية بتوقيت الرياض: «الخميس 3 ديسمبر 2026، الساعة 4:30 م»
create or replace function public.ar_datetime(p_ts timestamptz, p_with_date boolean default true)
returns text language plpgsql stable set search_path = public as $$
declare
  t timestamp := p_ts at time zone 'Asia/Riyadh';
  days text[] := array['الأحد','الاثنين','الثلاثاء','الأربعاء','الخميس','الجمعة','السبت'];
  months text[] := array['يناير','فبراير','مارس','أبريل','مايو','يونيو','يوليو','أغسطس','سبتمبر','أكتوبر','نوفمبر','ديسمبر'];
  h int; v_time text;
begin
  if p_ts is null then return ''; end if;
  h := extract(hour from t)::int;
  v_time := (case when h % 12 = 0 then 12 else h % 12 end)::text || ':' || to_char(t, 'MI')
            || case when h < 12 then ' ص' else ' م' end;
  if not p_with_date then return 'الساعة ' || v_time; end if;
  return days[extract(dow from t)::int + 1] || ' ' || extract(day from t)::int || ' '
         || months[extract(month from t)::int] || ' ' || extract(year from t)::int
         || '، الساعة ' || v_time;
end;
$$;

-- ١) إنشاء الفريق (للقائد) — الرابط في النص ليُنقر من البريد
create or replace function public.create_team_with_leader(
  p_track_id uuid,
  p_team_name text
) returns jsonb as $$
declare
  v_user_id uuid := auth.uid();
  v_team_id uuid;
  v_invite_code text;
  v_result jsonb;
  v_base text;
  v_track record;
begin
  if v_user_id is null then
    return jsonb_build_object('success', false, 'error', 'يجب تسجيل الدخول أولاً');
  end if;
  if p_team_name is null or trim(p_team_name) = '' then
    return jsonb_build_object('success', false, 'error', 'اسم الفريق مطلوب');
  end if;
  if exists (select 1 from public.team_members where user_id = v_user_id) then
    return jsonb_build_object('success', false, 'error', 'أنت عضو بفريق آخر بالفعل');
  end if;
  -- فحصا إغلاق التسجيل وسعة المسار (من الملف 33؛ سقطا سهوًا في الملف 57)
  select * into v_track from public.tracks where id = p_track_id;
  if v_track.id is null then
    return jsonb_build_object('success', false, 'error', 'المسار غير موجود');
  end if;
  if not v_track.registration_open then
    return jsonb_build_object('success', false, 'error', 'التسجيل بهذا المسار مغلق حاليًا');
  end if;
  if v_track.max_participants is not null
     and public.get_track_participant_count(p_track_id) >= v_track.max_participants then
    return jsonb_build_object('success', false, 'error', 'اكتملت السعة القصوى لهذا المسار');
  end if;
  insert into public.teams (track_id, team_name)
  values (p_track_id, trim(p_team_name))
  returning id, invite_code into v_team_id, v_invite_code;
  insert into public.team_members (team_id, user_id, is_leader)
  values (v_team_id, v_user_id, true);

  select coalesce(nullif(btrim(value), ''), 'https://seera-hackathon.vercel.app') into v_base
  from public.platform_settings where key = 'site_base_url';
  v_base := coalesce(v_base, 'https://seera-hackathon.vercel.app');

  insert into public.notifications (user_id, title, body, link)
  values (
    v_user_id,
    'تم إنشاء فريقكم بنجاح',
    'نفيدكم بأنه تم إنشاء فريق «' || trim(p_team_name) || '» بنجاح في هاكثون السيرة النبوية.' || chr(10) || chr(10) ||
    'لدعوة أعضاء فريقكم، يُرجى مشاركة رابط الدعوة الآتي معهم:' || chr(10) ||
    v_base || '/registration.html?join=' || v_invite_code || chr(10) || chr(10) ||
    'رمز الدعوة: ' || v_invite_code,
    '/registration.html?join=' || v_invite_code
  );
  select jsonb_build_object(
    'success', true,
    'team_id', t.id,
    'team_name', t.team_name,
    'invite_code', t.invite_code,
    'status', t.status
  ) into v_result
  from public.teams t where t.id = v_team_id;
  return v_result;
end;
$$ language plpgsql security definer set search_path = public;

-- ٢) تغيّر حالة الفريق (لجميع الأعضاء)
create or replace function public.notify_team_status_change()
returns trigger as $$
declare v_title text; v_body text; v_name text := '«' || new.team_name || '»';
begin
  if new.status is distinct from old.status then
    case new.status
      when 'confirmed' then
        v_title := 'اعتماد تسجيل فريقكم';
        v_body  := 'يسرّنا إبلاغكم بأنه تم اعتماد تسجيل فريق ' || v_name || ' رسميًا في هاكثون السيرة النبوية.'
                   || chr(10) || chr(10) || 'نتمنى لكم التوفيق والسداد في رحلتكم.';
      when 'disqualified' then
        v_title := 'إشعار بشأن مشاركة فريقكم';
        v_body  := 'نأسف لإبلاغكم بأنه تقرّر استبعاد فريق ' || v_name || ' من المشاركة في هاكثون السيرة النبوية.'
                   || chr(10) || chr(10) || 'للاستفسار، يُرجى التواصل مع اللجنة المنظمة.';
      when 'withdrawn' then
        v_title := 'تأكيد انسحاب فريقكم';
        v_body  := 'نفيدكم بأنه تم تسجيل انسحاب فريق ' || v_name || ' من هاكثون السيرة النبوية.'
                   || chr(10) || chr(10) || 'نشكر لكم اهتمامكم ومشاركتكم.';
      when 'pending' then
        v_title := 'طلب فريقكم قيد المراجعة';
        v_body  := 'نفيدكم بأن طلب تسجيل فريق ' || v_name || ' قيد المراجعة حاليًا، وسيتم إشعاركم فور اعتماده.';
      else
        v_title := 'تحديث حالة فريقكم';
        v_body  := 'نفيدكم بأنه تم تحديث حالة فريق ' || v_name || '. يُرجى الدخول إلى المنصة للاطلاع على التفاصيل.';
    end case;
    insert into public.notifications (user_id, title, body)
    select tm.user_id, v_title, v_body from public.team_members tm where tm.team_id = new.id;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

-- ٣ و٤) حجز جلسة إرشاد (للفريق وللمرشد)
create or replace function public.notify_mentor_booking()
returns trigger as $$
declare
  v_team_name text; v_mentor_id uuid; v_mentor_name text; v_slot_time timestamptz;
begin
  select team_name into v_team_name from public.teams where id = new.team_id;
  select mentor_user_id, start_time into v_mentor_id, v_slot_time from public.mentor_slots where id = new.slot_id;
  select full_name into v_mentor_name from public.profiles where id = v_mentor_id;

  insert into public.notifications (user_id, title, body)
  select tm.user_id, 'تأكيد حجز جلسة إرشاد',
         'نفيدكم بأنه تم حجز جلسة إرشاد لفريق «' || v_team_name || '» مع المرشد/ة '
         || coalesce(v_mentor_name, '') || '، يوم ' || public.ar_datetime(v_slot_time) || '.'
         || chr(10) || chr(10) || 'يُرجى الحضور في الموعد المحدد.'
  from public.team_members tm where tm.team_id = new.team_id;

  if v_mentor_id is not null then
    insert into public.notifications (user_id, title, body)
    values (v_mentor_id, 'حجز جديد لجلسة إرشاد',
      'نفيدكم بأن فريق «' || v_team_name || '» قد حجز جلسة إرشاد معكم، يوم '
      || public.ar_datetime(v_slot_time) || '.'
      || chr(10) || chr(10) || 'يُرجى الدخول إلى لوحة المرشد لتأكيد الجلسة.');
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

-- ٧ و٨) إلغاء جلسة إرشاد (للفريق وللمرشد)
create or replace function public.notify_mentor_booking_cancelled()
returns trigger as $$
declare v_team_name text; v_mentor_id uuid; v_slot_time timestamptz;
begin
  if new.status = 'cancelled' and old.status <> 'cancelled' then
    select team_name into v_team_name from public.teams where id = new.team_id;
    select mentor_user_id, start_time into v_mentor_id, v_slot_time from public.mentor_slots where id = new.slot_id;

    insert into public.notifications (user_id, title, body)
    select tm.user_id, 'إلغاء جلسة إرشاد',
           'نفيدكم بأنه تم إلغاء جلسة الإرشاد الخاصة بفريق «' || v_team_name || '»، التي كانت مقررة يوم '
           || public.ar_datetime(v_slot_time) || '.'
           || chr(10) || chr(10) || 'يمكنكم حجز موعد بديل من خلال المنصة.'
    from public.team_members tm where tm.team_id = new.team_id;

    if v_mentor_id is not null then
      insert into public.notifications (user_id, title, body)
      values (v_mentor_id, 'إلغاء حجز جلسة إرشاد',
        'نفيدكم بأنه تم إلغاء جلسة الإرشاد مع فريق «' || v_team_name || '»، التي كانت مقررة يوم '
        || public.ar_datetime(v_slot_time) || '.');
    end if;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

-- ٥ و٦) التذكير قبل الجلسة (بتوقيت مكة المكرمة)
create or replace function public.send_upcoming_mentorship_reminders()
returns void as $$
declare b record;
begin
  for b in (
    select mb.id, mb.team_id, ms.mentor_user_id, ms.start_time, t.team_name
    from public.mentor_bookings mb
    join public.mentor_slots ms on ms.id = mb.slot_id
    join public.teams t on t.id = mb.team_id
    where mb.status = 'confirmed'
      and mb.reminder_sent = false
      and ms.start_time between now() and now() + interval '35 minutes'
  ) loop
    insert into public.notifications (user_id, title, body)
    select tm.user_id, 'تذكير بموعد جلسة الإرشاد',
           'نذكّركم بأن جلسة الإرشاد لفريق «' || b.team_name || '» ستبدأ اليوم '
           || public.ar_datetime(b.start_time, false) || ' بتوقيت مكة المكرمة.'
           || chr(10) || chr(10) || 'يُرجى الاستعداد والحضور في الموعد المحدد.'
    from public.team_members tm where tm.team_id = b.team_id;

    insert into public.notifications (user_id, title, body)
    values (b.mentor_user_id, 'تذكير بموعد جلسة الإرشاد',
      'نذكّركم بأن جلستكم الإرشادية مع فريق «' || b.team_name || '» ستبدأ اليوم '
      || public.ar_datetime(b.start_time, false) || ' بتوقيت مكة المكرمة.');

    update public.mentor_bookings set reminder_sent = true where id = b.id;
  end loop;
end;
$$ language plpgsql security definer set search_path = public;

-- ٩) الإعلانات: العنوان بلا رمز، والنص كاملًا حتى 600 حرف ثم إحالة للمنصة
create or replace function public.notify_new_announcement()
returns trigger as $$
declare v_title text := 'إعلان: ' || new.title; v_body text;
begin
  v_body := coalesce(new.body, '');
  if length(v_body) > 600 then
    v_body := left(v_body, 600) || '…' || chr(10) || chr(10) || 'للاطلاع على الإعلان كاملًا، يُرجى الدخول إلى المنصة.';
  end if;

  if new.team_id is not null then
    insert into public.notifications (user_id, title, body, link)
    select tm.user_id, v_title, v_body, null
    from public.team_members tm where tm.team_id = new.team_id;
  else
    insert into public.notifications (user_id, title, body, link)
    select distinct p.id, v_title, v_body, null
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

-- ١٠) إصدار شهادة
create or replace function public.notify_certificate_issued()
returns trigger as $$
declare v_type text;
begin
  select name_ar into v_type from public.certificate_types where id = new.cert_type_id;
  insert into public.notifications (user_id, title, body)
  values (new.user_id, 'إصدار شهادتكم',
    'يسرّنا إبلاغكم بإصدار ' || coalesce(v_type, 'شهادتكم') || ' في هاكثون السيرة النبوية.'
    || chr(10) || chr(10) || 'يمكنكم تحميلها من تبويب «الشهادات» في المنصة.');
  return new;
end;
$$ language plpgsql security definer set search_path = public;

-- ١١) رسالة التفعيل (نصّها في الإعدادات ويمكن تعديله دون كود)
insert into public.platform_settings (key, value) values
  ('notif_activation_title', 'دعوة لتفعيل حسابكم في هاكثون السيرة النبوية'),
  ('notif_activation_body',
   'نفيدكم بأنه تم تسجيلكم ضمن فريق «{{team}}» في هاكثون السيرة النبوية.' || chr(10) || chr(10) ||
   'لتفعيل حسابكم، يُرجى اتباع الخطوات الآتية:' || chr(10) ||
   '- الدخول إلى الرابط أدناه.' || chr(10) ||
   '- اختيار تبويب «تفعيل أول مرة».' || chr(10) ||
   '- إدخال بريدكم الإلكتروني ورقم الجوال المسجَّل، ثم تعيين كلمة المرور.' || chr(10) || chr(10) ||
   '{{link}}')
on conflict (key) do update set value = excluded.value;

-- الإطار الموحّد لكل إيميل (قابل للتعديل من لوحة الإدارة ← قالب الإيميل)
update public.email_templates set
  greeting_text   = 'المكرَّم/ة {{name}}، السلام عليكم ورحمة الله وبركاته،',
  button_text     = 'الدخول إلى المنصة',
  footer_org_text = 'هاكثون السيرة النبوية — جامعة القصيم',
  updated_at      = now();
