#pragma once

#include <Arduino.h>

namespace SlaveConfig {

static constexpr char kDeviceName[] = "KneeSlaveShin";
static constexpr unsigned long kSerialBaud = 115200UL;

// Scheduling
static constexpr unsigned long kImuSampleIntervalMs = 5UL;      // 200 Hz
static constexpr unsigned long kBleNotifyIntervalMs = 10UL;     // 100 Hz
static constexpr unsigned long kSerialDebugIntervalMs = 200UL;  // 5 Hz

// Complementary filter tuning
static constexpr float kComplementaryAlphaMoving = 0.985f;
static constexpr float kComplementaryAlphaSettled = 0.90f;
static constexpr float kGyroQuietThresholdDps = 8.0f;
static constexpr float kGyroFastThresholdDps = 60.0f;
static constexpr bool kUsePitchAsPrimaryAxis = false;

// Mounting correction terms. Adjust signs once the boards are physically mounted.
static constexpr float kPitchSign = 1.0f;
static constexpr float kRollSign = 1.0f;
static constexpr float kPitchGyroSign = 1.0f;
static constexpr float kRollGyroSign = 1.0f;

// LSM6DS3TR-C I2C address on the XIAO MG24 Sense.
// If your board package exposes a different IMU driver, only ImuManager needs to change.
static constexpr uint8_t kImuI2cAddress = 0x6A;

}  // namespace SlaveConfig
