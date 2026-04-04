# Firmware Architecture

This directory contains the embedded side of the project: the code that runs on the wearable sensor nodes themselves. The firmware is responsible for turning raw motion and sensor data into a stable stream of knee-rehabilitation information that can be shown on the OLED, consumed by the phone app, and recorded by the calibration and monitoring tools on the laptop.

The most important idea in this firmware is that the system is split into two physical roles rather than trying to make one board do all sensing alone. One board sits on the thigh and acts as the main coordinator. The other board sits on the shank and acts as a remote measurement node. This split is what allows the project to estimate knee flexion as a relative angle between body segments rather than as a single local sensor reading.

## Why There Are Two Firmware Programs

The system is built around two boards because the knee is a joint between two moving segments. Measuring only one segment does not tell the full story. The firmware therefore separates the problem into:

- a master node on the thigh
- a slave node on the shank

The slave has one job: estimate the orientation of the lower leg and make that estimate available to the master over BLE.

The master has the larger role. It reads its own thigh-side IMU, reads the additional local sensors such as the flex sensor and potentiometer, receives the slave’s angle, computes knee-related outputs, drives the OLED, exposes the phone-facing BLE service, and produces serial streams for the PC tools.

This division keeps the system conceptually clean:

- the slave represents the shank
- the master represents the thigh and the system state as a whole

## The Slave Firmware

The slave firmware is the simpler of the two programs. It exists to do one thing reliably: measure the orientation of the lower leg and publish that result to the master.

At runtime, the slave repeatedly:

1. reads its IMU
2. filters the raw accelerometer and gyroscope data
3. produces one stable segment angle
4. advertises itself as a BLE peripheral
5. publishes that angle to the master whenever the master is connected

Conceptually, the slave should be thought of as a remote angle sensor rather than as a second independent device with complicated business logic. Its job is to be simple, steady, and recoverable.

Because BLE connection instability was one of the major pain points during development, the slave firmware also includes aggressive recovery behavior. If the link quality is not healthy enough for steady publishing, the slave can reset itself using the hardware watchdog. This is intentional. In this project, a clean reboot is often more reliable than trying to partially recover a wedged BLE state in software.

## The Master Firmware

The master firmware is where the system comes together.

It has to combine several responsibilities at once:

- read the thigh-side IMU
- receive the shank-side angle from the slave
- read the local analog sensors
- compute knee-angle outputs
- show a useful subset of information on the OLED
- provide serial output for calibration and runtime inspection
- expose a phone-facing BLE service

This makes the master the system orchestrator. It is not just another sensor board. It is the point where sensing, fusion, feedback, communication, and user control meet.

The master runs a loop that continuously balances:

- local sensing
- slave-link maintenance
- phone communication
- display updates
- serial streaming
- recovery behavior

That balancing act is why the master firmware is the most sensitive part of the entire project. The master is the only part of the system that must live in two BLE worlds at the same time:

- it is a BLE central toward the slave
- it is a BLE peripheral toward the phone

That dual-role behavior is central to the architecture, but it is also the main source of complexity.

## How Knee Angle Is Computed

The primary physical idea is simple: knee flexion is the angle between the thigh and shank.

The firmware turns that idea into a practical computation by:

- estimating the thigh segment angle on the master
- estimating the shank segment angle on the slave
- subtracting one from the other

That relative angle is the IMU-based knee estimate.

This is the backbone of the system. Even when other sensors are present, the dual-IMU geometry is the main biomechanical measurement path because it captures the relative motion of the two body segments directly.

The project also supports zeroing. Zeroing does not mean the sensors suddenly become different sensors. It simply means the system stores the current orientation relationship as a reference point and then reports subsequent motion relative to that reference. This is useful during setup because it lets the patient or clinician establish a known starting posture before beginning an exercise session.

## How The IMU Processing Works

Each IMU is not used in a completely raw form. The firmware first turns raw accelerometer and gyroscope values into a stable segment-angle estimate.

