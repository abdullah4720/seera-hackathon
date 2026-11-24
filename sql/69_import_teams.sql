-- ============================================================
-- 69: استيراد الفرق من Excel + تفعيل الحسابات المستورَدة
-- منقول من منصة ابتكار إنفاذ (كود فقط، بلا بيانات) ومكيَّف للسيرة:
--   • مطابقة مساري السيرة (رحلة / البصمة)
--   • لا حقول سجل تجاري أو براءة
--   • أمان إضافي: حالة «بانتظار التفعيل» تُعطى فقط للحسابات
--     التي أنشأها الاستيراد نفسه، فلا يمكن تفعيل (أي الاستيلاء على)
--     حساب سجّل صاحبه بنفسه بمعرفة بريده وجواله.
-- لا يغيّر أي سياسة RLS قائمة.
-- ============================================================

-- 1) الأعمدة
alter table public.profiles add column if not exists activation_status text not null default 'active';
alter table public.profiles add column if not exists activated_at timestamptz;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'profiles_activation_status_check') then
    alter table public.profiles add constraint profiles_activation_status_check
      check (activation_status in ('pending','active'));
  end if;
end $$;
-- كل الحسابات الموجودة قبل هذا الملف سجّلت بنفسها: مفعّلة
update public.profiles set activation_status = 'active', activated_at = coalesce(activated_at, created_at)
where activated_at is null;

alter table public.teams add column if not exists registration_no text;
create unique index if not exists teams_registration_no_uidx
  on public.teams(registration_no) where registration_no is not null;

-- 2) دوال مساعدة
create or replace function public.normalize_phone(p_phone text)
returns text language plpgsql immutable set search_path = public as $$
declare v text;
begin
  v := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  if v = '' then return null; end if;
  if v like '966%' and length(v) = 12 then v := '0' || substring(v from 4); end if;
  if length(v) = 9 and v like '5%' then v := '0' || v; end if;
  return v;
end;
$$;

create or replace function public.match_track(p_name text)
returns uuid language plpgsql stable security definer set search_path = public as $$
declare
  v_id uuid;
  v_txt text := lower(btrim(coalesce(p_name, '')));
begin
  if v_txt = '' then return null; end if;
  select id into v_id from public.tracks where lower(btrim(name_ar)) = v_txt limit 1;
  if v_id is not null then return v_id; end if;
  select id into v_id from public.tracks where lower(track_code) = v_txt limit 1;
  if v_id is not null then return v_id; end if;
  select id into v_id from public.tracks
  where (v_txt like '%رحل%' and name_ar like '%رحلة%')
     or ((v_txt like '%بصم%' or v_txt like '%رقمي%') and name_ar like '%البصمة%')
  limit 1;
  return v_id;
end;
$$;

create or replace function public.notif_text(p_key text, p_default text)
returns text language sql stable security definer set search_path = public as $$
  select coalesce(nullif(btrim(value), ''), p_default)
  from public.platform_settings where key = p_key
  union all select p_default
  limit 1;
$$;

