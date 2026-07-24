-- ============================================================
-- ELH-PRIMARY1 — Phase 0: Foundation Database Schema
-- يُنفَّذ بالكامل داخل Supabase → SQL Editor → New Query → Run
-- مبني على Database Design (المخرج 9) + Behavioral Analytics (المخرج 14)
-- ============================================================

-- تفعيل امتداد UUID
create extension if not exists "pgcrypto";

-- ============================================================
-- 1. جدول units — المحطات الست (بيانات مرجعية ثابتة)
-- ============================================================
create table units (
  id uuid primary key default gen_random_uuid(),
  order_index int not null unique check (order_index between 1 and 6),
  location_name text not null,
  learning_outcome_codes text[] not null default '{}',
  phonics_letters text[] not null default '{}'
);

-- ============================================================
-- 2. جدول admins — حسابات المدير (مرتبط بـ Supabase Auth)
-- ============================================================
create table admins (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  role text not null default 'admin'
);

-- ============================================================
-- 3. جدول students — الطلاب
-- ============================================================
create table students (
  id uuid primary key default gen_random_uuid(),
  display_name text not null,
  username text not null unique,
  pin_hash text not null, -- تجزئة (hash) لرمز الدخول البصري، وليس نصًا صريحًا
  avatar_config jsonb default '{}',
  current_unit_id uuid references units(id),
  placement_result jsonb default '{}',
  status text not null default 'active' check (status in ('active','paused','archived')),
  created_at timestamptz not null default now()
);

-- ============================================================
-- 4. جدول guardians — بيانات تواصل ولي الأمر (بدون أي حساب دخول)
-- ============================================================
create table guardians (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references students(id) on delete cascade,
  contact_email text not null,
  contact_name text
);

-- ============================================================
-- 5. جدول unit_progress — تقدّم كل طالب بكل مرحلة
-- ============================================================
create table unit_progress (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references students(id) on delete cascade,
  unit_id uuid not null references units(id),
  stage text not null check (stage in (
    'learning_goal','story','adventure','game','practice',
    'song','phonics','challenge','assessment'
  )),
  status text not null default 'locked' check (status in ('locked','in_progress','completed')),
  completed_at timestamptz,
  score_internal jsonb default '{}',
  unique (student_id, unit_id, stage)
);

-- ============================================================
-- 6. جدول phonics_attempts — محاولات النطق
-- ============================================================
create table phonics_attempts (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references students(id) on delete cascade,
  unit_id uuid not null references units(id),
  letter text not null,
  audio_storage_path text,
  accuracy_score numeric,
  attempt_number int not null default 1,
  created_at timestamptz not null default now()
);

-- ============================================================
-- 7. جدول rewards — نظام التحفيز
-- ============================================================
create table rewards (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references students(id) on delete cascade,
  type text not null check (type in ('star','coin','badge','medal','treasure')),
  reference_unit_id uuid references units(id),
  awarded_at timestamptz not null default now()
);

-- ============================================================
-- 8. جدول ai_analytics — تحليلات Joe
-- ============================================================
create table ai_analytics (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references students(id) on delete cascade,
  metric_type text not null check (metric_type in (
    'pronunciation','vocabulary','reading','listening','consistency','pace'
  )),
  value jsonb not null default '{}',
  period_start date not null,
  period_end date not null,
  generated_recommendation text,
  created_at timestamptz not null default now()
);

-- ============================================================
-- 9. جدول reports — تقارير أولياء الأمور
-- ============================================================
create table reports (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references students(id) on delete cascade,
  period_type text not null check (period_type in ('weekly','monthly')),
  pdf_storage_path text,
  generated_at timestamptz not null default now(),
  sent_status text not null default 'draft' check (sent_status in ('draft','sent','not_sent')),
  sent_at timestamptz,
  sent_to_guardian_id uuid references guardians(id)
);

-- ============================================================
-- 10. جدول video_library — مكتبة الفيديو
-- ============================================================
create table video_library (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  topic_category text not null,
  video_storage_path text,
  external_url text
);

-- ============================================================
-- 11. جدول behavior_events — أحداث سلوكية (من المخرج 14)
-- ============================================================
create table behavior_events (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references students(id) on delete cascade,
  unit_id uuid references units(id),
  stage text,
  event_type text not null check (event_type in (
    'stage_start_delay','retry_triggered','voluntary_replay',
    'session_pause','stage_completion_time','joe_help_requested','abandonment_point'
  )),
  duration_ms int,
  created_at timestamptz not null default now()
);

-- ============================================================
-- تفعيل Row Level Security على كل جدول بدون استثناء
-- ============================================================
alter table units enable row level security;
alter table admins enable row level security;
alter table students enable row level security;
alter table guardians enable row level security;
alter table unit_progress enable row level security;
alter table phonics_attempts enable row level security;
alter table rewards enable row level security;
alter table ai_analytics enable row level security;
alter table reports enable row level security;
alter table video_library enable row level security;
alter table behavior_events enable row level security;

