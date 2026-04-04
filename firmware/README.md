# Firmware

This folder contains the active Arduino firmware for the two-board knee measurement system.

## Layout

```text
firmware/
├── master_node/
└── slave_node/
```

## Current Roles

### Slave

Entry point:

- [slave_node.ino](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/slave_node/slave_node.ino)

Current responsibilities:

- read the shin IMU
- fuse accelerometer + gyro into a segment angle
- advertise that angle over BLE
- keep a hardware watchdog alive only when BLE publishing is healthy

Key files:

- [slave_node/AppConfig.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/slave_node/AppConfig.h)
- [slave_node/BlePeripheralManager.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/slave_node/BlePeripheralManager.h)
- [slave_node/BlePeripheralManager.cpp](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/slave_node/BlePeripheralManager.cpp)
- [slave_node/ImuManager.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/slave_node/ImuManager.h)
- [slave_node/ImuManager.cpp](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/slave_node/ImuManager.cpp)
- [slave_node/ComplementaryFilter.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/slave_node/ComplementaryFilter.h)
- [slave_node/ComplementaryFilter.cpp](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/slave_node/ComplementaryFilter.cpp)
- [slave_node/BleProtocol.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/slave_node/BleProtocol.h)

### Master

Entry point:

- [master_node.ino](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/master_node.ino)

Current responsibilities:

- read the thigh IMU
- connect to the slave over BLE as a central
- compute the dual-IMU knee angle
- read:
  - flex sensor on `D0`
  - potentiometer on `D2`
- drive the SSD1306 OLED
- advertise a phone-facing BLE service as `KneeMaster`
- accept phone commands:
  - zero IMU
  - clear zero

Current serial output:

```text
SIMPLE,time_ms,master_imu_deg,slave_imu_deg,knee_imu_deg,flex_raw_adc,flex_angle_deg,pot_raw_adc,pot_angle_deg,ble_state
```

## Key Master Files

### BLE Central To Slave

- [master_node/BleCentralManager.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/BleCentralManager.h)
- [master_node/BleCentralManager.cpp](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/BleCentralManager.cpp)
- [master_node/BleProtocol.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/BleProtocol.h)

### Phone BLE Peripheral

- [master_node/PhoneBleProtocol.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/PhoneBleProtocol.h)
- [master_node/PhoneBlePeripheralManager.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/PhoneBlePeripheralManager.h)
- [master_node/PhoneBlePeripheralManager.cpp](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/PhoneBlePeripheralManager.cpp)

### IMU And Angle Processing

- [master_node/ImuManager.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/ImuManager.h)
- [master_node/ImuManager.cpp](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/ImuManager.cpp)
- [master_node/ComplementaryFilter.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/ComplementaryFilter.h)
- [master_node/ComplementaryFilter.cpp](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/ComplementaryFilter.cpp)
- [master_node/SegmentOrientationEstimator.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/SegmentOrientationEstimator.h)
- [master_node/SegmentOrientationEstimator.cpp](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/SegmentOrientationEstimator.cpp)

### Analog Sensor Path

- [master_node/AnalogChannel.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/AnalogChannel.h)
- [master_node/AnalogChannel.cpp](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/AnalogChannel.cpp)
- [master_node/MovingAverageFilter.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/MovingAverageFilter.h)
- [master_node/FlexSensorModel.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/FlexSensorModel.h)
- [master_node/FlexSensorModel.cpp](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/FlexSensorModel.cpp)
- [master_node/PotentiometerModel.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/PotentiometerModel.h)
- [master_node/PotentiometerModel.cpp](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/PotentiometerModel.cpp)

### OLED

- [master_node/OledDisplayManager.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/OledDisplayManager.h)
- [master_node/OledDisplayManager.cpp](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/OledDisplayManager.cpp)

### Configuration

- [master_node/AppConfig.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/AppConfig.h)

This file contains:

- timing intervals
- BLE retry and timeout values
- OLED address
- analog pin assignments
- IMU filter tuning
- flex electrical assumptions

## Wiring Summary

### Master

- `D0`: flex sensor analog input
- `D2`: potentiometer analog input
- OLED: SSD1306 I2C display at `0x3C`

### Slave

- uses only the onboard IMU and BLE

## Build Notes

Required Arduino libraries / core:

- Silicon Labs MG24 board package
- `ArduinoBLE`
- `LSM6DS3`
- `U8g2`
- `WatchdogTimer` from the Silicon Labs core

Recommended upload order:

1. Upload the slave.
2. Upload the master.
3. Power the slave first, then the master.
