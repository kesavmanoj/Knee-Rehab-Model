#include <Arduino.h>
#include <Wire.h>
#include <core_cm33.h>
#include <WatchdogTimer.h>

#include "BleProtocol.h"
#include "AppConfig.h"
#include "BlePeripheralManager.h"
#include "ComplementaryFilter.h"
#include "ImuManager.h"

namespace {

ImuManager imuManager;
BlePeripheralManager bleManager;
ComplementaryFilter pitchFilter;
ComplementaryFilter rollFilter;

ImuSample latestSample{};

float fusedPitchDeg = 0.0f;
float fusedRollDeg = 0.0f;
float primaryZeroOffsetDeg = 0.0f;

uint16_t packetSequence = 0;
uint32_t lastImuSampleMs = 0;
uint32_t lastBleNotifyMs = 0;
uint32_t lastSerialDebugMs = 0;
uint32_t lastUpdateMicros = 0;
uint32_t healthyStreamingStartedMs = 0;
bool healthyStreamingAnnounced = false;

bool imuHealthy = false;
bool zeroApplied = false;

float computeAdaptiveAlpha(const ImuSample& sample) {
  const float motionDps = max(fabsf(sample.gyroX_dps), fabsf(sample.gyroY_dps));
  if (motionDps <= SlaveConfig::kGyroQuietThresholdDps) {
    return SlaveConfig::kComplementaryAlphaSettled;
  }
  if (motionDps >= SlaveConfig::kGyroFastThresholdDps) {
    return SlaveConfig::kComplementaryAlphaMoving;
  }

  const float span = SlaveConfig::kGyroFastThresholdDps - SlaveConfig::kGyroQuietThresholdDps;
  const float ratio = (motionDps - SlaveConfig::kGyroQuietThresholdDps) / span;
  return SlaveConfig::kComplementaryAlphaSettled +
         (ratio * (SlaveConfig::kComplementaryAlphaMoving - SlaveConfig::kComplementaryAlphaSettled));
}

float primaryAngleDeg() {
  const float rawPrimary = SlaveConfig::kUsePitchAsPrimaryAxis ? fusedPitchDeg : fusedRollDeg;
  return rawPrimary - primaryZeroOffsetDeg;
}

void printHelp() {
  Serial.println(F("Commands:"));
  Serial.println(F("  z -> zero current primary IMU angle"));
  Serial.println(F("  r -> reset zero offset"));
  Serial.println(F("  h -> show help"));
}

void resetBoard() {
  Serial.println(F("Slave watchdog reset."));
  Serial.flush();
  delay(50);
  NVIC_SystemReset();
}

void handleSerialCommands() {
  while (Serial.available() > 0) {
    const char command = static_cast<char>(Serial.read());
    if (command == 'z' || command == 'Z') {
      primaryZeroOffsetDeg = SlaveConfig::kUsePitchAsPrimaryAxis ? fusedPitchDeg : fusedRollDeg;
      zeroApplied = true;
      Serial.println(F("Zero reference stored for slave IMU."));
    } else if (command == 'r' || command == 'R') {
      primaryZeroOffsetDeg = 0.0f;
      zeroApplied = false;
      Serial.println(F("Zero reference cleared."));
    } else if (command == 'h' || command == 'H') {
      printHelp();
    }
  }
}

void updateImu() {
  ImuSample sample;
  if (!imuManager.readSample(sample)) {
    imuHealthy = false;
    return;
  }

  latestSample = sample;

  const uint32_t nowMicros = micros();
  float dtSeconds = 0.0f;
  if (lastUpdateMicros != 0) {
    dtSeconds = (nowMicros - lastUpdateMicros) * 1.0e-6f;
  }
  lastUpdateMicros = nowMicros;

  if (dtSeconds <= 0.0f || dtSeconds > 0.25f) {
    pitchFilter.begin(sample.accelPitchDeg * SlaveConfig::kPitchSign);
    rollFilter.begin(sample.accelRollDeg * SlaveConfig::kRollSign);
  } else {
    const float adaptiveAlpha = computeAdaptiveAlpha(sample);
    fusedPitchDeg = pitchFilter.update(sample.gyroY_dps * SlaveConfig::kPitchGyroSign,
                                       sample.accelPitchDeg * SlaveConfig::kPitchSign,
                                       dtSeconds,
                                       adaptiveAlpha);
    fusedRollDeg = rollFilter.update(sample.gyroX_dps * SlaveConfig::kRollGyroSign,
                                     sample.accelRollDeg * SlaveConfig::kRollSign,
                                     dtSeconds,
                                     adaptiveAlpha);
  }

  if (dtSeconds <= 0.0f || dtSeconds > 0.25f) {
    fusedPitchDeg = sample.accelPitchDeg * SlaveConfig::kPitchSign;
    fusedRollDeg = sample.accelRollDeg * SlaveConfig::kRollSign;
  }

  imuHealthy = true;
}

bool sendBlePacket() {
  KneeBle::OrientationPacketV1 packet{};
  packet.version = KneeBle::kProtocolVersion;
  packet.flags = KneeBle::kFlagNone;
  if (zeroApplied) {
    packet.flags |= KneeBle::kFlagZeroed;
  }
  if (imuHealthy) {
    packet.flags |= KneeBle::kFlagImuHealthy;
  }
  packet.sequence = packetSequence++;
  packet.uptimeMs = millis();
  packet.segmentAngleDeg = primaryAngleDeg();
  packet.pitchDeg = fusedPitchDeg;
  packet.rollDeg = fusedRollDeg;
  packet.accelPitchDeg = latestSample.accelPitchDeg * SlaveConfig::kPitchSign;

  return bleManager.publish(packet);
}

void printDebugLine() {
  char buffer[180];
  snprintf(buffer,
           sizeof(buffer),
           "SLAVE | PRI:[%7.2f] deg | PITCH:[%7.2f] | ROLL:[%7.2f] | ACC_P:[%7.2f] | GY_Y:[%7.2f] | BLE:%-4s",
           primaryAngleDeg(),
           fusedPitchDeg,
           fusedRollDeg,
           latestSample.accelPitchDeg * SlaveConfig::kPitchSign,
           latestSample.gyroY_dps * SlaveConfig::kPitchGyroSign,
           bleManager.isConnected() ? "ON" : "OFF");
  Serial.println(buffer);
}

void updateHardwareWatchdog(uint32_t nowMs) {
  const bool healthyLink =
      healthyStreamingStartedMs != 0UL &&
      (nowMs - healthyStreamingStartedMs) >= SlaveConfig::kConnectionHealthyWindowMs;

  if (healthyLink) {
    WatchdogTimer.feed();
    if (!healthyStreamingAnnounced) {
      healthyStreamingAnnounced = true;
      Serial.println(F("Slave hardware watchdog is now being fed."));
    }
    return;
  }

  healthyStreamingAnnounced = false;
}

}  // namespace