The key idea here is complementary filtering. Accelerometers provide a gravity-referenced estimate, which is useful in the long term but noisy in motion. Gyroscopes provide responsive rotational change, which is useful in the short term but drifts over time. The complementary filter blends those two behaviors:

- fast short-term responsiveness from the gyroscope
- slow long-term correction from the accelerometer

This gives the project a practical middle ground between raw data and a more complex estimator. The firmware therefore treats the IMU angle as a filtered orientation signal, not as a single unprocessed sensor reading.

The code also allows a primary axis choice. In practice, this matters because the physical mounting of the board determines whether pitch or roll better represents knee motion. That choice is configured rather than assumed.

## How The Analog Sensors Fit In

The master also reads two local supporting sensors:

- a flex sensor
- a potentiometer

These are not duplicates of the IMU path. They exist for a different reason: to provide independent mechanical references that can support or correct the motion estimate.

The flex sensor and potentiometer each start as raw ADC readings. Those raw readings are not directly meaningful in a clinical sense. The firmware has to map them into angle-like quantities first. That is why calibration exists.

After calibration:

- the flex sensor becomes a mapped estimate of knee angle
- the potentiometer becomes a mapped estimate of knee angle

These sensors are then available as supporting channels alongside the IMU angle. They are useful both for live comparison and for future fusion refinement.

## How Sensor Fusion Fits In

The firmware includes a local fusion stage on the master. The purpose of this stage is not to replace the IMU path blindly, but to combine multiple measurement sources into a more robust final estimate.

Right now, the master computes:

- an IMU-based knee angle
- a flex-based angle
- a potentiometer-based angle
- a fused angle

The current design philosophy is:

- the IMU path is the main geometric measurement
- the potentiometer is a strong secondary observer
- the flex sensor is a lighter supporting observer

This is why the fusion weights currently give most of the influence to the IMU and potentiometer, with much less weight given to the flex sensor. That weighting is not arbitrary; it reflects the project’s present confidence in the different sensing modalities.

An important architectural detail is that the firmware can compute more than it transmits. For example, the phone BLE contract is intentionally narrower than the full internal state of the master. This keeps the mobile interface simpler while allowing the firmware to evolve internally.

## BLE Architecture Inside The Firmware

There are two different BLE relationships in the firmware, and it is important not to confuse them.

### Slave To Master BLE

This link exists only to move the shank segment angle from the slave to the master.

In this relationship:

- the slave is the BLE peripheral
- the master is the BLE central

The master scans for the slave, connects, discovers the characteristic it needs, subscribes to updates, and keeps track of packet freshness. If the link goes stale, the master knows that the shank data is no longer trustworthy.

### Master To Phone BLE

This link exists to expose a phone-friendly summary of the system.

In this relationship:

- the master is the BLE peripheral
- the phone app is the BLE central

The phone does not need to understand the entire internal structure of the firmware. It only needs a stable, intentional contract that the app can build around. That is why the phone-facing BLE protocol lives as its own packet definition and command set.

This separation is important architecturally. The slave-master link is an internal machine-to-machine link. The master-phone link is a user-facing application link. They solve different problems and should remain conceptually separate even though they share the same master board.

## Why The Master Firmware Is More Fragile Than The Slave Firmware

The slave is simpler because it has a single BLE role and a single sensing purpose.

The master is more fragile because it must:

- maintain a BLE central link to the slave
- remain discoverable and usable by the phone
- stream serial data for tools
- drive an OLED
- continue local sensing and processing

That makes the master the part of the system most likely to suffer from timing contention, BLE congestion, and edge-case behavior when links drop. Much of the recent development work was about reducing unnecessary traffic, simplifying the phone payload, and making recovery behavior more predictable.

## The OLED’s Role In The Firmware

The OLED is not the primary output channel of the project, but it is extremely useful as a local sanity-check display.

The current display philosophy is simple:

- show the master segment angle
- show the slave segment angle
- show the relative IMU knee angle
- show connection state
- show whether zeroing is active
- show a few compact status indicators

The OLED is there to answer the question: “Is the system alive and behaving sensibly right now?” It is not intended to be a full rehabilitation interface. That is the role of the mobile app and PC tools.

