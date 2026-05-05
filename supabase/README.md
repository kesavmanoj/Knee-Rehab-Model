# Supabase Setup

This project now expects a Supabase backend for:

- email/password login
- patient and doctor self-signup
- doctor and patient role resolution
- doctor to patient assignment through a doctor code
- exercise session storage
- fused-angle graph sample storage

## 1. Create the Supabase project

Create a new Supabase project and keep the following two values ready:

- project URL
- anon public key

## 2. Run the database schema

In the Supabase SQL editor, run:

- `supabase/migrations/20260422_initial_rehab_schema.sql`
- `supabase/migrations/20260422_doctor_link_codes.sql`

This creates:

- `profiles`
- `doctor_patient_links`
- `exercise_sessions`
- `session_angle_samples`
- the `handle_new_user()` trigger
- the `doctor_link_code` column for doctor accounts
- the `link_patient_to_doctor()` RPC
- row-level security policies

If you already ran the first migration before this doctor-code flow existed, rerun the second migration so the new RPC, doctor codes, and profile visibility policy are applied.

## 3. Allow self-signup in Supabase Auth

In the Supabase dashboard:

1. Open `Authentication`
2. Open `Providers`
3. Make sure `Email` is enabled

For the smoothest development flow, either:

- disable email confirmation temporarily, or
- keep email confirmation enabled and make sure users confirm their email before signing in

## 4. Create accounts directly in the app

The Flutter app now supports self-signup for both roles.

When a user signs up:

- they choose `Patient` or `Doctor`
- the app sends `display_name` and `role` into Supabase Auth metadata
- the database trigger automatically creates the matching `profiles` row
- doctor accounts automatically receive an 8-character `doctor_link_code`

You no longer need to manually create test users just to get started.

## 5. Link doctor and patient through the app

After sign-up:

- doctors can see their own doctor link code on the doctor dashboard
- patients can enter that code from the patient home screen under `Care Team`
- the app calls `link_patient_to_doctor()` and creates the doctor-patient link

## 6. Optional manual linking for testing

After both users exist, use:

- `supabase/seed_test_accounts.sql`

Replace the placeholder UUIDs with the real auth user IDs and insert the
doctor-patient link manually if you want to bypass the code flow for testing.

## 7. Run the Flutter app

Start the app with:

```powershell
flutter run --dart-define=SUPABASE_URL=your-project-url --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

## Notes

- Patients can only read/write their own sessions.
- Doctors can only see patients explicitly linked to them.
- Patients can create their own account and link themselves to a doctor with a code.
- Doctors can create their own account and share their doctor code from the app.
- Only fused/final knee-angle graph samples are stored.
- No raw ADC or separate sensor-angle channels are uploaded.
