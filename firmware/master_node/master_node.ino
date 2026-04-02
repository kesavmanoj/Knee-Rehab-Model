#include <Arduino.h>
#include <Wire.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "AppConfig.h"
#include "BleCentralManager.h"
#include "CalibratedAngleModels.h"
#include "CalibrationSession.h"
#include "FlexSensorModel.h"
#include "GeneratedCalibration.h"
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

struct AlignedImuPair {
  float masterRawDeg;
  float slaveRawDeg;
  uint16_t slaveSequence;
  uint32_t capturedAtMs;
  bool valid;
};

CalibrationSession calibrationSession;
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
AlignedImuPair alignedImuPair{0.0f, 0.0f, 0U, 0UL, false};

char serialCommandBuffer[24] = {};
size_t serialCommandLength = 0;

uint32_t lastAnalogSampleMs = 0;
uint32_t lastImuSampleMs = 0;
uint32_t lastRuntimeLogMs = 0;
uint32_t lastOledUpdateMs = 0;
uint32_t lastPhoneTelemetryMs = 0;
uint16_t phoneTelemetrySequence = 0;

float wrapAngle180(float angleDeg) {
  while (angleDeg > 180.0f) {
    angleDeg -= 360.0f;
  }
  while (angleDeg < -180.0f) {
    angleDeg += 360.0f;
  }
  return angleDeg;
}

void latchAlignedImuPair() {
  if (!bleCentral.hasPacket()) {
    return;
  }

  alignedImuPair.masterRawDeg = thighImu.primaryAngleDeg();
  alignedImuPair.slaveRawDeg = bleCentral.latestPacket().segmentAngleDeg;
  alignedImuPair.slaveSequence = bleCentral.latestPacket().sequence;
  alignedImuPair.capturedAtMs = millis();
  alignedImuPair.valid = true;
}

float masterImuRawDeg() {
  if (alignedImuPair.valid) {
    return alignedImuPair.masterRawDeg;
  }
  return thighImu.primaryAngleDeg();
}

float slaveImuRawDeg() {
  if (alignedImuPair.valid) {
    return alignedImuPair.slaveRawDeg;
  }
  return bleCentral.hasPacket() ? bleCentral.latestPacket().segmentAngleDeg : 0.0f;
}

float masterImuZeroedDeg() {
  return masterImuRawDeg() - zeroReferences.masterImuDeg;
}

float slaveImuZeroedDeg() {
  return slaveImuRawDeg() - zeroReferences.slaveImuDeg;
}

float kneeAngleDeg() {
  return fabsf(wrapAngle180(slaveImuZeroedDeg() - masterImuZeroedDeg()));
}

float calibratedImuAngleDeg() {
  return CalibratedAngleModels::imuAngleFromRawKneeAngle(kneeAngleDeg());
}

void printHeader() {
  Serial.println();
  Serial.println(F("# Unified FLEX + POT monitor"));
  Serial.print(F("# FLEX source session: "));
  Serial.println(GeneratedCalibration::kFlexSourceSession);
  Serial.print(F("# POT source session: "));
  Serial.println(GeneratedCalibration::kPotSourceSession);
  Serial.println(F("# Output formats:"));
  Serial.println(F("#   RUNTIME_SAMPLE,time_ms,flex_raw_adc,flex_angle_deg,pot_raw_adc,pot_angle_deg,master_imu_deg,slave_imu_deg,imu_angle_deg"));
  Serial.println(F("#   FLEX_SAMPLE,time_ms,flex_raw_adc,flex_filtered_adc,flex_voltage,flex_resistance_ohms,flex_angle_deg,label_deg"));
  Serial.println(F("#   POT_SAMPLE,time_ms,pot_raw_adc,pot_filtered_adc,pot_voltage,pot_angle_deg,label_deg"));
  Serial.println(F("#   IMU_SAMPLE,time_ms,master_imu_deg,slave_imu_deg,imu_raw_knee_angle_deg,imu_angle_deg,label_deg"));
  Serial.println(F("# Phone BLE:"));
  Serial.print(F("#   Device Name: "));
  Serial.println(MasterConfig::kPhoneBleDeviceName);
  Serial.print(F("#   Service UUID: "));
  Serial.println(KneePhoneBle::kPhoneServiceUuid);
  Serial.println(F("#   LABEL_START,time_ms,label_deg,window_ms"));
  Serial.println(F("#   LABEL_END,time_ms,label_deg"));
  Serial.println(F("# Commands: h, z, r, or numeric angle 0..145"));
}