Because I2C displays can hang in embedded systems, the OLED path is treated defensively. The firmware includes timeout and recovery behavior rather than assuming every redraw will always succeed.

## Serial Output Philosophy

The serial interface has two different audiences:

- humans reading the Serial Monitor
- software tools on the laptop

Those audiences want different things. Humans want readable, slower output. Tools want denser, purpose-specific streams. The firmware therefore uses serial stream profiles rather than forcing one log format to do everything.

The master can switch its serial behavior depending on the task:

- normal readable runtime output
- faster runtime stream for the live monitor
- dedicated calibration streams for POT, flex, or IMU workflows

This is why the same unified firmware can support multiple PC tools without reflashing. The firmware changes its serial behavior on command rather than changing its entire identity.

That design is one of the most important quality-of-life improvements in the project because it keeps calibration, monitoring, and everyday debugging inside one coherent runtime.

## How Calibration Fits Into The Firmware

Calibration exists because raw sensor values are not automatically useful as biomechanical quantities.

For the analog sensors in particular, the firmware needs a mapping from electrical measurement to angle. That mapping is learned offline using the calibration tools, then turned into generated coefficients that the firmware uses at runtime.

The high-level calibration loop is:

1. collect labeled data from the live system
2. fit a mapping on the laptop
3. generate runtime constants
4. compile those constants back into the firmware

This keeps the embedded runtime lightweight while still allowing the mapping itself to be data-driven.

In other words, the firmware does not “figure out” the calibration during normal operation. Instead, it consumes the result of a calibration workflow that happened outside the board.

## Why The Firmware Uses Generated Calibration Data

Generated calibration is a practical compromise.

If the board had to perform all fitting logic internally, the embedded code would become more complex, slower, and harder to trust. Instead, the fitting is done offline on the laptop, and the runtime simply receives the distilled result as constants.

That makes the embedded system easier to reason about:

- the runtime behavior is deterministic
- the calibration can be regenerated whenever needed
- the calibration math stays inspectable

This is especially important when working with rehabilitation hardware because reproducibility matters more than cleverness.

## Recovery And Watchdog Strategy

The firmware does not assume BLE will always recover gracefully.

Instead, the recovery philosophy is intentionally pragmatic:

- if a local recovery is simple and reliable, do it
- if the system is wedged, reset cleanly

The slave uses a real hardware watchdog because it is better to reboot than to remain stuck in a broken connection state indefinitely.

The master also includes recovery-oriented behavior, but it must be more selective because it carries more system state and more user-facing responsibilities. The serial reset command exists for the same reason: during bring-up and troubleshooting, a clean reboot is often the fastest path back to a known state.

This project has repeatedly shown that partial BLE recovery is not always safer than a full reset. The firmware design reflects that reality.

## Configuration Philosophy

Most of the important tuning decisions live in configuration headers rather than being scattered invisibly through the code.

This includes things like:

- sensor timing
- BLE cadences
- filter choices
- selected IMU axis
- serial output rates
- watchdog thresholds
- display behavior

This separation matters because rehabilitation firmware is not just code, it is a system with physical assumptions. By keeping those assumptions visible and centralized, the project becomes easier to retune as the hardware placement, exercise protocol, or mobile interface evolves.

## The Firmware As A Whole

The firmware should be thought of as a layered system:

1. physical sensing
2. local filtering and signal conditioning
3. cross-segment angle construction
4. supporting analog estimation
5. fusion and selection of outputs
6. communication to phone, laptop tools, and OLED
7. defensive recovery behavior

That layered structure is what makes the project manageable. Without it, the code would feel like a collection of unrelated sensor reads and BLE callbacks. With it, the purpose of each part is clearer:

- the slave exists to represent the shank
- the master exists to assemble system meaning
- calibration exists to make analog sensors interpretable
- BLE exists to move information to where it is needed
- the OLED exists for local confidence
- watchdogs exist because recovery matters as much as measurement

Seen that way, the firmware is not just “the code on the boards.” It is the part of the project that turns raw body motion into a structured, recoverable, clinically meaningful signal path.
