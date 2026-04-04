#pragma once

#include <Arduino.h>

namespace MasterConfig {

struct FlexCalibrationPoint {
  float resistanceOhms;
  float angleDeg;
};

static constexpr unsigned long kSerialBaud = 115200UL;

// Scheduling
static constexpr unsigned long kImuSampleIntervalMs = 5UL;          // 200 Hz
static constexpr unsigned long kAnalogSampleIntervalMs = 5UL;       // 200 Hz
static constexpr unsigned long kDashboardIntervalMs = 50UL;         // 20 Hz live serial stream for the laptop monitor
static constexpr unsigned long kOledUpdateIntervalMs = 500UL;       // 2 Hz
static constexpr unsigned long kBleRetryIntervalMs = 1000UL;        // reconnect pacing
static constexpr unsigned long kBlePacketTimeoutMs = 1000UL;        // stale-data timeout
static constexpr unsigned long kPhoneTelemetryIntervalMs = 50UL;    // 20 Hz phone refresh with the smaller final-angle payload
static constexpr unsigned long kDebugHeartbeatIntervalMs = 1000UL;  // once-per-second loop health report
static constexpr unsigned long kPotCalibrationCaptureWindowMs = 3000UL;  // label the next 3 s of POT samples after a numeric angle command
static constexpr unsigned long kConnectionStableTimeMs = 2000UL;    // require a continuously healthy slave link before clearing recovery
static constexpr unsigned long kConnectionResetTimeoutMs = 6000UL;  // reboot if the slave link never becomes stable
static constexpr uint8_t kConnectionResetDisconnectCount = 3U;       // reboot after repeated flaps during recovery

// ADC and analog assumptions
static constexpr float kAdcFullScale = 4095.0f;
static constexpr float kAnalogReferenceVoltage = 3.30f;
static constexpr size_t kAnalogMovingAverageWindow = 40;
static constexpr float kPotMaxAngleDeg = 315.0f;
static constexpr float kKneeAngleMinDeg = 0.0f;
static constexpr float kKneeAngleMaxDeg = 145.0f;

// First-pass fusion weights. IMU and POT are equal dominant contributors,
// while FLEX is a small corrective term.
static constexpr float kImuFusionBaseWeight = 0.475f;
static constexpr float kPotFusionBaseWeight = 0.475f;
static constexpr float kFlexFusionBaseWeight = 0.05f;

// OLED display
static constexpr uint8_t kOledI2cAddress = 0x3C;
static constexpr char kPhoneBleDeviceName[] = "KneeMaster";

// XIAO MG24 exposes analog-capable pads using D-pin names in the Silicon Labs core.
// Current simplified build uses one flex sensor on D0 and one potentiometer on D2.
static constexpr uint8_t kFlex1Pin = D0;
static constexpr uint8_t kPotPin = D2;

// IMU filter tuning and axis selection. Adjust signs once boards are mounted.
static constexpr uint8_t kImuI2cAddress = 0x6A;
static constexpr float kComplementaryAlphaMoving = 0.985f;
static constexpr float kComplementaryAlphaSettled = 0.90f;
static constexpr float kGyroQuietThresholdDps = 8.0f;
static constexpr float kGyroFastThresholdDps = 60.0f;
static constexpr bool  kUsePitchAsPrimaryAxis = true;
static constexpr float kPitchSign = 1.0f;
static constexpr float kRollSign = 1.0f;
static constexpr float kPitchGyroSign = 1.0f;
static constexpr float kRollGyroSign = 1.0f;

// Flex sensor divider assumptions.
// This code assumes:
//  - flex sensor is on the high side to 3.3 V
//  - fixed resistor is on the low side to GND
//  - ADC samples the divider midpoint
// If your circuit is wired differently, only the resistance formula needs to change.
static constexpr bool kFlexSensorUsesHighSideDivider = true;
static constexpr float kFlex1FixedResistorOhms = 33000.0f;

// Starter 10-point resistance->angle calibration for a flex sensor that is
// approximately 45k ohm when straight and 15k ohm when bent. The table must
// stay ordered by increasing resistance for the interpolation code.
static constexpr size_t kFlexCalibrationPointCount = 10;
static constexpr FlexCalibrationPoint kFlexCalibrationTable[kFlexCalibrationPointCount] = {
    {15000.0f, 145.0f},
    {18000.0f, 130.0f},
    {21000.0f, 115.0f},
    {24000.0f, 100.0f},
    {27000.0f, 85.0f},
    {30000.0f, 70.0f},
    {33000.0f, 55.0f},
    {37000.0f, 40.0f},
    {41000.0f, 20.0f},
    {45000.0f, 0.0f},
};

}  // namespace MasterConfig
