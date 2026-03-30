# Real-Time Knee Joint Angle Measurement & Rehabilitation Assessment Using Sensor Fusion

## Overview
This project is a wearable knee rehabilitation monitoring system built around two **Seeed Studio XIAO MG24 Sense** boards. The current firmware establishes the full sensing pipeline needed before higher-level rehab analytics are added:

- dual-node IMU sensing
- BLE communication from shin node to thigh node
- local analog sensing on the master node
- zeroing / tare support
- modular signal-processing blocks
- a stable serial dashboard for debugging and validation

The long-term goal is to support:

- real-time knee angle monitoring
- peak flexion and extension lag metrics
- repetition counting
- exercise classification
- future lightweight ML or CNN-based rehab assessment

## Project Status
Current implemented phases:

- Phase 1: project architecture and modular file layout
- Phase 2: slave firmware with IMU orientation + BLE notify
- Phase 3: master firmware with BLE central, local IMU, flex sensor pipeline, potentiometer pipeline, moving average filtering, and zeroing

Not implemented yet:

- Phase 4 fused knee-angle decision layer
- Phase 5 rehab-oriented analytics and ML hooks

## Hardware
- 2x Seeed Studio XIAO MG24 Sense
- built-in LSM6DS3TR-C IMU on each board
- 2x flex sensors
- 1x potentiometer
- Arduino framework
- ArduinoBLE library

## Node Roles

### Slave Node
Mounted on the **distal / shin segment**.

- acts as a BLE Peripheral
- reads its built-in IMU
- estimates segment orientation using a complementary filter
- sends orientation packets to the master using BLE notifications

### Master Node
Mounted on the **proximal / thigh segment**.

- acts as a BLE Central
- reads its built-in IMU
- reads two flex sensors
- reads one potentiometer
- receives shin IMU telemetry from the slave
- calculates candidate knee-angle sources for later fusion

## Pin Assignments
This is the most important wiring table for the current firmware.

### Master Node Pin Map
These assignments are defined in [firmware/master_node/AppConfig.h](/c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/AppConfig.h).

| Signal | Current firmware pin | XIAO pad label | Notes |
|---|---|---|---|
| Flex Sensor 1 analog input | `D0` | `A0 / D0` | 12-bit ADC input |
| Flex Sensor 2 analog input | `D1` | `A1 / D1` | 12-bit ADC input |
| Potentiometer analog input | `D2` | `A2 / D2` | 12-bit ADC input |
| Built-in IMU | internal | LSM6DS3TR-C | no external wiring needed |
| USB serial | USB-C | onboard | used for dashboard and commands |
| BLE | internal radio | onboard | used to connect to slave |

### Slave Node Pin Map
The slave currently uses no external analog pins.

| Signal | Current firmware pin | Notes |
|---|---|---|
| Built-in IMU | internal | LSM6DS3TR-C |
| USB serial | USB-C | debug output and zero command |
| BLE notify | internal radio | sends shin orientation |

### Important Pin Notes
- On the Silicon Labs XIAO MG24 Arduino core, analog-capable pins are referenced as `D0`, `D1`, `D2`, etc.
- In hardware documentation these may also appear as `A0/D0`, `A1/D1`, `A2/D2`.
- The current firmware uses `D0`, `D1`, and `D2` because that matches the installed board core.
- If your final wiring changes, only update the constants in [firmware/master_node/AppConfig.h](/c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/AppConfig.h).

## Sensor Wiring Assumptions

### Flex Sensors
The current code assumes each flex sensor is part of a voltage divider:

- flex sensor connected on the **high side** to `3.3V`
- fixed resistor connected on the **low side** to `GND`
- ADC pin reads the midpoint voltage

Current fixed resistor assumptions:

- Flex 1 fixed resistor: `10,000 ohms`
- Flex 2 fixed resistor: `10,000 ohms`

If your divider is wired the opposite way, update:

- `kFlexSensorUsesHighSideDivider`

in [firmware/master_node/AppConfig.h](/c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/AppConfig.h).

### Potentiometer
The potentiometer is assumed to be read as a standard analog voltage:

- one end to `3.3V`
- one end to `GND`
- wiper to `D2`

The code maps ADC linearly to `0..315 degrees`.

## Current Signal Processing Design

### IMU Processing
Both nodes use:

