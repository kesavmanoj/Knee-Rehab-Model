# Firmware

This folder contains the Arduino firmware for the two-board knee measurement system.

## Structure

```text
firmware/
├── master_node/
└── slave_node/
```

## System Roles

### `slave_node`

The slave is the shin-side board.

- reads its onboard IMU
- estimates segment orientation using a complementary filter
- advertises a BLE telemetry service
- notifies the master with orientation packets

Main entry:

- [slave_node.ino](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/slave_node/slave_node.ino)

### `master_node`

The master is the thigh-side board.

- reads its onboard IMU
- connects to the slave over BLE
- receives the slave IMU packet
- reads analog inputs
- drives the OLED
- publishes a unified serial stream used by the Python tools

Main entry:

- [master_node.ino](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/master_node.ino)

## Master Firmware Overview

The master is now a unified runtime and calibration sketch. One upload supports:

- OLED live display
- BLE shin-node reception
- flex sensor reading
- potentiometer reading
- runtime monitoring from Python
- POT calibration logging
- flex calibration logging
- IMU calibration logging

### Current Serial Records

The master emits:

- `RUNTIME_SAMPLE,time_ms,flex_raw_adc,flex_angle_deg,pot_raw_adc,pot_angle_deg,master_imu_deg,slave_imu_deg,imu_angle_deg`
- `FLEX_SAMPLE,time_ms,flex_raw_adc,flex_filtered_adc,flex_voltage,flex_resistance_ohms,flex_angle_deg,label_deg`
- `POT_SAMPLE,time_ms,pot_raw_adc,pot_filtered_adc,pot_voltage,pot_angle_deg,label_deg`
- `IMU_SAMPLE,time_ms,master_imu_deg,slave_imu_deg,imu_raw_knee_angle_deg,imu_angle_deg,label_deg`
- `LABEL_START,time_ms,label_deg,window_ms`
- `LABEL_END,time_ms,label_deg`

### Master Commands

Sent over USB serial:

- `h`: print help and current record formats
- `z`: zero the dual-IMU knee reference
- `r`: clear the IMU zero reference
- `0..145`: start a labeled capture window for calibration

### Master OLED

The OLED currently shows the same core IMU/BLE information it used to:

- master IMU angle
- slave IMU angle
- knee angle difference
- BLE state
- zeroed state

OLED helper:

- [OledDisplayManager.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/OledDisplayManager.h)
- [OledDisplayManager.cpp](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/OledDisplayManager.cpp)

## Key Master Files

### Configuration

- [AppConfig.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/AppConfig.h)

Holds:

- serial baud rate
- sample intervals
- OLED update interval
- BLE retry / timeout values
- ADC assumptions
- moving average window
- analog pin assignments
- IMU filter tuning
- flex sensor electrical assumptions
- fallback flex resistance-angle table

### Analog Input Pipeline

- [AnalogChannel.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/AnalogChannel.h)
- [AnalogChannel.cpp](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/AnalogChannel.cpp)
- [MovingAverageFilter.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/MovingAverageFilter.h)

Responsibilities:

- 12-bit ADC sampling
- moving-average smoothing
- conversion to filtered ADC and voltage

### Flex Model

- [FlexSensorModel.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/FlexSensorModel.h)
- [FlexSensorModel.cpp](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/FlexSensorModel.cpp)

Responsibilities:

- use the analog channel wrapper
- convert voltage to resistance using the configured divider model
- optionally map resistance through the fallback interpolation table

Important:

- current runtime flex angle used by the monitor comes from generated raw-ADC calibration in [CalibratedAngleModels.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/CalibratedAngleModels.h)
- the resistance-angle table in [AppConfig.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/AppConfig.h) is a fallback / starter model

### Potentiometer Model

- [PotentiometerModel.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/PotentiometerModel.h)
- [PotentiometerModel.cpp](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/PotentiometerModel.cpp)

Responsibilities:

