# Tools

This folder contains the PC-side tooling used to:

- capture calibration data from the master board
- label calibration windows
- save CSV logs
- generate plots and calibration summaries
- generate runtime calibration coefficients for firmware
- monitor live flex, POT, and IMU angles

These tools are still kept in the repo, but the active embedded runtime has been simplified and no longer depends on every calibration stage all the time.

## Structure

```text
tools/
└── calibration/
```

Everything currently lives under:

- [tools/calibration](c:/Users/KESAV/Downloads/Knee-Rehab-Model/tools/calibration)

## Main User-Facing Workflows

### POT Calibration

Launch:

- [launch_pot_calibration_gui.bat](c:/Users/KESAV/Downloads/Knee-Rehab-Model/launchers/launch_pot_calibration_gui.bat)

GUI:

- [pot_calibration_gui.py](c:/Users/KESAV/Downloads/Knee-Rehab-Model/tools/calibration/pot_calibration_gui.py)

What it does:

- connects to the master serial port
- listens for `POT_SAMPLE,...`
- shows live raw ADC, filtered ADC, voltage, and mapped POT angle
- lets you stamp angle labels
- stores samples and label events
- runs analysis and generates plots

### Flex Calibration

Launch:

- [launch_flex_calibration_gui.bat](c:/Users/KESAV/Downloads/Knee-Rehab-Model/launchers/launch_flex_calibration_gui.bat)

GUI:

- [flex_calibration_gui.py](c:/Users/KESAV/Downloads/Knee-Rehab-Model/tools/calibration/flex_calibration_gui.py)

What it does:

- connects to the same unified master serial stream
- listens for `FLEX_SAMPLE,...`
- shows live flex raw ADC, filtered ADC, voltage, resistance, and mapped angle
- lets you stamp labels
- stores calibration logs
- runs flex calibration analysis and plot generation

### Dual IMU Calibration

Launch:

- [launch_imu_calibration_gui.bat](c:/Users/KESAV/Downloads/Knee-Rehab-Model/launchers/launch_imu_calibration_gui.bat)

GUI:

- [imu_calibration_gui.py](c:/Users/KESAV/Downloads/Knee-Rehab-Model/tools/calibration/imu_calibration_gui.py)

What it does:

- listens for `IMU_SAMPLE,...`
- shows:
  - master IMU angle
  - slave IMU angle
  - raw dual-IMU knee angle
  - mapped IMU angle
- supports label windows
- stores IMU calibration logs

Important current project decision:

- the runtime firmware now uses the measured dual-IMU angle directly
- IMU runtime calibration is not required
- the IMU calibration GUI is still useful for validation, plotting, and comparison

### Runtime Monitor

Launch:

- [launch_runtime_monitor_gui.bat](c:/Users/KESAV/Downloads/Knee-Rehab-Model/launchers/launch_runtime_monitor_gui.bat)

GUI:

- [runtime_monitor_gui.py](c:/Users/KESAV/Downloads/Knee-Rehab-Model/tools/calibration/runtime_monitor_gui.py)

What it does:

- listens for `RUNTIME_SAMPLE,...`
- shows:
  - flex raw ADC and angle
  - POT raw ADC and angle
  - master IMU
  - slave IMU
  - IMU knee angle
- plots live traces with different colors

## Runtime Calibration Generator

Launch:

- [generate_runtime_calibration.bat](c:/Users/KESAV/Downloads/Knee-Rehab-Model/launchers/generate_runtime_calibration.bat)

Script:

- [generate_runtime_calibration.py](c:/Users/KESAV/Downloads/Knee-Rehab-Model/tools/calibration/generate_runtime_calibration.py)

What it does:

- finds the latest valid POT session
- finds the latest valid flex session
- computes:
  - a linear fit for POT raw ADC to angle
  - a quadratic fit for flex raw ADC to angle
  - a cubic flex fit for comparison only
- writes:
  - [GeneratedCalibration.h](c:/Users/KESAV/Downloads/Knee-Rehab-Model/firmware/master_node/GeneratedCalibration.h)
  - [generated_runtime_calibration_summary.txt](c:/Users/KESAV/Downloads/Knee-Rehab-Model/calibration_sessions/generated_runtime_calibration_summary.txt)

Current behavior:

- IMU is treated as direct measurement at runtime

## Internal Module Layout

### Shared Plot Widgets

- [plot_widgets.py](c:/Users/KESAV/Downloads/Knee-Rehab-Model/tools/calibration/plot_widgets.py)

Contains reusable Tk canvas widgets such as:

- single-trace live plots
- dual-trace live plots
- triple-trace live plots

### POT Modules

