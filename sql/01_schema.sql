-- ============================================================
-- منصة هاكثون السيرة النبوية - مخطط قاعدة البيانات
-- Prophetic Biography Hackathon Platform - Database Schema
-- ============================================================
-- ملاحظة: يُطبّق هذا الملف على Supabase (PostgreSQL)
-- الترتيب: هذا الملف أولاً، ثم 02_rls_policies.sql، ثم 03_functions.sql، ثم 04_seed.sql
-- ============================================================

-- تفعيل الإضافات المطلوبة
create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";

-- ============================================================
-- 1. المستخدمون والأدوار (Users & Roles)
-- ============================================================

-- ملف المستخدم (يمتد جدول auth.users المدمج في Supabase)
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  email text not null unique,
  phone text,
  national_id text,
  organization text,           -- الجهة (جامعة، شركة، إلخ)
  city text,
  avatar_url text,
  bio text,                    -- نبذة (تُستخدم لملفات المرشدين/المحكّمين)
  is_active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- الأدوار المتاحة بالنظام (قابلة للتوسعة)
create table public.roles (
  id serial primary key,
  key text not null unique,      -- participant | mentor | judge | admin | coordinator
  name_ar text not null,
  name_en text
);

-- ============================================================
-- 2. المسارات (Tracks) - تُعرَّف هنا مبكرًا لأن user_roles يشير إليها
-- ============================================================

create table public.tracks (
  id uuid primary key default gen_random_uuid(),
  name_ar text not null,
  name_en text,
  description text,
  max_team_size int default 5,
  min_team_size int default 2,
  registration_open boolean default true,
  display_order int default 0,
  is_active boolean default true,
  created_at timestamptz default now()
);

-- ربط المستخدمين بالأدوار (يسمح بأكثر من دور لنفس الشخص)
-- الدور ممكن يكون عام (track_id = null) أو مخصص لمسار معين
create table public.user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  role_id int not null references public.roles(id) on delete cascade,
  track_id uuid references public.tracks(id) on delete cascade,
  assigned_at timestamptz default now(),
  assigned_by uuid references public.profiles(id),
  unique (user_id, role_id, track_id)
);

-- ============================================================
-- 3. الفرق (Teams)
-- ============================================================