void captureImuZeroReference() {
  zeroReferences.masterImuDeg = masterImuRawDeg();
  zeroReferences.slaveImuDeg = slaveImuRawDeg();
  zeroReferences.applied = true;
  Serial.println(F("# IMU zero reference captured."));
}

void clearImuZeroReference() {
  zeroReferences.masterImuDeg = 0.0f;
  zeroReferences.slaveImuDeg = 0.0f;
  zeroReferences.applied = false;
  Serial.println(F("# IMU zero reference cleared."));
}

void handleCommand(const char* command) {
  if (strcmp(command, "h") == 0 || strcmp(command, "H") == 0) {
    printHeader();
    return;
  }

  if (strcmp(command, "z") == 0 || strcmp(command, "Z") == 0) {
    captureImuZeroReference();
    return;
  }

  if (strcmp(command, "r") == 0 || strcmp(command, "R") == 0) {
    clearImuZeroReference();
    return;
  }

  char* parseEnd = nullptr;
  const float labelDeg = strtof(command, &parseEnd);
  if (parseEnd == command || *parseEnd != '\0') {
    Serial.println(F("# Ignored command. Enter h, z, r, or a numeric angle 0..145."));
    return;
  }

  if (labelDeg < MasterConfig::kCalibrationMinAngleDeg || labelDeg > MasterConfig::kCalibrationMaxAngleDeg) {
    Serial.println(F("# Angle out of range. Enter a value between 0 and 145."));
    return;
  }

  const uint32_t nowMs = millis();
  if (calibrationSession.isActive()) {
    Serial.print(F("LABEL_END,"));
    Serial.print(nowMs);
    Serial.print(F(","));
    Serial.println(calibrationSession.activeLabelDeg(), 1);
  }

  calibrationSession.beginLabel(labelDeg, MasterConfig::kCalibrationCaptureWindowMs, nowMs);
  Serial.print(F("LABEL_START,"));
  Serial.print(nowMs);
  Serial.print(F(","));
  Serial.print(labelDeg, 1);
  Serial.print(F(","));
  Serial.println(MasterConfig::kCalibrationCaptureWindowMs);
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

void updateCalibrationSession() {
  const bool wasActive = calibrationSession.isActive();
  const float completedLabelDeg = calibrationSession.activeLabelDeg();
  calibrationSession.update(millis());
  if (wasActive && !calibrationSession.isActive()) {
    Serial.print(F("LABEL_END,"));
    Serial.print(millis());
    Serial.print(F(","));
    Serial.println(completedLabelDeg, 1);
  }
}

float activeLabelDegOrNan() {
  return calibrationSession.isActive() ? calibrationSession.activeLabelDeg() : NAN;
}

void printRuntimeSample() {
  const auto& flex = flexSensor.reading();
  const auto& pot = potSensor.reading();
  const float flexAngleDeg = CalibratedAngleModels::flexAngleFromRawAdc(flex.rawAdc);
  const float potAngleDeg = CalibratedAngleModels::potAngleFromRawAdc(pot.rawAdc);
  const float masterImuDeg = masterImuZeroedDeg();
  const float slaveImuDeg = slaveImuZeroedDeg();
  const float imuAngleDeg = calibratedImuAngleDeg();

  Serial.print(F("RUNTIME_SAMPLE,"));
  Serial.print(millis());
  Serial.print(F(","));
  Serial.print(flex.rawAdc);
  Serial.print(F(","));
  Serial.print(flexAngleDeg, 2);
  Serial.print(F(","));
  Serial.print(pot.rawAdc);
  Serial.print(F(","));
  Serial.print(potAngleDeg, 2);
  Serial.print(F(","));
  Serial.print(masterImuDeg, 2);
  Serial.print(F(","));
  Serial.print(slaveImuDeg, 2);
  Serial.print(F(","));
  Serial.println(imuAngleDeg, 2);
}

void printFlexSample() {
  const auto& flex = flexSensor.reading();
  const float flexAngleDeg = CalibratedAngleModels::flexAngleFromRawAdc(flex.rawAdc);

  Serial.print(F("FLEX_SAMPLE,"));
  Serial.print(millis());
  Serial.print(F(","));
  Serial.print(flex.rawAdc);
  Serial.print(F(","));
  Serial.print(flex.filteredAdc, 2);
  Serial.print(F(","));
  Serial.print(flex.voltage, 4);
  Serial.print(F(","));
  if (flex.valid) {
    Serial.print(flex.resistanceOhms, 2);
  } else {
    Serial.print(F("nan"));
  }
  Serial.print(F(","));
  Serial.print(flexAngleDeg, 2);
  Serial.print(F(","));
  if (calibrationSession.isActive()) {
    Serial.println(activeLabelDegOrNan(), 1);
  } else {
    Serial.println(F("nan"));
  }
}

void printPotSample() {
  const auto& pot = potSensor.reading();
  const float potAngleDeg = CalibratedAngleModels::potAngleFromRawAdc(pot.rawAdc);

  Serial.print(F("POT_SAMPLE,"));
  Serial.print(millis());
  Serial.print(F(","));
  Serial.print(pot.rawAdc);
  Serial.print(F(","));
  Serial.print(pot.filteredAdc, 2);
  Serial.print(F(","));
  Serial.print(pot.voltage, 4);
  Serial.print(F(","));
  Serial.print(potAngleDeg, 2);
  Serial.print(F(","));
  if (calibrationSession.isActive()) {
    Serial.println(activeLabelDegOrNan(), 1);
  } else {
    Serial.println(F("nan"));
  }
}

void printImuSample() {
  const float masterImuDeg = masterImuZeroedDeg();
  const float slaveImuDeg = slaveImuZeroedDeg();
  const float imuRawKneeAngleDeg = kneeAngleDeg();
  const float imuAngleDeg = calibratedImuAngleDeg();

  Serial.print(F("IMU_SAMPLE,"));
  Serial.print(millis());
  Serial.print(F(","));
  Serial.print(masterImuDeg, 2);
  Serial.print(F(","));
  Serial.print(slaveImuDeg, 2);
  Serial.print(F(","));
  Serial.print(imuRawKneeAngleDeg, 2);
  Serial.print(F(","));
  Serial.print(imuAngleDeg, 2);
  Serial.print(F(","));
  if (calibrationSession.isActive()) {
    Serial.println(activeLabelDegOrNan(), 1);
  } else {
    Serial.println(F("nan"));
  }
}

void handlePhoneCommands() {
  if (!phoneBle.hasPendingCommand()) {
    return;
  }

  const KneePhoneBle::CommandPacketV1 command = phoneBle.consumePendingCommand();
  switch (command.commandId) {
    case KneePhoneBle::kCmdZeroImu:
      captureImuZeroReference();
      break;
    case KneePhoneBle::kCmdClearZero:
      clearImuZeroReference();
      break;
    default:
      Serial.println(F("# Ignored phone command."));
      break;
  }
}

KneePhoneBle::TelemetryPacketV1 makePhoneTelemetryPacket() {
  const auto& flex = flexSensor.reading();
  const auto& pot = potSensor.reading();

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
  if (flex.valid) {
    packet.flags |= KneePhoneBle::kFlagFlexValid;
  }
  packet.flags |= KneePhoneBle::kFlagPotValid;
  packet.sequence = phoneTelemetrySequence++;
  packet.uptimeMs = millis();
  packet.masterImuDeg = masterImuZeroedDeg();
  packet.slaveImuDeg = slaveImuZeroedDeg();
  packet.imuKneeDeg = calibratedImuAngleDeg();
  packet.flexRawAdc = flex.rawAdc;
  packet.flexAngleDeg = CalibratedAngleModels::flexAngleFromRawAdc(flex.rawAdc);
  packet.potRawAdc = pot.rawAdc;
  packet.potAngleDeg = CalibratedAngleModels::potAngleFromRawAdc(pot.rawAdc);
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
  if (bleCentral.consumeNewPacketFlag()) {
    latchAlignedImuPair();
  }
  handleSerialCommands();
  updateCalibrationSession();
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

  if (nowMs - lastRuntimeLogMs >= MasterConfig::kCalibrationLogIntervalMs) {
    lastRuntimeLogMs = nowMs;
    printRuntimeSample();
    printFlexSample();
    printPotSample();
    printImuSample();
  }

  if (nowMs - lastPhoneTelemetryMs >= MasterConfig::kPhoneTelemetryIntervalMs) {
    lastPhoneTelemetryMs = nowMs;
    const KneePhoneBle::TelemetryPacketV1 telemetry = makePhoneTelemetryPacket();
    const KneePhoneBle::StatusPacketV1 status = makePhoneStatusPacket(telemetry.sequence);
    phoneBle.updateTelemetry(telemetry, status);
  }

  if (nowMs - lastOledUpdateMs >= MasterConfig::kOledUpdateIntervalMs) {
    lastOledUpdateMs = nowMs;
    oledDisplay.render({masterImuZeroedDeg(),
                        slaveImuZeroedDeg(),
                        kneeAngleDeg(),
                        zeroReferences.applied,
                        bleCentral.stateText()});
  }
}