-- ============================================================
-- دالة مساعدة: هل المستخدم الحالي مدير؟
-- ============================================================
create or replace function is_admin()
returns boolean as $$
  select exists (select 1 from admins where id = auth.uid());
$$ language sql security definer stable;

-- ============================================================
-- سياسات RLS
-- ملاحظة: مصادقة الطالب تتم عبر Edge Function مخصصة تُصدر JWT
-- يحمل claim باسم "student_id" — انظر دليل الإعداد لتفاصيل التنفيذ.
-- ============================================================

-- units: الكل يقرأ (بيانات مرجعية غير حساسة)، المدير فقط يكتب
create policy "units_read_all" on units for select using (true);
create policy "units_admin_write" on units for all using (is_admin());

-- admins: المدير يقرأ بيانات نفسه فقط
create policy "admins_self_read" on admins for select using (id = auth.uid());

-- students: المدير كامل الصلاحية، الطالب يقرأ/يعدّل صفه فقط
create policy "students_admin_all" on students for all using (is_admin());
create policy "students_self_read" on students for select
  using (id = (auth.jwt() ->> 'student_id')::uuid);

-- guardians: المدير فقط
create policy "guardians_admin_all" on guardians for all using (is_admin());

-- unit_progress: المدير كامل، الطالب يقرأ فقط صفوفه (لا يعدّل مباشرة)
create policy "progress_admin_all" on unit_progress for all using (is_admin());
create policy "progress_self_read" on unit_progress for select
  using (student_id = (auth.jwt() ->> 'student_id')::uuid);

-- phonics_attempts: المدير كامل، الطالب يضيف/يقرأ محاولاته فقط
create policy "phonics_admin_all" on phonics_attempts for all using (is_admin());
create policy "phonics_self_rw" on phonics_attempts for all
  using (student_id = (auth.jwt() ->> 'student_id')::uuid)
  with check (student_id = (auth.jwt() ->> 'student_id')::uuid);

-- rewards: المدير كامل، الطالب يقرأ فقط
create policy "rewards_admin_all" on rewards for all using (is_admin());
create policy "rewards_self_read" on rewards for select
  using (student_id = (auth.jwt() ->> 'student_id')::uuid);

-- ai_analytics: المدير فقط (لا وصول مباشر للطالب، حسب AI Architecture)
create policy "analytics_admin_all" on ai_analytics for all using (is_admin());

-- reports: المدير فقط بالكامل
create policy "reports_admin_all" on reports for all using (is_admin());

-- video_library: الكل يقرأ، المدير فقط يكتب
create policy "video_read_all" on video_library for select using (true);
create policy "video_admin_write" on video_library for all using (is_admin());

-- behavior_events: المدير يقرأ الكل، الطالب يضيف فقط لنفسه (لا قراءة)
create policy "behavior_admin_read" on behavior_events for select using (is_admin());
create policy "behavior_self_insert" on behavior_events for insert
  with check (student_id = (auth.jwt() ->> 'student_id')::uuid);

-- ============================================================
-- بيانات أولية: المحطات الست (بدون أي إشارة لمصدر المنهج)
-- ============================================================
insert into units (order_index, location_name, learning_outcome_codes, phonics_letters) values
(1, 'بوابة إل',        array['LO-U1-01','LO-U1-02','LO-U1-03','LO-U1-04','LO-U1-05'], array['Tt','Ii']),
(2, 'حديقة الألوان',    array['LO-U2-01','LO-U2-02','LO-U2-03','LO-U2-04','LO-U2-05','LO-U2-06'], array['Ss','Aa']),
(3, 'بيت الشجرة العائلي', array['LO-U3-01','LO-U3-02','LO-U3-03','LO-U3-04','LO-U3-05'], array['Nn','Pp','Hh','Dd']),
(4, 'مرآة الاكتشاف',    array['LO-U4-01','LO-U4-02','LO-U4-03','LO-U4-04','LO-U4-05','LO-U4-06'], array['Rr','Ee','Cc','Kk']),
(5, 'حقول إل',          array['LO-U5-01','LO-U5-02','LO-U5-03','LO-U5-04','LO-U5-05','LO-U5-06'], array['Mm','Gg','Oo','Ff']),
(6, 'الغابة الصغيرة',   array['LO-U6-01','LO-U6-02','LO-U6-03','LO-U6-04','LO-U6-05','LO-U6-06'], array['Bb','Ll','Uu','Jj']);

-- ============================================================
-- نهاية سكريبت المرحلة 0
-- الخطوة التالية بعد التنفيذ: إنشاء أول حساب مدير من Supabase Auth
-- ثم إدخال صفه في جدول admins يدويًا (مرة واحدة فقط)
-- ============================================================
