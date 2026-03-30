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
static constexpr unsigned long kDashboardIntervalMs = 250UL;        // 4 Hz
static constexpr unsigned long kOledUpdateIntervalMs = 500UL;       // 2 Hz
static constexpr unsigned long kBleRetryIntervalMs = 1000UL;        // reconnect pacing
static constexpr unsigned long kBlePacketTimeoutMs = 1000UL;        // stale-data timeout

// ADC and analog assumptions
static constexpr float kAdcFullScale = 4095.0f;
static constexpr float kAnalogReferenceVoltage = 3.30f;
static constexpr size_t kAnalogMovingAverageWindow = 20;
static constexpr float kPotMaxAngleDeg = 315.0f;

// OLED display
static constexpr uint8_t kOledI2cAddress = 0x3C;

// XIAO MG24 exposes analog-capable pads using D-pin names in the Silicon Labs core.
// These are placeholder assignments until your final wiring is confirmed.
static constexpr uint8_t kFlex1Pin = D0;
static constexpr uint8_t kFlex2Pin = D1;
static constexpr uint8_t kPotPin = D2;

// IMU filter tuning and axis selection. Adjust signs once boards are mounted.
static constexpr uint8_t kImuI2cAddress = 0x6A;
static constexpr float kComplementaryAlphaMoving = 0.985f;
static constexpr float kComplementaryAlphaSettled = 0.90f;
static constexpr float kGyroQuietThresholdDps = 8.0f;
static constexpr float kGyroFastThresholdDps = 60.0f;
static constexpr bool kUsePitchAsPrimaryAxis = false;
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
static constexpr float kFlex1FixedResistorOhms = 10000.0f;
static constexpr float kFlex2FixedResistorOhms = 10000.0f;

// Placeholder 10-point resistance->angle calibration.
// Replace with measured values from your actual sensors once you characterize them.
static constexpr size_t kFlexCalibrationPointCount = 10;
static constexpr FlexCalibrationPoint kFlexCalibrationTable[kFlexCalibrationPointCount] = {
    {10000.0f, 0.0f},
    {12000.0f, 10.0f},
    {14500.0f, 20.0f},
    {17500.0f, 30.0f},
    {21000.0f, 45.0f},
    {25500.0f, 60.0f},
    {31000.0f, 75.0f},
    {38000.0f, 95.0f},
    {46000.0f, 115.0f},
    {55000.0f, 135.0f},
};

}  // namespace MasterConfig
