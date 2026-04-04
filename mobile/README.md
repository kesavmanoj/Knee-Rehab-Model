# Mobile Layer

## Why This Folder Exists

The mobile layer is where the embedded system becomes a usable rehabilitation product.

The firmware can measure angle, the calibration tools can validate and tune the sensors, but neither of those alone gives a patient a guided rehabilitation experience. The mobile app is the layer that translates engineering data into something a person can actually use during recovery.

This folder exists to hold that interface layer.

At a high level, the mobile side has three jobs:

- connect to the wearable system
- present the knee angle in a clear and useful way
- organize exercise sessions and recovery progress around that angle

## Place Of The Mobile App In The Whole System

The mobile app does not replace the embedded logic. It sits on top of it.

The data flow is:

- sensors measure physical motion
- the slave sends shin information to the master
- the master computes the phone-facing knee angle
- the phone receives that value over BLE
- the app turns it into feedback, session logic, and progress summaries

This means the app is not the source of truth for sensing. The boards are still the sensing system. The app is the interpretation and interaction layer.

## Design Philosophy

The app is being shaped around a patient-first model.

That means the main screens should answer simple questions:

- am I connected?
- what is my current knee angle?
- am I moving correctly?
- am I inside the intended exercise range?
- how many reps have I completed?
- how did this session go?

The app should not feel like a BLE debugging utility in normal use.

Technical information still matters, but it belongs in a dedicated debug area rather than the normal patient workflow.

## Current App Structure

The current Flutter app is organized into four conceptual spaces:

- Home
- Live
- Progress
- Debug

Each tab has a different responsibility.

### Home

Home is the operational entry point.

Its job is to make setup intuitive:

- scan for devices
- list discoverable devices
- connect to the right device
- show connection and telemetry health
- expose quick actions like zeroing and starting a session
- show the current knee angle in a simple summary card

Home is not meant to be graph-heavy. It is meant to help the user get ready.

### Live

Live is the exercise screen.

This is where the app becomes an actual rehab companion rather than just a connection tool.

Its responsibilities are:

- show the current knee angle prominently
- show whether the current angle is inside the target range
- visualize motion in a way that is easy to understand
- count repetitions according to the selected exercise logic
- show session metrics such as peak flexion, extension lag, speed, hold time, and duration

This is the tab that tries to deliver real-time biofeedback.

### Progress

Progress is the session-summary layer.

This part of the app is not trying to show every raw signal. Its purpose is to keep a memory of how the user performed over time.

Right now it stores session summaries locally in the app state, such as:

- which exercise was performed
- peak flexion
- extension lag
- rep count
- session duration

Long-term, this is the area that naturally grows into recovery trends and remote monitoring.

### Debug

Debug is intentionally kept separate and intentionally kept available.

It exists because this project is still under active development and hardware integration work is still happening. The debug view provides visibility into:

- BLE state
- characteristic payload information
- flags
- device discovery
- error messages

This tab is valuable for development, testing, and troubleshooting, but it should not define the overall feel of the app.

## Why The App Uses BLE The Way It Does

The app does not connect to both boards directly in the current architecture.

Instead:

- the slave talks to the master
- the master talks to the phone

The app connects only to the master.

That design keeps the mobile side simpler because the phone sees one device that already represents the system as a whole. It does not need to assemble thigh and shin data itself in the current setup.

The app therefore consumes a phone-facing BLE contract that is intentionally narrow:

- one main live angle value
- connection and validity flags
- a command path for zeroing and related controls

This is useful because the phone UI can evolve without forcing the user to understand the internal sensor topology.

## Current BLE App Logic

The mobile app does four important BLE jobs:

1. discovery
2. connection
3. telemetry polling
4. command writing

### Discovery

The app scans for the master board using the project’s BLE service UUID and advertised device identity.

That means the user does not need to know a MAC address or manually enter a board ID. The app simply looks for the correct device type.

### Connection

Once a device is chosen, the app connects and establishes access to the expected BLE characteristics.

This is where the app makes sure it is really talking to a compatible board and not just any BLE peripheral.

### Telemetry Polling

The app polls the current knee angle regularly. The update rate is chosen to balance two competing goals:

- the interface should feel live
- command writes and BLE stability must not be starved by over-aggressive polling

That balance is especially important because the master is already doing dual-role BLE.

### Command Writing

The app can send commands such as:

- zero leg
- reset zero

These commands do not implement angle logic themselves. They request the master firmware to update its zero reference state.

That is important because zeroing belongs in the embedded interpretation layer, not as a client-side visual trick.

## Exercise Logic In The App

The app is not only showing the current angle. It is also turning the angle stream into exercise logic.

That means the app has to decide:

- when a movement begins
- when a rep becomes valid
- whether the user held long enough
- whether the movement speed is meaningful
- when a rep is counted

This is why exercise profiles exist.

Different exercises do not behave the same way:

- some rely on flexion and return
- some rely on extension and release
- some need a longer hold
- some need a tighter angle window

The app therefore contains exercise-specific profiles rather than one universal rep detector.

## Why Rep Counting Lives In The App

Rep counting is a behavioral layer, not a sensing layer.

The boards should focus on:

- measuring angles reliably
- keeping BLE stable
- producing a trustworthy live signal

The app should focus on:

- interpreting that signal in the context of an exercise
- deciding when a movement counts
- presenting session feedback to the user

This separation keeps the embedded side leaner and the patient-facing side more adaptable.

## Live Visualization Philosophy

The app currently uses two main live visualization ideas:

- a large semicircular gauge
- a recent trend graph

The gauge answers:

- where am I now?

The graph answers:

- how am I moving over time?

Together, they are more useful than either alone.

The gauge provides immediate posture feedback.

The graph provides movement context:

- whether motion is smooth
- whether the user is reaching the target range
- whether the last few seconds show repetition behavior

## Why Smoothness Matters In The App

A rehabilitation interface that feels laggy creates two problems:

- it makes the device feel less trustworthy
- it makes exercise timing harder for the patient

But the answer is not just “increase BLE rate forever.”

Because the master is doing central and peripheral BLE roles simultaneously, a very aggressive data rate can actually hurt reliability.

So the app uses two layers of smoothness:

- transport updates at a practical BLE rate
- UI interpolation and animation between samples

This is why the app can be made to feel smoother without pushing the BLE link into instability.

## Relationship To The PC Tools

The mobile app and the PC tools are different products inside the same repo.

The PC tools are for:

- calibration
- validation
- engineering visibility

The mobile app is for:

- exercise flow
- live patient feedback
- session logic
- progress experience

That separation is intentional. The app should learn from the calibration tools, but it should not feel like one.

## Current State Of The Mobile Layer

The mobile layer is beyond a simple BLE demo now, but it is not yet a finished clinical application.

It already has:

- structured navigation
- exercise-aware logic
- live motion visualization
- progress summaries
- zeroing controls
- a preserved debug surface

What it does not yet fully have is a complete remote-monitoring product with cloud storage and clinician dashboards. Those are future layers that can grow on top of the current architecture.

## How To Think About This Folder

The easiest way to understand the mobile folder is:

- it is the interface translation layer
- it receives the embedded system’s live knee angle
- it transforms that angle into a user experience

The embedded system says:

- this is the angle now

The mobile app says:

- what does that mean for the user right now?

That is the role of this entire folder.