- accelerometer + gyroscope complementary filtering
- lightweight angle estimation suitable for MG24 real-time use
- primary axis selection via config
- sign correction terms for mounting adjustment

Current IMU settings:

- sample period: `10 ms` (`100 Hz`)
- complementary filter alpha: `0.98`

### Flex Sensor Processing
Each flex channel currently uses:

1. `analogRead()` at 12-bit resolution
2. moving average filtering with window size `20`
3. ADC to voltage conversion using divisor `4095.0`
4. voltage-divider resistance calculation
5. 10-point piecewise linear interpolation from resistance to angle

Important:

- the code correctly uses `4095.0`, never `1023`
- the calibration table is still a **placeholder table**
- you should replace it with real measured resistance-angle points from your sensors

### Potentiometer Processing
The potentiometer path uses:

1. `analogRead()` at 12-bit resolution
2. moving average filtering with window size `20`
3. linear mapping from ADC to `0..315 degrees`

### Zeroing
The system supports user-triggered zeroing through serial commands.

When zeroing is triggered in full extension, the master stores offsets for:

- master IMU
- slave IMU
- flex sensor 1 angle
- flex sensor 2 angle
- potentiometer angle

All displayed angles are then reported relative to that zero reference.

## BLE Architecture

### Slave BLE Behavior
- advertises as `KneeSlaveShin`
- exposes a custom telemetry service
- exposes a notify characteristic carrying orientation data

### Master BLE Behavior
- scans for the slave service UUID
- connects as BLE central
- discovers the notify characteristic
- subscribes to notifications
- handles disconnect and reconnect automatically

### Shared BLE Packet
The packet format is defined in:

- [firmware/common/BleProtocol.h](/c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/common/BleProtocol.h)

Fields currently included:

- protocol version
- flags
- sequence number
- slave uptime
- zeroed primary segment angle
- fused pitch
- fused roll
- accelerometer pitch

## Knee Angle Strategy
The intended knee-angle approach for this system is:

1. estimate each segment angle relative to gravity
2. select the axis aligned with sagittal-plane knee motion
3. subtract thigh angle from shin angle
4. compare this IMU-derived angle against flex and potentiometer channels
5. later add a simple explainable fusion rule

In practical terms:

- `knee_angle ~= shin_segment_angle - thigh_segment_angle`

This works well when:

- both boards are mounted consistently
- the movement is mainly flexion/extension
- the primary axis and signs are tuned correctly

Known limitations:

- complementary filtering does not solve yaw
- accelerometer readings are disturbed during fast dynamic motion
- board mounting and soft tissue motion can introduce error

## Firmware Structure

```text
firmware/
├── common/
│   └── BleProtocol.h
├── master_node/
│   ├── master_node.ino
│   ├── AppConfig.h
│   ├── AnalogChannel.h/.cpp
│   ├── MovingAverageFilter.h
│   ├── FlexSensorModel.h/.cpp
│   ├── PotentiometerModel.h/.cpp
│   ├── ImuManager.h/.cpp
│   ├── ComplementaryFilter.h/.cpp
│   ├── SegmentOrientationEstimator.h/.cpp
│   ├── BleCentralManager.h/.cpp
│   └── BleProtocol.h
└── slave_node/
    ├── slave_node.ino
    ├── AppConfig.h
    ├── ImuManager.h/.cpp
    ├── ComplementaryFilter.h/.cpp
    ├── BlePeripheralManager.h/.cpp
    └── BleProtocol.h
```

### Master Module Responsibilities
- `master_node.ino`: main loop, scheduling, dashboard, serial commands, zeroing
- `AppConfig.h`: all tunable constants and pin assignments
- `AnalogChannel`: filtered ADC sampling wrapper
- `MovingAverageFilter`: reusable windowed averaging filter
- `FlexSensorModel`: flex voltage, resistance, interpolation, and angle
- `PotentiometerModel`: filtered ADC to angle conversion
- `ImuManager`: low-level local IMU reads
- `ComplementaryFilter`: 1-axis IMU fusion helper
- `SegmentOrientationEstimator`: thigh orientation estimation
- `BleCentralManager`: slave discovery, connect, subscribe, packet reception

