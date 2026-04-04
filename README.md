# Knee Rehab Model

## Project Purpose

This project is a wearable knee rehabilitation measurement system. Its purpose is to measure knee range of motion in a way that is practical outside a lab, understandable to a patient, and useful to a clinician.

The central idea is simple:

- one sensor board sits on the thigh
- one sensor board sits on the shin
- both segment motions are measured
- the system estimates knee angle from those segment measurements
- additional sensors provide supporting measurements
- the result is shown on an OLED, sent to a phone app, and exposed to PC calibration tools

The project is designed around home rehabilitation use. That means the system is not only trying to measure angle. It is also trying to be:

- stable enough to reconnect when something goes wrong
- simple enough to calibrate without changing firmware every time
- modular enough to evolve from raw sensing to clinically useful analytics

## High-Level Architecture

The whole system is split into four major layers:

1. Embedded firmware
2. PC-side calibration and monitoring tools
3. Mobile app
4. Stored calibration sessions and generated calibration coefficients

These layers are connected, but each has a separate job.

### 1. Embedded Firmware

The firmware is the real-time sensing layer.

There are two boards:

- the slave board
- the master board

The slave board lives on the shin and has one main job: measure the shin segment angle and advertise it over BLE.

The master board is the hub. It:

- measures the thigh segment angle
- connects to the slave board over BLE
- computes the knee angle from the two segment angles
- reads the flex sensor
- reads the potentiometer
- computes a fused knee estimate
- drives the OLED
- sends a phone-facing BLE telemetry stream to the app
- exposes serial streams for calibration and laptop monitoring

The master is therefore the place where the project comes together.

### 2. PC-Side Tools

The tools folder contains the calibration and runtime-monitoring layer.

These tools are responsible for:

- capturing labeled data for each sensor
- visualizing live signals
- fitting calibration curves
- generating the runtime coefficients used by the firmware

The firmware no longer needs to be swapped for each tool. Instead, the master now supports multiple serial stream profiles. Each GUI tells the board which stream it wants.

That design decision matters because it keeps the workflow modular:

- the same firmware can support runtime use
- the same firmware can support POT calibration
- the same firmware can support flex calibration
- the same firmware can support IMU validation

without constant reflashing.

### 3. Mobile App

The mobile app is the patient-facing and exercise-facing interface.

At the moment, the app is still a structured prototype rather than a finished clinical product, but its role is already clear:

- find the master board
- connect to it over BLE
- receive the current knee angle
- let the user zero the system
- guide the user through an exercise session
- track reps and session summaries
- separate the normal patient interface from the technical debug interface

The app is intentionally moving away from being a BLE test screen and toward being a rehab interface.

### 4. Calibration Sessions And Generated Coefficients

Every calibration session produces data. That data is stored so it can be reviewed, plotted, and converted into firmware coefficients.

This layer matters because the system mixes two kinds of knowledge:

- physics and geometry from the IMUs
- empirical calibration from the flex sensor and potentiometer

The calibration session folders preserve the evidence behind those mappings.

## Why Two Boards Are Used

The knee angle is not measured directly from a single segment. It is measured from the relationship between two segments:

- the thigh
- the shin

Each IMU measures the orientation of one segment. The knee angle is then derived from the difference between those segment orientations.

This is why the system uses a slave and a master rather than a single board. A single IMU can describe one segment well, but it cannot by itself describe the relative bend between thigh and shin.

## Current Sensing Logic

The system currently uses three sensing families:

- dual IMUs
- potentiometer
- flex sensor

### Dual IMUs

This is the primary knee-angle path.

Each IMU measures motion with accelerometer and gyroscope data. A complementary filter is used to combine:

- the short-term responsiveness of the gyro
- the long-term stability of the accelerometer

That produces a stable segment angle on each board.

The master then computes knee angle as the relative angle between:

- the master segment angle
- the slave segment angle

This is the most physically meaningful path in the current system, and it is also the angle that is currently sent to the phone as the main live value.

### Potentiometer

The potentiometer is treated as an additional angle observer. It is useful because it gives a direct analog measurement that can help ground the fused estimate.

The potentiometer path is:

- raw ADC read
- filtering
- conversion to angle using generated runtime calibration coefficients

This is why recalibrating the POT and regenerating runtime calibration changes the runtime behavior.

### Flex Sensor

The flex sensor is another supporting observer. Its behavior is more nonlinear than the potentiometer, so it depends more strongly on empirical fitting.

Its path is:

- raw ADC read
- filtering
- voltage estimation
- resistance estimation
- mapping to angle

