#include <Arduino.h>
#include <Wire.h>
#include <math.h>
#include <string.h>
#include <core_cm33.h>

#include "AppConfig.h"
#include "BleCentralManager.h"
#include "FlexSensorModel.h"
#include "OledDisplayManager.h"
#include "PhoneBlePeripheralManager.h"
#include "PhoneBleProtocol.h"
#include "PotentiometerModel.h"
#include "SegmentOrientationEstimator.h"

namespace {

struct ZeroReferences {
  float masterImuDeg;
  float slaveImuDeg;
  bool applied;
};

struct RuntimeSnapshot {
  float masterImuDeg;
  float slaveImuDeg;
  float kneeImuDeg;
  uint16_t flexRawAdc;
  float flexAngleDeg;
  uint16_t potRawAdc;
  float potAngleDeg;
};

SegmentOrientationEstimator thighImu;
BleCentralManager bleCentral;
OledDisplayManager oledDisplay;
PhoneBlePeripheralManager phoneBle;
FlexSensorModel flexSensor(MasterConfig::kFlex1Pin,
                           MasterConfig::kFlex1FixedResistorOhms,
                           MasterConfig::kFlexCalibrationTable,
                           MasterConfig::kFlexCalibrationPointCount);
PotentiometerModel potSensor(MasterConfig::kPotPin);

ZeroReferences zeroReferences{0.0f, 0.0f, false};

char serialCommandBuffer[24] = {};
size_t serialCommandLength = 0;

uint32_t lastImuSampleMs = 0;
uint32_t lastAnalogSampleMs = 0;
uint32_t lastDashboardMs = 0;
uint32_t lastOledUpdateMs = 0;
uint32_t lastPhoneTelemetryMs = 0;
uint16_t phoneTelemetrySequence = 0;
uint32_t recoveryStartedMs = 0;
uint32_t connectedSinceMs = 0;
bool lastSlaveLinkHealthy = false;

float wrapAngle180(float angleDeg) {
  while (angleDeg > 180.0f) {
    angleDeg -= 360.0f;
  }
  while (angleDeg < -180.0f) {
    angleDeg += 360.0f;
  }
  return angleDeg;
}

float masterImuRawDeg() {
  return thighImu.primaryAngleDeg();
}

float slaveImuRawDeg() {
  return bleCentral.hasPacket() ? bleCentral.latestPacket().segmentAngleDeg : 0.0f;
}

float masterImuZeroedDeg() {
  return masterImuRawDeg() - zeroReferences.masterImuDeg;
}

float slaveImuZeroedDeg() {
  return slaveImuRawDeg() - zeroReferences.slaveImuDeg;
}

float kneeImuDeg() {
  return fabsf(wrapAngle180(slaveImuZeroedDeg() - masterImuZeroedDeg()));
}

RuntimeSnapshot makeSnapshot() {
  const FlexSensorReading& flex = flexSensor.reading();
  const PotentiometerReading& pot = potSensor.reading();

  RuntimeSnapshot snapshot{};
  snapshot.masterImuDeg = masterImuZeroedDeg();
  snapshot.slaveImuDeg = slaveImuZeroedDeg();
  snapshot.kneeImuDeg = kneeImuDeg();
  snapshot.flexRawAdc = flex.rawAdc;
  snapshot.flexAngleDeg = flex.angleDeg;
  snapshot.potRawAdc = pot.rawAdc;
  snapshot.potAngleDeg = pot.angleDeg;
  return snapshot;
}

void printHeader() {
  Serial.println();
  Serial.println(F("# Simple master baseline"));
  Serial.println(F("# Features: local IMU, slave BLE link, flex D0, pot D2, phone BLE"));
  Serial.print(F("# Phone device name: "));
  Serial.println(MasterConfig::kPhoneBleDeviceName);
  Serial.print(F("# Phone service UUID: "));
  Serial.println(KneePhoneBle::kPhoneServiceUuid);
  Serial.println(F("# Commands: h, z, r, x/reset"));
  Serial.println(F("# Output: SIMPLE,time_ms,master_imu_deg,slave_imu_deg,knee_imu_deg,flex_raw_adc,flex_angle_deg,pot_raw_adc,pot_angle_deg,ble_state"));
}

void captureZeroReference() {
  zeroReferences.masterImuDeg = masterImuRawDeg();
  zeroReferences.slaveImuDeg = slaveImuRawDeg();
  zeroReferences.applied = true;
  Serial.println(F("# Zero reference captured."));
}

void clearZeroReference() {
  zeroReferences.masterImuDeg = 0.0f;
  zeroReferences.slaveImuDeg = 0.0f;
  zeroReferences.applied = false;
  Serial.println(F("# Zero reference cleared."));
}

void resetBoard() {
  Serial.println(F("# Resetting board..."));
  Serial.flush();
  delay(50);
  NVIC_SystemReset();
}

void updateConnectionWatchdog(uint32_t nowMs) {
  const bool linkHealthy = bleCentral.hasFreshPacket();
  if (linkHealthy) {
    if (!lastSlaveLinkHealthy) {
      connectedSinceMs = nowMs;
      lastSlaveLinkHealthy = true;
      Serial.println(F("# Master reconnected to slave, stability check running."));
    }

    if (recoveryStartedMs != 0UL &&
        (nowMs - connectedSinceMs) >= MasterConfig::kConnectionStableTimeMs) {
      Serial.println(F("# Master-slave link considered stable, watchdog cleared."));
      recoveryStartedMs = 0UL;
    }

    return;
  }

  if (lastSlaveLinkHealthy) {
    if (recoveryStartedMs == 0UL) {
      recoveryStartedMs = nowMs;
    }
    connectedSinceMs = 0UL;
    lastSlaveLinkHealthy = false;
    Serial.println(F("# Master lost slave link, recovery watchdog armed."));
    return;
  }

  if (recoveryStartedMs == 0UL) {
    recoveryStartedMs = nowMs;
    return;
  }

  if ((nowMs - recoveryStartedMs) >= MasterConfig::kConnectionResetTimeoutMs) {
    Serial.println(F("# Master failed to recover a stable slave link in time."));
    resetBoard();
  }
}

void handleCommand(const char* command) {
  if (strcmp(command, "h") == 0 || strcmp(command, "H") == 0) {
    printHeader();
    return;
  }

  if (strcmp(command, "z") == 0 || strcmp(command, "Z") == 0) {
    captureZeroReference();
    return;
  }

  if (strcmp(command, "r") == 0 || strcmp(command, "R") == 0) {
    clearZeroReference();
    return;
  }

  if (strcmp(command, "x") == 0 || strcmp(command, "X") == 0 ||
      strcmp(command, "reset") == 0 || strcmp(command, "RESET") == 0) {
    resetBoard();
    return;
  }

  Serial.println(F("# Ignored command. Use h, z, r, or x/reset."));
}

void handleSerialCommands() {
  while (Serial.available() > 0) {
    const char incoming = static_cast<char>(Serial.read());
    if (incoming == '\r' || incoming == '\n') {
      if (serialCommandLength > 0U) {
        serialCommandBuffer[serialCommandLength] = '\0';
        handleCommand(serialCommandBuffer);
        serialCommandLength = 0U;
      }
      continue;
    }

    if (serialCommandLength < (sizeof(serialCommandBuffer) - 1U)) {
      serialCommandBuffer[serialCommandLength++] = incoming;
    }
  }
}

void handlePhoneCommands() {
  if (!phoneBle.hasPendingCommand()) {
    return;
  }

  const KneePhoneBle::CommandPacketV1 command = phoneBle.consumePendingCommand();
  switch (command.commandId) {
    case KneePhoneBle::kCmdZeroImu:
      captureZeroReference();
      break;
    case KneePhoneBle::kCmdClearZero:
      clearZeroReference();
      break;
    default:
      Serial.println(F("# Ignored phone command."));
      break;
  }
}

void printSimpleLine(const RuntimeSnapshot& snapshot) {
  Serial.print(F("SIMPLE,"));
  Serial.print(millis());
  Serial.print(F(","));
  Serial.print(snapshot.masterImuDeg, 2);
  Serial.print(F(","));
  Serial.print(snapshot.slaveImuDeg, 2);
  Serial.print(F(","));
  Serial.print(snapshot.kneeImuDeg, 2);
  Serial.print(F(","));
  Serial.print(snapshot.flexRawAdc);
  Serial.print(F(","));
  Serial.print(snapshot.flexAngleDeg, 2);
  Serial.print(F(","));
  Serial.print(snapshot.potRawAdc);
  Serial.print(F(","));
  Serial.print(snapshot.potAngleDeg, 2);
  Serial.print(F(","));
  Serial.println(bleCentral.stateText());
}

KneePhoneBle::TelemetryPacketV1 makePhoneTelemetryPacket(const RuntimeSnapshot& snapshot) {
  KneePhoneBle::TelemetryPacketV1 packet{};
  packet.version = KneePhoneBle::kTelemetryVersion;
  packet.flags = KneePhoneBle::kFlagNone;
  if (bleCentral.hasFreshPacket()) {
    packet.flags |= KneePhoneBle::kFlagSlaveConnected;
    packet.flags |= KneePhoneBle::kFlagImuValid;
  }
  if (zeroReferences.applied) {
    packet.flags |= KneePhoneBle::kFlagImuZeroed;
  }
  if (flexSensor.reading().valid) {
    packet.flags |= KneePhoneBle::kFlagFlexValid;
  }
  packet.flags |= KneePhoneBle::kFlagPotValid;
  packet.sequence = phoneTelemetrySequence++;
  packet.uptimeMs = millis();
  packet.masterImuDeg = snapshot.masterImuDeg;
  packet.slaveImuDeg = snapshot.slaveImuDeg;
  packet.imuKneeDeg = snapshot.kneeImuDeg;
  packet.flexRawAdc = snapshot.flexRawAdc;
  packet.flexAngleDeg = snapshot.flexAngleDeg;
  packet.potRawAdc = snapshot.potRawAdc;
  packet.potAngleDeg = snapshot.potAngleDeg;
  return packet;
}

KneePhoneBle::StatusPacketV1 makePhoneStatusPacket(uint16_t lastSequence) {
  KneePhoneBle::StatusPacketV1 packet{};
  packet.version = KneePhoneBle::kStatusVersion;
  packet.flags = KneePhoneBle::kFlagNone;
  if (bleCentral.hasFreshPacket()) {
    packet.flags |= KneePhoneBle::kFlagSlaveConnected;
    packet.flags |= KneePhoneBle::kFlagImuValid;
  }
  if (zeroReferences.applied) {
    packet.flags |= KneePhoneBle::kFlagImuZeroed;
  }
  if (flexSensor.reading().valid) {
    packet.flags |= KneePhoneBle::kFlagFlexValid;
  }
  packet.flags |= KneePhoneBle::kFlagPotValid;
  packet.lastSequence = lastSequence;
  packet.uptimeMs = millis();
  return packet;
}

}  // namespace