create or replace function public.create_auth_user_for_import(p_email text, p_full_name text)
returns uuid language plpgsql security definer set search_path = public, extensions, auth as $$
declare v_uid uuid := gen_random_uuid();
begin
  insert into auth.users (
    id, instance_id, email, aud, role, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data,
    confirmation_token, recovery_token, email_change_token_new, email_change,
    created_at, updated_at
  ) values (
    v_uid, '00000000-0000-0000-0000-000000000000', lower(btrim(p_email)),
    'authenticated', 'authenticated',
    crypt(gen_random_uuid()::text, gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('full_name', coalesce(p_full_name, '')),
    '', '', '', '', now(), now()
  );
  return v_uid;
end;
$$;
-- داخلية فقط: لا تُستدعى من الواجهة
revoke execute on function public.create_auth_user_for_import(text, text) from public, anon, authenticated;

-- 3) استيراد فريق واحد (صف من الملف)
create or replace function public.import_team(p_team jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_track_id uuid; v_team_id uuid; v_member jsonb; v_uid uuid;
  v_email text; v_phone text; v_is_new boolean;
  v_created int := 0; v_linked int := 0;
  v_warnings text[] := '{}'; v_name text;
begin
  if not exists (
    select 1 from public.user_roles ur join public.roles r on r.id = ur.role_id
    where ur.user_id = auth.uid() and r.key in ('admin','coordinator')
  ) then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل');
  end if;

  v_name := btrim(coalesce(p_team->>'team_name', ''));
  if v_name = '' then
    return jsonb_build_object('success', false, 'error', 'اسم الفريق مطلوب');
  end if;

  v_track_id := public.match_track(p_team->>'track');
  if v_track_id is null then
    return jsonb_build_object('success', false,
      'error', 'المسار غير معروف: ' || coalesce(p_team->>'track', '(فارغ)'), 'team', v_name);
  end if;

  select id into v_team_id from public.teams
  where registration_no = nullif(btrim(p_team->>'reg_no'), '') limit 1;

  if v_team_id is null then
    insert into public.teams (team_name, track_id, status, registration_no)
    values (v_name, v_track_id, 'confirmed', nullif(btrim(p_team->>'reg_no'), ''))
    returning id into v_team_id;
  else
    update public.teams set team_name = v_name, track_id = v_track_id, status = 'confirmed'
    where id = v_team_id;
  end if;

  if coalesce(btrim(p_team->>'project_title'), '') <> '' then
    if exists (select 1 from public.submissions where team_id = v_team_id) then
      update public.submissions
      set title = p_team->>'project_title', description = p_team->>'project_desc'
      where team_id = v_team_id
        and version = (select max(version) from public.submissions where team_id = v_team_id);
    else
      insert into public.submissions (team_id, title, description, version)
      values (v_team_id, p_team->>'project_title', p_team->>'project_desc', 1);
    end if;
  end if;

  for v_member in select * from jsonb_array_elements(coalesce(p_team->'members', '[]'::jsonb)) loop
    v_email := lower(btrim(coalesce(v_member->>'email', '')));
    v_phone := public.normalize_phone(v_member->>'phone');
    if v_email = '' then
      v_warnings := v_warnings || ('عضو بلا بريد في فريق ' || v_name);
      continue;
    end if;

    select id into v_uid from auth.users where lower(email) = v_email limit 1;
    v_is_new := v_uid is null;
    if v_is_new then
      v_uid := public.create_auth_user_for_import(v_email, v_member->>'name');
      v_created := v_created + 1;
    end if;

    insert into public.profiles (id, full_name, email, phone, organization,
                                 category, city, gender, project_role, activation_status)
    values (v_uid, coalesce(nullif(btrim(v_member->>'name'), ''), split_part(v_email, '@', 1)),
            v_email, v_phone,
            nullif(btrim(v_member->>'org'), ''), nullif(btrim(v_member->>'category'), ''),
            nullif(btrim(v_member->>'city'), ''),
            case lower(btrim(coalesce(v_member->>'gender','')))
              when 'ذكر' then 'ذكر' when 'أنثى' then 'أنثى' when 'انثى' then 'أنثى'
              when 'male' then 'ذكر' when 'female' then 'أنثى' else null end,
            nullif(btrim(v_member->>'role'), ''),
            case when v_is_new then 'pending' else 'active' end)
    on conflict (id) do update set
      full_name    = coalesce(nullif(btrim(v_member->>'name'), ''), public.profiles.full_name),
      phone        = coalesce(excluded.phone, public.profiles.phone),
      organization = coalesce(excluded.organization, public.profiles.organization),
      category     = coalesce(excluded.category, public.profiles.category),
      city         = coalesce(excluded.city, public.profiles.city),
      gender       = coalesce(excluded.gender, public.profiles.gender),
      project_role = coalesce(excluded.project_role, public.profiles.project_role),
      -- الحساب الجديد فقط يُعلَّم «بانتظار التفعيل»؛ الموجود مسبقًا لا يُمسّ
      activation_status = case when v_is_new then 'pending' else public.profiles.activation_status end;

    delete from public.team_members where user_id = v_uid and team_id <> v_team_id;
    insert into public.team_members (team_id, user_id, is_leader)
    values (v_team_id, v_uid, coalesce((v_member->>'is_leader')::boolean, false))
    on conflict (team_id, user_id) do update set is_leader = excluded.is_leader;
    v_linked := v_linked + 1;
  end loop;

  return jsonb_build_object('success', true, 'team_id', v_team_id, 'team', v_name,
    'accounts_created', v_created, 'members_linked', v_linked, 'warnings', to_jsonb(v_warnings));
exception when others then
  return jsonb_build_object('success', false, 'team', v_name, 'error', sqlerrm);
end;
$$;

-- 4) تفعيل الحساب المستورَد (بالبريد + الجوال المسجَّل) — مرة واحدة فقط
create or replace function public.activate_imported_account(p_email text, p_phone text, p_new_password text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_uid uuid; v_status text; v_stored text; v_activated timestamptz;
begin
  if length(coalesce(p_new_password, '')) < 6 then
    return jsonb_build_object('success', false, 'error', 'كلمة المرور يجب ألا تقل عن ستة أحرف');
  end if;

  select p.id, p.activation_status, p.phone, p.activated_at
    into v_uid, v_status, v_stored, v_activated
  from public.profiles p where lower(p.email) = lower(btrim(p_email));

  -- رسالة موحّدة لكل حالات الفشل حتى لا تُكشف الحسابات
  if v_uid is null or v_status <> 'pending' or v_activated is not null
     or public.normalize_phone(v_stored) is null
     or public.normalize_phone(v_stored) is distinct from public.normalize_phone(p_phone) then
    return jsonb_build_object('success', false,
      'error', 'تعذّر التفعيل: تأكد من البريد ورقم الجوال المسجَّلين في بيانات فريقك، أو أن الحساب لم يُفعَّل مسبقًا');
  end if;

  update auth.users
  set encrypted_password = crypt(p_new_password, gen_salt('bf')),
      email_confirmed_at = coalesce(email_confirmed_at, now()),
      updated_at = now()
  where id = v_uid;

  update public.profiles set activation_status = 'active', activated_at = now() where id = v_uid;
  return jsonb_build_object('success', true);
end;
$$;
grant execute on function public.activate_imported_account(text, text, text) to anon, authenticated;

-- 5) رسائل التفعيل (معاينة أو إرسال)
create or replace function public.send_activation_invites(p_team_id uuid default null, p_dry_run boolean default false)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_title text; v_body text; v_base text; v_link text; v_sent int := 0;
  r record; v_list jsonb := '[]'::jsonb;