create table public.teams (
  id uuid primary key default gen_random_uuid(),
  track_id uuid not null references public.tracks(id),
  team_name text not null,
  status text not null default 'pending'
    check (status in ('pending','confirmed','disqualified','withdrawn')),
  invite_code text unique default substr(md5(random()::text), 1, 8),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table public.team_members (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  is_leader boolean default false,
  joined_at timestamptz default now(),
  unique (team_id, user_id)
);

-- الفكرة/المشروع المقدم من كل فريق (بإصدارات متعددة)
create table public.submissions (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  title text not null,
  description text,
  file_url text,
  version int default 1,
  submitted_at timestamptz default now(),
  is_final boolean default false
);

-- ============================================================
-- 4. التحضير (Preparation / Training Sessions)
-- ============================================================

create table public.prep_sessions (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  track_id uuid references public.tracks(id),  -- null = لجميع المسارات
  session_date timestamptz not null,
  duration_minutes int default 60,
  location text,
  is_online boolean default false,
  meeting_url text,
  capacity int,
  created_at timestamptz default now()
);

create table public.prep_attendance (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.prep_sessions(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  checked_in_at timestamptz default now(),
  unique (session_id, user_id)
);

-- ============================================================
-- 5. الإرشاد (Mentorship)
-- ============================================================

create table public.mentor_slots (
  id uuid primary key default gen_random_uuid(),
  mentor_user_id uuid not null references public.profiles(id) on delete cascade,
  start_time timestamptz not null,
  end_time timestamptz not null,
  location text,
  is_online boolean default true,
  meeting_url text,
  is_booked boolean default false,
  created_at timestamptz default now()
);

create table public.mentor_bookings (
  id uuid primary key default gen_random_uuid(),
  slot_id uuid not null references public.mentor_slots(id) on delete cascade,
  team_id uuid not null references public.teams(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending','confirmed','completed','cancelled')),
  requested_topic text,
  created_at timestamptz default now(),
  unique (slot_id)  -- كل موعد يُحجز مرة وحدة
);

create table public.mentor_feedback (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.mentor_bookings(id) on delete cascade,
  mentor_user_id uuid not null references public.profiles(id),
  team_id uuid not null references public.teams(id),
  notes text,
  team_readiness_score int check (team_readiness_score between 1 and 5),
  created_at timestamptz default now()
);

-- ============================================================
-- 6. التحكيم (Judging)
-- ============================================================

create table public.judging_rounds (
  id uuid primary key default gen_random_uuid(),
  name_ar text not null,       -- مثال: التصفية الأولية، النهائي
  round_order int not null,
  is_active boolean default false,
  starts_at timestamptz,
  ends_at timestamptz
);

-- معايير التقييم (قابلة للتعديل من لوحة التحكم، بدون تعديل كود)
create table public.judging_criteria (
  id uuid primary key default gen_random_uuid(),
  round_id uuid not null references public.judging_rounds(id) on delete cascade,
  name_ar text not null,
  description text,
  weight numeric(5,2) not null default 1.0,   -- وزن المعيار
  max_score int not null default 10,
  display_order int default 0
);

-- تعيين المحكّمين للفرق (مع دعم فحص تعارض المصالح)
create table public.judge_assignments (
  id uuid primary key default gen_random_uuid(),
  judge_user_id uuid not null references public.profiles(id) on delete cascade,
  team_id uuid not null references public.teams(id) on delete cascade,
  round_id uuid not null references public.judging_rounds(id) on delete cascade,
  has_conflict boolean default false,   -- يُعلَّم يدويًا أو تلقائيًا عند تطابق الجهة
  conflict_reason text,
  created_at timestamptz default now(),
  unique (judge_user_id, team_id, round_id)
);

create table public.scores (
  id uuid primary key default gen_random_uuid(),
  judge_user_id uuid not null references public.profiles(id),
  team_id uuid not null references public.teams(id),
  round_id uuid not null references public.judging_rounds(id),
  criteria_id uuid not null references public.judging_criteria(id),
  score numeric(5,2) not null,
  comments text,
  submitted_at timestamptz default now(),
  unique (judge_user_id, team_id, round_id, criteria_id)
);

-- ============================================================
-- 7. الفعاليات والحضور العام (Events & Attendance)
-- ============================================================

create table public.events (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  event_date timestamptz not null,
  location text,
  qr_token text unique default gen_random_uuid()::text,
  created_at timestamptz default now()
);

create table public.event_attendance (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  scanned_at timestamptz default now(),
  unique (event_id, user_id)
);

-- ============================================================
-- 8. الشهادات (Certificates)
-- ============================================================

create table public.certificate_types (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,          -- participation | mentor | judge | winner
  name_ar text not null,
  template_url text,
  min_attendance_pct numeric(5,2) default 0,   -- الحد الأدنى لنسبة الحضور
  requires_survey boolean default false,        -- يشترط تعبئة استبيان
  is_active boolean default true
);

create table public.certificates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  cert_type_id uuid not null references public.certificate_types(id),
  verification_code text unique default upper(substr(md5(random()::text), 1, 10)),
  pdf_url text,
  issued_at timestamptz default now(),
  unique (user_id, cert_type_id)
);

-- ============================================================
-- 9. الاستبيانات وقياس الرضا (Surveys & Satisfaction)
-- ============================================================

create table public.surveys (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  target_stage text not null
    check (target_stage in ('prep','mentorship','judging','closing','overall')),
  questions_json jsonb not null,   -- بنية مرنة للأسئلة
  is_active boolean default true,
  gates_certificate_type_id uuid references public.certificate_types(id),
  created_at timestamptz default now()
);

create table public.survey_responses (
  id uuid primary key default gen_random_uuid(),
  survey_id uuid not null references public.surveys(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  answers_json jsonb not null,
  nps_score int check (nps_score between 0 and 10),
  submitted_at timestamptz default now(),
  unique (survey_id, user_id)
);

-- ============================================================
-- 10. سجل النشاطات (Audit Log) - اختياري لكن مفيد للإدارة
-- ============================================================

create table public.activity_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id),
  action text not null,
  entity_type text,
  entity_id uuid,
  metadata jsonb,
  created_at timestamptz default now()
);

-- ============================================================
-- الفهارس (Indexes) لتحسين الأداء
-- ============================================================

create index idx_user_roles_user on public.user_roles(user_id);
create index idx_team_members_team on public.team_members(team_id);
create index idx_team_members_user on public.team_members(user_id);
create index idx_teams_track on public.teams(track_id);
create index idx_scores_team_round on public.scores(team_id, round_id);
create index idx_judge_assignments_judge on public.judge_assignments(judge_user_id);
create index idx_prep_attendance_session on public.prep_attendance(session_id);
create index idx_event_attendance_event on public.event_attendance(event_id);
create index idx_survey_responses_survey on public.survey_responses(survey_id);
create index idx_certificates_user on public.certificates(user_id);
