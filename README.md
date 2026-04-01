# Knee-Rehab-Model

Real-time knee rehabilitation measurement project using:

- 2x Seeed Studio XIAO MG24 Sense boards
- dual IMUs for thigh and shin segment orientation
- BLE for inter-node communication
- optional flex sensor and potentiometer analog channels
- Python calibration and runtime-monitor GUIs

This repository is organized into two main working areas:

- [firmware/README.md](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/README.md): Arduino firmware for the master and slave boards
- [tools/README.md](c:/Users/KESAV/Downloads/Knee-Rehab-Model/tools/README.md): Python tools for calibration, plotting, coefficient generation, and live monitoring

## Project Goal

The system is intended to measure knee flexion and extension in real time for rehabilitation monitoring. The long-term direction is to support:

- live knee angle tracking
- home-use rehab monitoring
- calibration workflows for multiple sensor types
- extension toward repetition counting, peak flexion, extension lag, and later analytics

## Current Architecture

### Slave Node

The slave board is mounted on the shin segment.

- reads its onboard IMU
- computes orientation locally with a complementary filter
- exposes orientation over BLE as a peripheral

### Master Node

The master board is mounted on the thigh segment.

- reads its onboard IMU
- connects to the slave over BLE as a central
- receives the slave IMU angle
- reads analog sensors such as:
  - flex sensor on `D0`
  - potentiometer on `D2`
- drives the SSD1306 OLED display
- streams serial records that the Python tools consume

## Current Working Modes

The master firmware currently supports a unified serial stream. One flashed sketch can serve:

- the live runtime monitor
- the flex calibration GUI
- the potentiometer calibration GUI
- the dual-IMU calibration GUI

The board emits machine-readable serial records such as:

- `RUNTIME_SAMPLE,...`
- `FLEX_SAMPLE,...`
- `POT_SAMPLE,...`
- `IMU_SAMPLE,...`
- `LABEL_START,...`
- `LABEL_END,...`

Each Python GUI listens only to the records it cares about and ignores the rest.

## Quick Start

### 1. Flash the boards

- Slave firmware: [slave_node.ino](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/slave_node/slave_node.ino)
- Master firmware: [master_node.ino](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/master_node.ino)

### 2. Install Python dependencies

Typical packages used by the tools:

```bash
pip install pyserial matplotlib numpy
```

`tkinter` is expected from the standard Windows Python install.

### 3. Launch the tool you need

- POT calibration: [launch_pot_calibration_gui.bat](c:/Users/KESAV/Downloads/Knee-Rehab-Model/launch_pot_calibration_gui.bat)
- Flex calibration: [launch_flex_calibration_gui.bat](c:/Users/KESAV/Downloads/Knee-Rehab-Model/launch_flex_calibration_gui.bat)
- IMU calibration: [launch_imu_calibration_gui.bat](c:/Users/KESAV/Downloads/Knee-Rehab-Model/launch_imu_calibration_gui.bat)
- Runtime monitor: [launch_runtime_monitor_gui.bat](c:/Users/KESAV/Downloads/Knee-Rehab-Model/launch_runtime_monitor_gui.bat)

### 4. Regenerate runtime calibration after POT or flex recalibration

Run:

- [generate_runtime_calibration.bat](c:/Users/KESAV/Downloads/Knee-Rehab-Model/generate_runtime_calibration.bat)

This updates:

- [GeneratedCalibration.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/GeneratedCalibration.h)
- [generated_runtime_calibration_summary.txt](c:/Users/KESAV/Downloads/Knee-Rehab-Model/calibration_sessions/generated_runtime_calibration_summary.txt)

Then re-upload the master sketch.

Important:

- POT uses a generated linear mapping from raw ADC to angle
- Flex uses a generated quadratic mapping from raw ADC to angle
- IMU currently uses the measured dual-IMU angle directly at runtime, with no runtime calibration fit applied

## Wiring Summary

### Master analog inputs

- Flex sensor input: `D0`
- Potentiometer input: `D2`

### OLED

The OLED is an SSD1306 `128x64` I2C display and is driven by the master firmware.

### Flex divider assumption

The firmware assumes:

- flex sensor on the high side to `3V3`
- fixed resistor on the low side to `GND`
- ADC node in the middle

Example:

```text
3V3 ---- Flex Sensor ----+---- D0
                         |
                       33k ohm
                         |
                        GND
```

### Potentiometer

```text
3V3 ----[ pot track ]---- GND
              |
            wiper
              |
              D2
```

## Repo Layout

```text
Knee-Rehab-Model/
├── firmware/
├── tools/
├── calibration_sessions/
├── knee_visualizer.py
├── generate_runtime_calibration.bat
├── launch_flex_calibration_gui.bat
├── launch_imu_calibration_gui.bat
├── launch_pot_calibration_gui.bat
└── launch_runtime_monitor_gui.bat
```

## Notes

- The OLED view is for embedded live feedback on the master node.
- The Python GUIs are the main workflow for calibration and live visualization on a PC.
- `calibration_sessions/` stores captured calibration logs and generated plots.
- `calibration_output/` can be used for extra exported analysis artifacts if needed later.

## Recommended Workflow

1. Flash the slave.
2. Flash the master.
3. Verify the master OLED shows:
   - master IMU
   - slave IMU
   - knee angle
   - BLE state
4. Calibrate POT if needed.
5. Calibrate flex if needed.
6. Regenerate runtime calibration.
7. Re-upload the master.
8. Use the runtime monitor GUI for live flex, pot, and IMU tracking.

## Documentation Map

For details, use:

- [firmware/README.md](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/README.md)
- [tools/README.md](c:/Users/KESAV/Downloads/Knee-Rehab-Model/tools/README.md)
