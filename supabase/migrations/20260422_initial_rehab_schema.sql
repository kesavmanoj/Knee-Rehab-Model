create extension if not exists pgcrypto;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'app_role') then
    create type public.app_role as enum ('patient', 'doctor');
  end if;
end
$$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role public.app_role not null default 'patient',
  display_name text not null default '',
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.doctor_patient_links (
  doctor_id uuid not null references public.profiles(id) on delete cascade,
  patient_id uuid not null references public.profiles(id) on delete cascade,
  linked_at timestamptz not null default timezone('utc', now()),
  primary key (doctor_id, patient_id),
  check (doctor_id <> patient_id)
);

create table if not exists public.exercise_sessions (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.profiles(id) on delete cascade,
  started_at timestamptz not null,
  ended_at timestamptz not null,
  exercise_type text not null,
  rep_count integer not null check (rep_count >= 0),
  peak_flexion_deg double precision not null,
  extension_lag_deg double precision not null,
  duration_ms integer not null check (duration_ms >= 0),
  session_status text not null default 'completed',
  device_name text,
  firmware_protocol_version text,
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.session_angle_samples (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.exercise_sessions(id) on delete cascade,
  sample_index integer not null,
  elapsed_ms integer not null check (elapsed_ms >= 0),
  final_angle_deg double precision not null,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_profiles_role on public.profiles(role);
create index if not exists idx_links_doctor on public.doctor_patient_links(doctor_id);
create index if not exists idx_links_patient on public.doctor_patient_links(patient_id);
create index if not exists idx_sessions_patient_started on public.exercise_sessions(patient_id, started_at desc);
create index if not exists idx_samples_session_index on public.session_angle_samples(session_id, sample_index);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  requested_role text;
begin
  requested_role := coalesce(new.raw_user_meta_data ->> 'role', 'patient');

  insert into public.profiles (id, role, display_name)
  values (
    new.id,
    case when requested_role = 'doctor' then 'doctor'::public.app_role else 'patient'::public.app_role end,
    coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1), '')
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

create or replace function public.is_doctor_for_patient(target_patient_id uuid)
returns boolean
language sql
stable
as $$
  select exists (
    select 1
    from public.doctor_patient_links link
    join public.profiles p on p.id = link.doctor_id
    where link.patient_id = target_patient_id
      and link.doctor_id = auth.uid()
      and p.role = 'doctor'
  );
$$;

alter table public.profiles enable row level security;
alter table public.doctor_patient_links enable row level security;
alter table public.exercise_sessions enable row level security;
alter table public.session_angle_samples enable row level security;

drop policy if exists "profiles_self_or_assigned_doctor_select" on public.profiles;
create policy "profiles_self_or_assigned_doctor_select"
on public.profiles
for select
to authenticated
using (
  id = auth.uid()
  or exists (
    select 1
    from public.doctor_patient_links link
    where (link.doctor_id = auth.uid() and link.patient_id = public.profiles.id)
       or (link.patient_id = auth.uid() and link.doctor_id = public.profiles.id)
  )
);

drop policy if exists "profiles_self_update" on public.profiles;
create policy "profiles_self_update"
on public.profiles
for update
to authenticated
using (id = auth.uid())
with check (id = auth.uid() and role = (select role from public.profiles where id = auth.uid()));

drop policy if exists "links_visible_to_participants" on public.doctor_patient_links;
create policy "links_visible_to_participants"
on public.doctor_patient_links
for select
to authenticated
using (
  doctor_id = auth.uid()
  or patient_id = auth.uid()
);

drop policy if exists "sessions_patient_insert" on public.exercise_sessions;
create policy "sessions_patient_insert"
on public.exercise_sessions
for insert
to authenticated
with check (
  patient_id = auth.uid()
);

drop policy if exists "sessions_patient_or_doctor_select" on public.exercise_sessions;
create policy "sessions_patient_or_doctor_select"
on public.exercise_sessions
for select
to authenticated
using (
  patient_id = auth.uid()
  or public.is_doctor_for_patient(patient_id)
);

drop policy if exists "samples_patient_insert" on public.session_angle_samples;
create policy "samples_patient_insert"
on public.session_angle_samples
for insert
to authenticated
with check (
  exists (
    select 1
    from public.exercise_sessions s
    where s.id = session_angle_samples.session_id
      and s.patient_id = auth.uid()
  )
);

drop policy if exists "samples_patient_or_doctor_select" on public.session_angle_samples;
create policy "samples_patient_or_doctor_select"
on public.session_angle_samples
for select
to authenticated
using (
  exists (
    select 1
    from public.exercise_sessions s
    where s.id = session_angle_samples.session_id
      and (
        s.patient_id = auth.uid()
        or public.is_doctor_for_patient(s.patient_id)
      )
  )
);
