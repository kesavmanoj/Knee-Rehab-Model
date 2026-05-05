# Knee Rehab Mobile App

This Flutter app now has two roles in one mobile client:

- `patient`
- `doctor`

Patients use the live BLE device workflow:

- log in
- connect to `KneeMaster`
- run exercise sessions
- upload session summaries and fused-angle graph samples
- review their own progress history

Doctors use the same app to:

- log in
- see only assigned patients
- open patient session history
- review per-session summary metrics
- view stored fused-angle motion graphs

## Backend Requirements

This app now depends on Supabase for:

- authentication
- role resolution
- doctor-patient access control
- session storage
- fused-angle graph storage

See:

- `supabase/README.md`

## Runtime Configuration

Run the app with:

```powershell
flutter run --dart-define=SUPABASE_URL=your-project-url --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

If those values are missing, the app will stop at a configuration screen instead of booting into BLE mode.

## Current Architecture

### Patient Flow

The patient shell still contains:

- Home
- Live
- Progress
- Debug

The BLE connection remains patient-only. Patients connect to the master board, receive the final knee angle, and use that for:

- live display
- rep counting
- session metrics
- session graph capture

At session end, the app uploads:

- exercise metadata
- rep count
- peak flexion
- extension lag
- duration
- fused/final angle graph samples only

No raw ADC and no separate sensor-angle channels are uploaded.

### Doctor Flow

The doctor shell is read-only in v1.

Doctors can:

- see assigned patients
- open patient session history
- review session metrics
- review stored fused-angle motion graphs

Doctors cannot yet:

- edit exercise plans
- write notes
- manage patients

## Local Retry Queue

If a patient finishes a session while cloud upload fails, the app stores that session locally as a pending upload and retries it later when the patient logs in again or triggers sync.

This keeps the live rehab workflow usable even if the backend is temporarily unavailable.