- read the potentiometer analog input
- compute raw ADC, filtered ADC, voltage, and a simple linear angle

Current runtime monitor angle for POT comes from:

- [GeneratedCalibration.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/GeneratedCalibration.h)
- [CalibratedAngleModels.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/CalibratedAngleModels.h)

### IMU Processing

- [ImuManager.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/ImuManager.h)
- [ImuManager.cpp](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/ImuManager.cpp)
- [ComplementaryFilter.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/ComplementaryFilter.h)
- [ComplementaryFilter.cpp](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/ComplementaryFilter.cpp)
- [SegmentOrientationEstimator.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/SegmentOrientationEstimator.h)
- [SegmentOrientationEstimator.cpp](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/SegmentOrientationEstimator.cpp)

Responsibilities:

- access the onboard LSM6DS3
- compute accelerometer pitch and roll
- fuse gyro plus accelerometer into stable segment angles
- provide the primary angle used for knee computation

### BLE Central

- [BleCentralManager.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/BleCentralManager.h)
- [BleCentralManager.cpp](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/BleCentralManager.cpp)
- [BleProtocol.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/BleProtocol.h)

Responsibilities:

- scan for the slave
- connect and subscribe
- receive the orientation packet
- maintain connection state
- expose latest packet data to the main loop

### Runtime Calibration Layer

- [GeneratedCalibration.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/GeneratedCalibration.h)
- [CalibratedAngleModels.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/CalibratedAngleModels.h)

Responsibilities:

- hold generated runtime coefficients
- convert raw ADC values to calibrated angle values

Current policy:

- POT uses a generated linear fit from raw ADC
- Flex uses a generated quadratic fit from raw ADC
- IMU uses the measured dual-IMU knee angle directly at runtime

### Calibration Session Support

- [CalibrationSession.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/CalibrationSession.h)
- [CalibrationSession.cpp](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/CalibrationSession.cpp)

Responsibilities:

- track labeled capture windows
- start and end `LABEL_START` / `LABEL_END` windows
- support all calibration GUIs with one firmware stream

## Slave Firmware Overview

Key files:

- [slave_node.ino](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/slave_node/slave_node.ino)
- [AppConfig.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/slave_node/AppConfig.h)
- [ImuManager.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/slave_node/ImuManager.h)
- [ImuManager.cpp](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/slave_node/ImuManager.cpp)
- [ComplementaryFilter.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/slave_node/ComplementaryFilter.h)
- [ComplementaryFilter.cpp](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/slave_node/ComplementaryFilter.cpp)
- [BlePeripheralManager.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/slave_node/BlePeripheralManager.h)
- [BlePeripheralManager.cpp](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/slave_node/BlePeripheralManager.cpp)
- [BleProtocol.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/slave_node/BleProtocol.h)

Responsibilities:

- read the slave IMU
- compute orientation locally
- package orientation into the shared BLE payload
- notify the master repeatedly

## Pin and Hardware Assumptions

### Master

- `D0`: flex sensor analog input
- `D1`: spare / second flex channel placeholder
- `D2`: potentiometer analog input
- OLED: I2C SSD1306 `0x3C`

### Flex divider assumption

The code assumes:

- flex sensor from `3V3` to ADC node
- fixed resistor from ADC node to `GND`

With your current working setup, the fixed resistor value is configured as:

- `33k ohm`

## Build Notes

### Arduino IDE

Required:

- Silicon Labs XIAO MG24 board support
- `ArduinoBLE`
- `LSM6DS3`
- `U8g2`

### Upload sequence

1. Upload [slave_node.ino](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/slave_node/slave_node.ino)
2. Upload [master_node.ino](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/master_node.ino)

## Practical Notes

- The master firmware is intentionally serving multiple Python tools from one serial stream.
- If you change the record format in `master_node.ino`, make matching parser changes in the Python tools.
- If you recalibrate POT or flex, regenerate [GeneratedCalibration.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/GeneratedCalibration.h) and re-upload the master.
