# KneeMaster BLE Test App

This is a small Flutter app for Phase 3 phone testing.

It is intentionally narrow in scope:

- scan for `KneeMaster`
- connect to the master board
- subscribe to `Telemetry`
- subscribe/read `Status`
- show live values for IMU, flex, and potentiometer
- write `Zero IMU` and `Clear Zero` commands

## BLE Contract

This app targets the UUIDs defined in:

- [PHONE_APP_BLE_SPEC.md](c:/Users/KESAV/Downloads/Knee-Rehab-Model/PHONE_APP_BLE_SPEC.md)
- [PhoneBleProtocol.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/PhoneBleProtocol.h)

## App Structure

- `lib/src/ble/knee_ble_contract.dart`
  - service and characteristic UUIDs plus friendly names
- `lib/src/ble/knee_command.dart`
  - command enum and binary packet builder
- `lib/src/ble/knee_telemetry.dart`
  - telemetry and status packet parsers
- `lib/src/ble/ble_permissions.dart`
  - Android BLE permission requests
- `lib/src/ble/knee_ble_controller.dart`
  - scan, connect, subscribe, read, and write command logic
- `lib/src/ui/knee_home_screen.dart`
  - test UI for live values and command buttons

## First-Time Setup

1. Install Flutter on your PC and make sure `flutter` is on your `PATH`.
2. Install Android Studio or at least the Android SDK and platform tools.
3. On your phone:
   - enable Developer Options
   - enable USB debugging
   - connect by USB and accept the debugging prompt
4. In this app folder, run:

```powershell
flutter create --platforms=android .
flutter pub get
flutter devices
flutter run
```

`flutter create --platforms=android .` is important the first time because this repo only stores the custom app source and Android manifest/activity pieces we care about. Flutter will generate the remaining Android project files around them.

## Quick Run From Repo Root

You can also use:

- [run_flutter_knee_master_test_app.bat](c:/Users/KESAV/Downloads/Knee-Rehab-Model/launchers/run_flutter_knee_master_test_app.bat)

That launcher runs:

1. `flutter create --platforms=android .`
2. `flutter pub get`
3. `flutter run`

from the app folder.

## What To Expect In The UI

- connection card showing BLE and permissions state
- scan results list for `KneeMaster`
- live telemetry cards:
  - master IMU
  - slave IMU
  - IMU knee angle
  - flex raw ADC
  - flex angle
  - POT raw ADC
  - POT angle
- command buttons:
  - `Zero IMU`
  - `Clear Zero`

## Next Phase

Once this test app is stable, the next good steps are:

- add graphs
- add reconnect polish
- add packet-rate and stale-data indicators
- separate a cleaner clinician/patient UI from the low-level test screen
