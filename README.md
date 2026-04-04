# Knee-Rehab-Model

Two-board knee measurement project built around Seeed Studio XIAO MG24 Sense boards.

Current active setup:

- `slave_node`: shin-side IMU BLE peripheral
- `master_node`: thigh-side IMU BLE central to the slave, BLE peripheral to the phone, OLED host, flex + potentiometer reader
- `mobile/knee_master_test_app`: Flutter phone test app for the master BLE service

## What Is Running Now

The current firmware is a simplified runtime build focused on:

- master/slave BLE connectivity
- dual-IMU knee angle measurement
- one flex sensor on `D0`
- one potentiometer on `D2`
- SSD1306 OLED display on the master
- phone connectivity through the master BLE service `KneeMaster`

The master currently prints a simple serial line:

```text
SIMPLE,time_ms,master_imu_deg,slave_imu_deg,knee_imu_deg,fused_knee_deg,flex_raw_adc,flex_angle_deg,pot_raw_adc,pot_angle_deg,ble_state
```

The master also supports auto-switched serial stream profiles for the PC tools:

- `stream runtime`
- `stream pot`
- `stream flex`
- `stream imu`
- `stream normal`

## Repo Layout

```text
Knee-Rehab-Model/
├── firmware/
├── tools/
├── mobile/
├── launchers/
├── calibration_sessions/
└── knee_visualizer.py
```

## Main Working Areas

- [firmware/README.md](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/README.md)
  Current master/slave firmware architecture and behavior
- [tools/README.md](c:/Users/KESAV/Downloads/Knee-Rehab-Model/tools/README.md)
  Python calibration and monitoring utilities kept for offline workflows
- [mobile/knee_master_test_app/README.md](c:/Users/KESAV/Downloads/Knee-Rehab-Model/mobile/knee_master_test_app/README.md)
  Flutter phone-side BLE test app

## Quick Start

1. Flash the slave:
   - [slave_node.ino](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/slave_node/slave_node.ino)
2. Flash the master:
   - [master_node.ino](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/master_node.ino)
3. Power the slave, then the master.
4. Check the master OLED for:
   - slave BLE state
   - phone BLE state
   - knee angle
5. Run the phone app from:
   - [run_flutter_knee_master_test_app.bat](c:/Users/KESAV/Downloads/Knee-Rehab-Model/launchers/run_flutter_knee_master_test_app.bat)

## Notes

- The firmware has been intentionally simplified for BLE stability and upcoming sensor-fusion work.
- Some older calibration utilities are still kept under `tools/` for future reuse, but they are no longer the center of the runtime path.
- The master and slave now both include recovery logic, and the slave uses the MG24 hardware watchdog.