- [serial_protocol.py](c:/Users/KESAV/Downloads/Knee-Rehab-Model/tools/calibration/serial_protocol.py)
- [pot_serial_session.py](c:/Users/KESAV/Downloads/Knee-Rehab-Model/tools/calibration/pot_serial_session.py)
- [session_writer.py](c:/Users/KESAV/Downloads/Knee-Rehab-Model/tools/calibration/session_writer.py)
- [calibration_log_parser.py](c:/Users/KESAV/Downloads/Knee-Rehab-Model/tools/calibration/calibration_log_parser.py)
- [pot_calibration_analysis.py](c:/Users/KESAV/Downloads/Knee-Rehab-Model/tools/calibration/pot_calibration_analysis.py)
- [analyze_pot_calibration.py](c:/Users/KESAV/Downloads/Knee-Rehab-Model/tools/calibration/analyze_pot_calibration.py)

Responsibilities:

- parse `POT_SAMPLE`
- read serial data
- log samples and labels to CSV
- generate time plots and fit plots

### Flex Modules

- [flex_serial_protocol.py](c:/Users/KESAV/Downloads/Knee-Rehab-Model/tools/calibration/flex_serial_protocol.py)
- [flex_serial_session.py](c:/Users/KESAV/Downloads/Knee-Rehab-Model/tools/calibration/flex_serial_session.py)
- [flex_session_writer.py](c:/Users/KESAV/Downloads/Knee-Rehab-Model/tools/calibration/flex_session_writer.py)
- [flex_calibration_log_parser.py](c:/Users/KESAV/Downloads/Knee-Rehab-Model/tools/calibration/flex_calibration_log_parser.py)
- [flex_calibration_analysis.py](c:/Users/KESAV/Downloads/Knee-Rehab-Model/tools/calibration/flex_calibration_analysis.py)

Responsibilities:

- parse `FLEX_SAMPLE`
- capture flex logs
- compute flex fit summaries

### IMU Modules

- [imu_serial_protocol.py](c:/Users/KESAV/Downloads/Knee-Rehab-Model/tools/calibration/imu_serial_protocol.py)
- [imu_serial_session.py](c:/Users/KESAV/Downloads/Knee-Rehab-Model/tools/calibration/imu_serial_session.py)
- [imu_session_writer.py](c:/Users/KESAV/Downloads/Knee-Rehab-Model/tools/calibration/imu_session_writer.py)
- [imu_calibration_log_parser.py](c:/Users/KESAV/Downloads/Knee-Rehab-Model/tools/calibration/imu_calibration_log_parser.py)
- [imu_calibration_analysis.py](c:/Users/KESAV/Downloads/Knee-Rehab-Model/tools/calibration/imu_calibration_analysis.py)

Responsibilities:

- parse `IMU_SAMPLE`
- capture dual-IMU labeled sessions
- analyze raw knee angle against labeled angle

### Runtime Monitor Modules

- [runtime_serial_protocol.py](c:/Users/KESAV/Downloads/Knee-Rehab-Model/tools/calibration/runtime_serial_protocol.py)
- [runtime_monitor_session.py](c:/Users/KESAV/Downloads/Knee-Rehab-Model/tools/calibration/runtime_monitor_session.py)
- [runtime_monitor_gui.py](c:/Users/KESAV/Downloads/Knee-Rehab-Model/tools/calibration/runtime_monitor_gui.py)

Responsibilities:

- parse `RUNTIME_SAMPLE`
- ignore calibration traffic
- display the live multi-sensor state

### Fitting Utility

- [calibration_curve_fitter.py](c:/Users/KESAV/Downloads/Knee-Rehab-Model/tools/calibration/calibration_curve_fitter.py)

This is a small pure-Python polynomial fitting helper used so the generator can still run without depending on `numpy` for the fit step itself.

## Data Output

Calibration sessions are stored under:

- [calibration_sessions](c:/Users/KESAV/Downloads/Knee-Rehab-Model/calibration_sessions)

Typical session contents:

- `*_samples.csv`
- `*_label_events.csv`
- `serial_raw.log`
- generated plots
- `fit_summary.txt`

## Python Dependencies

Typical install:

```bash
pip install pyserial matplotlib numpy
```

Expected standard library pieces:

- `tkinter`
- `csv`
- `threading`
- `pathlib`

## Design Notes

- The tools are intentionally modular by sensor type.
- Each sensor type has the same basic shape:
  - serial protocol
  - serial session
  - session writer
  - log parser
  - analysis
  - GUI
- The runtime monitor is separate because it is not a labeling workflow.

This layout is meant to make future additions easier, for example:

- a second flex channel
- fused-angle calibration
- repetition annotations
- exercise window labeling
