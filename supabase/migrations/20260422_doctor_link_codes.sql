alter table public.profiles
  add column if not exists doctor_link_code text;

create unique index if not exists idx_profiles_doctor_link_code
  on public.profiles(doctor_link_code)
  where doctor_link_code is not null;

create or replace function public.generate_doctor_link_code()
returns text
language plpgsql
as $$
declare
  candidate text;
begin
  loop
    candidate := substring(upper(replace(gen_random_uuid()::text, '-', '')) from 1 for 8);
    exit when not exists (
      select 1 from public.profiles where doctor_link_code = candidate
    );
  end loop;
  return candidate;
end;
$$;

update public.profiles
set doctor_link_code = public.generate_doctor_link_code()
where role = 'doctor'
  and doctor_link_code is null;

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

  insert into public.profiles (id, role, display_name, doctor_link_code)
  values (
    new.id,
    case when requested_role = 'doctor' then 'doctor'::public.app_role else 'patient'::public.app_role end,
    coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1), ''),
    case when requested_role = 'doctor' then public.generate_doctor_link_code() else null end
  )
  on conflict (id) do update
    set role = excluded.role,
        display_name = coalesce(nullif(excluded.display_name, ''), public.profiles.display_name),
        doctor_link_code = case
          when excluded.role = 'doctor' and public.profiles.doctor_link_code is null
            then public.generate_doctor_link_code()
          else public.profiles.doctor_link_code
        end;

  return new;
end;
$$;

create or replace function public.link_patient_to_doctor(input_code text)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  patient_profile public.profiles;
  target_doctor public.profiles;
begin
  select *
  into patient_profile
  from public.profiles
  where id = auth.uid();

  if patient_profile.id is null then
    raise exception 'Authenticated user profile not found.';
  end if;

  if patient_profile.role <> 'patient' then
    raise exception 'Only patients can link to a doctor code.';
  end if;

  select *
  into target_doctor
  from public.profiles
  where role = 'doctor'
    and doctor_link_code = upper(trim(input_code));

  if target_doctor.id is null then
    raise exception 'Doctor code not found.';
  end if;

  insert into public.doctor_patient_links (doctor_id, patient_id)
  values (target_doctor.id, patient_profile.id)
  on conflict do nothing;

  return target_doctor;
end;
$$;

grant execute on function public.link_patient_to_doctor(text) to authenticated;

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