At runtime, its angle mapping is derived from the generated calibration model.

## Current Fusion Logic

The system does not treat all sensors equally.

Right now the fusion model is intentionally simple and interpretable:

- IMU has major weight
- POT has major weight
- flex has minor weight

The purpose of that choice is to let the system benefit from multiple signals without hiding the logic inside a black-box model.

The fused result is computed on the master. Even when the phone currently only receives the IMU-based final angle, the master still computes the fused estimate locally so the fusion path can be tuned and observed.

## BLE Architecture

The BLE architecture is one of the most important ideas in the project.

There are two BLE relationships:

1. Slave to master
2. Master to phone

### Slave To Master

The slave acts as a BLE peripheral.

The master acts as a BLE central.

The slave publishes its segment angle. The master subscribes to that data and uses it to compute the knee angle.

### Master To Phone

The master also acts as a BLE peripheral for the phone.

The phone app acts as a BLE central.

This means the master is doing two BLE jobs at once:

- central to the slave
- peripheral to the phone

That dual-role design is powerful, but it is also one of the main sources of engineering complexity in this project. A lot of the debugging work in this repo has been about making that architecture stable enough for real use.

## Reliability Strategy

This project is not just about measurement accuracy. It is also about recovery behavior.

Because the boards are wearable and battery-powered, failures are realistic:

- the slave can lose power
- BLE can flap
- a board can get stuck
- a phone can disconnect

So the firmware includes recovery logic such as:

- reconnect handling
- reset commands
- watchdog behavior
- guarded clearing of stale links

The goal is not to pretend the system will never fail. The goal is to make it recover predictably when it does.

## Serial Stream Profiles

The master firmware exposes several serial personalities. This is one of the key design decisions in the current project.

Instead of reflashing different sketches for different workflows, the board can switch modes:

- normal
- runtime
- pot
- flex
- imu

The PC tools use this automatically.

That means:

- the runtime monitor asks for the runtime stream
- the POT GUI asks for the POT stream
- the flex GUI asks for the flex stream
- the IMU GUI asks for the IMU stream

This keeps the current setup modular and much easier to maintain.

## Calibration Workflow

The calibration workflow follows a repeatable pattern.

### POT Calibration

The operator opens the POT calibration GUI, captures labeled angle windows, and stores a session. Later, the runtime calibration generator fits a linear mapping from raw ADC to angle.

### Flex Calibration

The operator opens the flex calibration GUI, captures labeled angle windows, and stores a session. The generator later fits a nonlinear model for the flex sensor.

### IMU Calibration

The IMU calibration GUI is now mainly for validation and analysis rather than runtime correction. The runtime system uses the direct measured dual-IMU angle, but the IMU tool is still useful for verifying how well the raw IMU knee angle aligns with labeled positions.

### Runtime Calibration Generation

The generator pulls the latest valid POT and flex sessions and writes generated coefficients into the firmware header used by the master at runtime.

That means the calibration process is data-driven:

- capture session
- analyze session
- generate coefficients
- upload firmware

## Mobile App Philosophy

The app is moving toward a patient-first design.

That means the default experience should answer:

- am I connected?
- what is my current knee angle?
- am I inside the target range?
- what exercise am I doing?
- how many reps have I done?

It should not require the user to think in terms of:

- UUIDs
- raw packet structures
- BLE internals
- MTU sizes

That technical information still exists, but it belongs in the Debug tab, not in the main rehab flow.

## Current Project State

The project currently has a working end-to-end loop:

- sensors read on the boards
- slave communicates with master
- master computes knee angle and sensor values
- OLED shows live data
- phone connects to the master
- app shows live angle and session logic
- PC tools can calibrate and monitor the system

This means the repo is already beyond a raw hardware experiment. It now behaves like a real multi-layer system:

- embedded sensing
- wireless transport
- calibration tooling
- mobile interaction

## What Still Matters Going Forward

The most important future direction is not adding more random features. It is making the existing architecture more clinically meaningful.

The next major ideas in this project are:

- better sensor-fusion behavior
- more exercise-specific analytics
- clearer patient biofeedback
- longitudinal recovery tracking
- eventually, clinician-facing dashboards or remote review

The repo is already structured for that evolution. The firmware, tools, and app are separate enough that each part can grow without rewriting the entire project every time.

## Mental Model For The Whole System

If someone new is trying to understand the project, the easiest mental model is:

- the slave measures the shin
- the master measures the thigh and becomes the hub
- the master combines all sensor information
- the PC tools help calibrate and validate
- the phone app turns the measurement into a rehab experience

Everything in the repo exists to support one of those five statements.