void setup() {
  Serial.begin(SlaveConfig::kSerialBaud);
  const uint32_t serialStart = millis();
  while (!Serial && (millis() - serialStart < 2000UL)) {
  }

  Wire.begin();

  Serial.println();
  Serial.println(F("Knee Rehab Slave Node"));
  if (WatchdogTimer.watchdogResetHappened()) {
    Serial.println(F("Slave restarted after a hardware watchdog reset."));
  }
  printHelp();

  if (!imuManager.begin()) {
    Serial.println(F("ERROR: Failed to initialize LSM6DS3 IMU."));
    while (true) {
      delay(100);
    }
  }

  if (!bleManager.begin(SlaveConfig::kDeviceName)) {
    Serial.println(F("ERROR: Failed to initialize BLE peripheral."));
    while (true) {
      delay(100);
    }
  }

  healthyStreamingStartedMs = 0UL;
  WatchdogTimer.begin(WDOG_PERIOD_2_S);

  updateImu();
  pitchFilter.begin(latestSample.accelPitchDeg * SlaveConfig::kPitchSign);
  rollFilter.begin(latestSample.accelRollDeg * SlaveConfig::kRollSign);
  fusedPitchDeg = latestSample.accelPitchDeg * SlaveConfig::kPitchSign;
  fusedRollDeg = latestSample.accelRollDeg * SlaveConfig::kRollSign;
}

void loop() {
  const uint32_t nowMs = millis();

  bleManager.poll();
  handleSerialCommands();

  if (nowMs - lastImuSampleMs >= SlaveConfig::kImuSampleIntervalMs) {
    lastImuSampleMs = nowMs;
    updateImu();
  }

  if (nowMs - lastBleNotifyMs >= SlaveConfig::kBleNotifyIntervalMs) {
    lastBleNotifyMs = nowMs;
    if (bleManager.isConnected() && sendBlePacket()) {
      if (healthyStreamingStartedMs == 0UL) {
        healthyStreamingStartedMs = nowMs;
        Serial.println(F("Slave good BLE publishing started."));
      }
    } else {
      if (healthyStreamingStartedMs != 0UL) {
        Serial.println(F("Slave lost continuous good BLE publishing."));
      }
      healthyStreamingStartedMs = 0UL;
    }
  }

  updateHardwareWatchdog(nowMs);

  if (nowMs - lastSerialDebugMs >= SlaveConfig::kSerialDebugIntervalMs) {
    lastSerialDebugMs = nowMs;
    printDebugLine();
  }
}