### Slave Module Responsibilities
- `slave_node.ino`: main loop, scheduling, zeroing, debug output
- `AppConfig.h`: slave timing and IMU config
- `ImuManager`: low-level shin IMU reads
- `ComplementaryFilter`: IMU fusion helper
- `BlePeripheralManager`: BLE peripheral service, notify, reconnect advertising

## Serial Commands

### Slave Commands
- `z`: zero current slave IMU primary axis
- `r`: clear slave IMU zero offset
- `h`: print help

### Master Commands
- `z`: zero all currently observed channels
- `r`: clear all zero offsets
- `h`: print help

## Serial Dashboard
The master prints a fixed-width dashboard intended to stay visually stable in Serial Monitor.

Typical fields include:

- IMU relative angle
- zeroed thigh angle
- zeroed shin angle
- flex 1 angle
- flex 2 angle
- potentiometer angle
- raw ADC values
- flex resistances
- BLE state
- packet age / sequence

This makes it easier to debug:

- wiring problems
- reversed sensor directions
- noisy analog signals
- stale BLE packets
- poor zeroing conditions

## Build and Upload

### Required Arduino IDE Setup
- Arduino IDE 2.x
- Silicon Labs Arduino core
- board selected as `Seeed Studio XIAO MG24`
- `Tools > Protocol stack` set to `BLE (Arduino)`
- libraries installed:
  - `ArduinoBLE`
  - `LSM6DS3`

### Upload Order
1. Upload [firmware/slave_node/slave_node.ino](/c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/slave_node/slave_node.ino) to the shin node
2. Upload [firmware/master_node/master_node.ino](/c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/master_node.ino) to the thigh node
3. Open both serial monitors at `115200`
4. Confirm the master transitions from `SCAN` to `LIVE`

## Initial Bring-Up Checklist
1. Power both boards.
2. Confirm the slave prints orientation debug lines.
3. Confirm the master reports `BLE:LIVE`.
4. Move the shin board and watch the `SHIN` field.
5. Move the thigh board and watch the `THIGH` field.
6. Check that `IMU_REL` changes as expected when the boards rotate relative to each other.
7. Confirm `ADC1`, `ADC2`, and `POT` respond when analog sensors are connected.
8. Place the leg in full extension and send `z` from the master.

## Calibration Notes

### IMU Axis Tuning
If the wrong orientation axis responds to flexion/extension:

- change `kUsePitchAsPrimaryAxis`

If the sign is inverted:

- change `kPitchSign`
- change `kRollSign`
- if needed, also update `kPitchGyroSign` and `kRollGyroSign`

These are defined in:

- [firmware/master_node/AppConfig.h](/c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/AppConfig.h)
- [firmware/slave_node/AppConfig.h](/c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/slave_node/AppConfig.h)

### Flex Sensor Calibration
The current 10-point flex calibration table is only a starting placeholder.

For better results:

1. measure sensor resistance at known bend angles
2. replace the 10 table entries with your own values
3. keep points ordered by increasing resistance

### Potentiometer Calibration
The current potentiometer model is a simple linear map from:

- `0 ADC` -> `0 deg`
- `4095 ADC` -> `315 deg`

If your mechanical mounting does not use the full travel, you may later want:

- minimum ADC calibration
- maximum ADC calibration
- deadband or endpoint clamping

## Current Assumptions and Open Items
- master analog pins are currently `D0`, `D1`, `D2`
- flex divider assumes high-side flex sensor wiring
- flex calibration table is placeholder data
- IMU axis selection may need to be switched from pitch to roll depending on mounting
- the current code computes candidate angles but does not yet implement final fusion weighting

## Planned Next Steps
- Phase 4: simple, explainable fused knee-angle logic
- Phase 5: rehab metric hooks such as:
  - peak flexion tracking
  - extension lag tracking
  - repetition counting
  - exercise classification
  - future windowed feature extraction for ML

## Quick Reference

### Current Master Pins
- Flex 1: `D0`
- Flex 2: `D1`
- Potentiometer: `D2`

### Current Key Constants
- ADC divisor: `4095.0`
- moving average window: `20`
- potentiometer range: `0..315 deg`
- complementary filter alpha: `0.98`
- IMU sampling: `100 Hz`

## Authoring Note
This README reflects the current firmware state in this repository. If you change wiring or calibration later, update:

- [firmware/master_node/AppConfig.h](/c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/AppConfig.h)
- this `README.md`