begin
  if not exists (
    select 1 from public.user_roles ur join public.roles r2 on r2.id = ur.role_id
    where ur.user_id = auth.uid() and r2.key in ('admin','coordinator')
  ) then
    return jsonb_build_object('success', false, 'error', 'غير مخوّل');
  end if;

  v_title := public.notif_text('notif_activation_title', 'مرحبًا بكم في هاكثون السيرة النبوية');
  v_body  := public.notif_text('notif_activation_body',
               'تم تسجيلكم ضمن فريق «{{team}}» في هاكثون السيرة النبوية.' || chr(10) || chr(10) ||
               'للتفعيل: افتحوا الرابط واختاروا «تفعيل أول مرة»، ثم أدخلوا بريدكم ورقم جوالكم المسجَّل.' || chr(10) || chr(10) ||
               '{{link}}');
  select value into v_base from public.platform_settings where key = 'site_base_url';
  v_link := coalesce(nullif(btrim(v_base), ''), 'https://seera-hackathon.vercel.app') || '/registration.html';

  for r in
    select p.id, p.full_name, p.email, t.team_name
    from public.profiles p
    join public.team_members tm on tm.user_id = p.id
    join public.teams t on t.id = tm.team_id
    where p.activation_status = 'pending' and p.activated_at is null
      and (p_team_id is null or t.id = p_team_id)
    order by t.team_name, p.full_name
  loop
    v_list := v_list || jsonb_build_object('name', r.full_name, 'email', r.email, 'team', r.team_name);
    if not p_dry_run then
      insert into public.notifications (user_id, title, body, link)
      values (r.id, v_title,
              replace(replace(v_body, '{{team}}', coalesce(r.team_name, '')), '{{link}}', v_link),
              '/registration.html');
    end if;
    v_sent := v_sent + 1;
  end loop;

  return jsonb_build_object('success', true, 'dry_run', p_dry_run, 'count', v_sent, 'recipients', v_list);
end;
$$;

-- 6) من يدخل بأي طريقة أخرى (مثل استعادة كلمة المرور) يُعدّ مفعّلًا
create or replace function public.sync_activation_on_login()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.last_sign_in_at is not null
     and (old.last_sign_in_at is null or old.last_sign_in_at < new.last_sign_in_at) then
    update public.profiles
    set activation_status = 'active', activated_at = coalesce(activated_at, new.last_sign_in_at)
    where id = new.id and activation_status <> 'active';
  end if;
  return new;
exception when others then
  return new;
end;
$$;
drop trigger if exists trg_sync_activation_on_login on auth.users;
create trigger trg_sync_activation_on_login
  after update of last_sign_in_at on auth.users
  for each row execute function public.sync_activation_on_login();

insert into public.platform_settings (key, value) values
  ('site_base_url', 'https://seera-hackathon.vercel.app')
on conflict (key) do nothing;