void setup() {
  Serial.begin(MasterConfig::kSerialBaud);
  const uint32_t serialStart = millis();
  while (!Serial && (millis() - serialStart < 2000UL)) {
  }

  Wire.begin();
  analogReadResolution(12);

  if (!thighImu.begin()) {
    Serial.println(F("# ERROR: Failed to initialize local IMU."));
    while (true) {
      delay(100);
    }
  }

  if (!bleCentral.begin()) {
    Serial.println(F("# ERROR: Failed to initialize BLE central."));
    while (true) {
      delay(100);
    }
  }

  if (!phoneBle.begin()) {
    Serial.println(F("# Warning: Failed to initialize phone BLE service."));
  } else {
    Serial.print(F("# Phone BLE advertising as "));
    Serial.println(MasterConfig::kPhoneBleDeviceName);
  }

  flexSensor.begin();
  potSensor.begin();

  if (oledDisplay.begin()) {
    Serial.println(F("# OLED display detected on I2C."));
  } else {
    Serial.println(F("# Warning: SSD1306 OLED not detected at 0x3C."));
  }

  printHeader();
}

void loop() {
  const uint32_t nowMs = millis();

  bleCentral.poll();
  phoneBle.poll();
  updateConnectionWatchdog(nowMs);
  handleSerialCommands();
  handlePhoneCommands();

  if (nowMs - lastImuSampleMs >= MasterConfig::kImuSampleIntervalMs) {
    lastImuSampleMs = nowMs;
    thighImu.update();
  }

  if (nowMs - lastAnalogSampleMs >= MasterConfig::kAnalogSampleIntervalMs) {
    lastAnalogSampleMs = nowMs;
    flexSensor.update();
    potSensor.update();
  }

  const RuntimeSnapshot snapshot = makeSnapshot();

  if (nowMs - lastDashboardMs >= MasterConfig::kDashboardIntervalMs) {
    lastDashboardMs = nowMs;
    printSimpleLine(snapshot);
  }

  if (nowMs - lastPhoneTelemetryMs >= MasterConfig::kPhoneTelemetryIntervalMs) {
    lastPhoneTelemetryMs = nowMs;
    const KneePhoneBle::TelemetryPacketV1 telemetry = makePhoneTelemetryPacket(snapshot);
    const KneePhoneBle::StatusPacketV1 status = makePhoneStatusPacket(telemetry.sequence);
    phoneBle.updateTelemetry(telemetry, status);
  }

  if (nowMs - lastOledUpdateMs >= MasterConfig::kOledUpdateIntervalMs) {
    lastOledUpdateMs = nowMs;
    oledDisplay.render({snapshot.masterImuDeg,
                        snapshot.slaveImuDeg,
                        snapshot.kneeImuDeg,
                        zeroReferences.applied,
                        bleCentral.stateText()});
  }
}
