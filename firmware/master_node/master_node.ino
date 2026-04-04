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
#include "SensorFusion.h"
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
  float fusedKneeDeg;
  float fusedImuWeight;
  float fusedFlexWeight;
  float fusedPotWeight;
  uint16_t flexRawAdc;
  float flexAngleDeg;
  uint16_t potRawAdc;
  float potFilteredAdc;
  float potVoltage;
  float potAngleDeg;
};

enum class SerialStreamMode : uint8_t {
  kNormal = 0,
  kRuntime = 1,
  kPotCalibration = 2,
  kFlexCalibration = 3,
  kImuCalibration = 4,
};

SegmentOrientationEstimator thighImu;
BleCentralManager bleCentral;
OledDisplayManager oledDisplay;
PhoneBlePeripheralManager phoneBle;
SensorFusion sensorFusion;
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
uint8_t recoveryDisconnectCount = 0;
const char* currentPhase = "BOOT";

bool potCalibrationLabelActive = false;
float potCalibrationLabelDeg = 0.0f;
uint32_t potCalibrationLabelEndMs = 0;
SerialStreamMode serialStreamMode = SerialStreamMode::kNormal;

unsigned long currentDashboardIntervalMs() {
  return serialStreamMode == SerialStreamMode::kNormal
             ? MasterConfig::kDashboardIntervalNormalMs
             : MasterConfig::kDashboardIntervalFastMs;
}

const __FlashStringHelper* serialStreamModeLabel() {
  switch (serialStreamMode) {
    case SerialStreamMode::kRuntime:
      return F("RUNTIME");
    case SerialStreamMode::kPotCalibration:
      return F("POT_CAL");
    case SerialStreamMode::kFlexCalibration:
      return F("FLEX_CAL");
    case SerialStreamMode::kImuCalibration:
      return F("IMU_CAL");
    case SerialStreamMode::kNormal:
    default:
      return F("NORMAL");
  }
}

void setPhase(const char* phase) {
  currentPhase = phase;
}

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
  const float imuKneeAngle = kneeImuDeg();
  const SensorFusionResult fused = sensorFusion.fuse({
      bleCentral.hasFreshPacket(),
      imuKneeAngle,
      flex.valid,
      flex.angleDeg,
      isfinite(pot.angleDeg),
      pot.angleDeg,
  });

  RuntimeSnapshot snapshot{};
  snapshot.masterImuDeg = masterImuZeroedDeg();
  snapshot.slaveImuDeg = slaveImuZeroedDeg();
  snapshot.kneeImuDeg = imuKneeAngle;
  snapshot.fusedKneeDeg = fused.valid ? fused.fusedAngleDeg : imuKneeAngle;
  snapshot.fusedImuWeight = fused.imuWeight;
  snapshot.fusedFlexWeight = fused.flexWeight;
  snapshot.fusedPotWeight = fused.potWeight;
  snapshot.flexRawAdc = flex.rawAdc;
  snapshot.flexAngleDeg = flex.angleDeg;
  snapshot.potRawAdc = pot.rawAdc;
  snapshot.potFilteredAdc = pot.filteredAdc;
  snapshot.potVoltage = pot.voltage;
  snapshot.potAngleDeg = pot.angleDeg;
  return snapshot;
}

void printHeader() {
  Serial.println();
  Serial.println(F("# Simple master baseline"));
  Serial.println(F("# Features: local IMU, slave BLE link, flex D0, pot D2, phone BLE, sensor fusion"));
  Serial.print(F("# Phone device name: "));
  Serial.println(MasterConfig::kPhoneBleDeviceName);
  Serial.print(F("# Phone service UUID: "));
  Serial.println(KneePhoneBle::kPhoneServiceUuid);
  Serial.println(F("# Commands: h, z, r, x/reset, mode normal, mode fast, stream runtime, stream pot, stream flex, stream imu, or any numeric angle 0..145 for labels"));
  Serial.println(F("# Fusion weights: IMU=0.475 POT=0.475 FLEX=0.05"));
  Serial.print(F("# Primary IMU axis: "));
  Serial.println(MasterConfig::kUsePitchAsPrimaryAxis ? F("PITCH") : F("ROLL"));
  Serial.println(F("# Phone telemetry profile: final-angle only (currently IMU knee)"));
  Serial.print(F("# Serial stream mode: "));
  Serial.println(serialStreamModeLabel());
  Serial.println(F("# Output: SIMPLE,time_ms,master_imu_deg,slave_imu_deg,knee_imu_deg,fused_knee_deg,flex_raw_adc,flex_angle_deg,pot_raw_adc,pot_angle_deg,ble_state"));
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

bool tryParsePotCalibrationAngle(const char* command, float& angleDeg) {
  char* end_ptr = nullptr;
  const float parsed = strtof(command, &end_ptr);
  if (end_ptr == command || *end_ptr != '\0') {
    return false;
  }
  if (!isfinite(parsed)) {
    return false;
  }
  if (parsed < MasterConfig::kKneeAngleMinDeg || parsed > MasterConfig::kKneeAngleMaxDeg) {
    return false;
  }
  angleDeg = parsed;
  return true;
}

void endPotCalibrationLabel(uint32_t nowMs) {
  if (!potCalibrationLabelActive) {
    return;
  }

  Serial.print(F("LABEL_END,"));
  Serial.print(nowMs);
  Serial.print(F(","));
  Serial.println(potCalibrationLabelDeg, 1);
  potCalibrationLabelActive = false;
}

void startPotCalibrationLabel(float angleDeg, uint32_t nowMs) {
  if (potCalibrationLabelActive) {
    endPotCalibrationLabel(nowMs);
  }

  potCalibrationLabelActive = true;
  potCalibrationLabelDeg = angleDeg;
  potCalibrationLabelEndMs = nowMs + MasterConfig::kPotCalibrationCaptureWindowMs;

  Serial.print(F("LABEL_START,"));
  Serial.print(nowMs);
  Serial.print(F(","));
  Serial.print(angleDeg, 1);
  Serial.print(F(","));
  Serial.println(MasterConfig::kPotCalibrationCaptureWindowMs);
}

void updatePotCalibrationLabel(uint32_t nowMs) {
  if (!potCalibrationLabelActive) {
    return;
  }

  if (static_cast<int32_t>(nowMs - potCalibrationLabelEndMs) >= 0) {
    endPotCalibrationLabel(nowMs);
  }
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
      recoveryDisconnectCount = 0U;
    }

    if (recoveryStartedMs != 0UL &&
        (nowMs - recoveryStartedMs) >= MasterConfig::kConnectionResetTimeoutMs) {
      Serial.println(F("# Master-slave link kept flapping and never became stable."));
      resetBoard();
    }

    return;
  }

  if (lastSlaveLinkHealthy) {
    if (recoveryStartedMs == 0UL) {
      recoveryStartedMs = nowMs;
    }
    ++recoveryDisconnectCount;
    connectedSinceMs = 0UL;
    lastSlaveLinkHealthy = false;
    Serial.println(F("# Master lost slave link, recovery watchdog armed."));
    if (recoveryDisconnectCount >= MasterConfig::kConnectionResetDisconnectCount) {
      Serial.println(F("# Master exceeded disconnect flap limit during recovery."));
      resetBoard();
    }
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

bool trySetSerialStreamMode(const char* command) {
  if (strcmp(command, "mode fast") == 0 || strcmp(command, "fast") == 0 ||
      strcmp(command, "stream runtime") == 0 || strcmp(command, "runtime") == 0) {
    serialStreamMode = SerialStreamMode::kRuntime;
    Serial.println(F("# Serial stream mode set to RUNTIME."));
    return true;
  }
  if (strcmp(command, "stream pot") == 0 || strcmp(command, "pot") == 0) {
    serialStreamMode = SerialStreamMode::kPotCalibration;
    Serial.println(F("# Serial stream mode set to POT_CAL."));
    return true;
  }
  if (strcmp(command, "stream flex") == 0 || strcmp(command, "flex") == 0) {
    serialStreamMode = SerialStreamMode::kFlexCalibration;
    Serial.println(F("# Serial stream mode set to FLEX_CAL."));
    return true;
  }
  if (strcmp(command, "stream imu") == 0 || strcmp(command, "imu") == 0) {
    serialStreamMode = SerialStreamMode::kImuCalibration;
    Serial.println(F("# Serial stream mode set to IMU_CAL."));
    return true;
  }
  if (strcmp(command, "mode normal") == 0 || strcmp(command, "normal") == 0 ||
      strcmp(command, "stream normal") == 0) {
    serialStreamMode = SerialStreamMode::kNormal;
    Serial.println(F("# Serial stream mode set to NORMAL."));
    return true;
  }
  return false;
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

  if (trySetSerialStreamMode(command)) {
    return;
  }

  float calibrationAngleDeg = 0.0f;
  if (tryParsePotCalibrationAngle(command, calibrationAngleDeg)) {
    startPotCalibrationLabel(calibrationAngleDeg, millis());
    Serial.print(F("# POT calibration label accepted: "));
    Serial.println(calibrationAngleDeg, 1);
    return;
  }

  Serial.println(F("# Ignored command. Use h, z, r, x/reset, mode normal, mode fast, or a numeric angle label."));
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
  Serial.print(snapshot.fusedKneeDeg, 2);
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

void printPotCalibrationLine(const RuntimeSnapshot& snapshot) {
  Serial.print(F("POT_SAMPLE,"));
  Serial.print(millis());
  Serial.print(F(","));
  Serial.print(snapshot.potRawAdc);
  Serial.print(F(","));
  Serial.print(snapshot.potFilteredAdc, 2);
  Serial.print(F(","));
  Serial.print(snapshot.potVoltage, 4);
  Serial.print(F(","));
  Serial.print(snapshot.potAngleDeg, 2);
  Serial.print(F(","));
  if (potCalibrationLabelActive) {
    Serial.println(potCalibrationLabelDeg, 1);
  } else {
    Serial.println(F("nan"));
  }
}

void printFlexCalibrationLine(const RuntimeSnapshot& snapshot) {
  Serial.print(F("FLEX_SAMPLE,"));
  Serial.print(millis());
  Serial.print(F(","));
  Serial.print(snapshot.flexRawAdc);
  Serial.print(F(","));
  Serial.print(flexSensor.reading().filteredAdc, 2);
  Serial.print(F(","));
  Serial.print(flexSensor.reading().voltage, 4);
  Serial.print(F(","));
  if (flexSensor.reading().valid) {
    Serial.print(flexSensor.reading().resistanceOhms, 2);
  } else {
    Serial.print(F("nan"));
  }
  Serial.print(F(","));
  Serial.print(snapshot.flexAngleDeg, 2);
  Serial.print(F(","));
  if (potCalibrationLabelActive) {
    Serial.println(potCalibrationLabelDeg, 1);
  } else {
    Serial.println(F("nan"));
  }
}

void printImuCalibrationLine(const RuntimeSnapshot& snapshot) {
  Serial.print(F("IMU_SAMPLE,"));
  Serial.print(millis());
  Serial.print(F(","));
  Serial.print(snapshot.masterImuDeg, 2);
  Serial.print(F(","));
  Serial.print(snapshot.slaveImuDeg, 2);
  Serial.print(F(","));
  Serial.print(snapshot.kneeImuDeg, 2);
  Serial.print(F(","));
  Serial.print(snapshot.kneeImuDeg, 2);
  Serial.print(F(","));
  if (potCalibrationLabelActive) {
    Serial.println(potCalibrationLabelDeg, 1);
  } else {
    Serial.println(F("nan"));
  }
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
  packet.sequence = phoneTelemetrySequence++;
  packet.uptimeMs = millis();
  packet.finalAngleDeg = snapshot.kneeImuDeg;
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
  Wire.setWireTimeout(1000, true);
  Wire.clearWireTimeoutFlag();
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

  setPhase("CEN");
  bleCentral.poll();
  setPhase("PHN");
  phoneBle.poll();
  setPhase("WDOG");
  updateConnectionWatchdog(nowMs);
  updatePotCalibrationLabel(nowMs);
  setPhase("SER");
  handleSerialCommands();
  setPhase("CMD");
  handlePhoneCommands();

  if (nowMs - lastImuSampleMs >= MasterConfig::kImuSampleIntervalMs) {
    setPhase("IMU");
    lastImuSampleMs = nowMs;
    thighImu.update();
  }

  if (nowMs - lastAnalogSampleMs >= MasterConfig::kAnalogSampleIntervalMs) {
    setPhase("ADC");
    lastAnalogSampleMs = nowMs;
    flexSensor.update();
    potSensor.update();
  }

  setPhase("SNAP");
  const RuntimeSnapshot snapshot = makeSnapshot();

  if (nowMs - lastDashboardMs >= currentDashboardIntervalMs()) {
    setPhase("DASH");
    lastDashboardMs = nowMs;
    switch (serialStreamMode) {
      case SerialStreamMode::kPotCalibration:
        printPotCalibrationLine(snapshot);
        break;
      case SerialStreamMode::kFlexCalibration:
        printFlexCalibrationLine(snapshot);
        break;
      case SerialStreamMode::kImuCalibration:
        printImuCalibrationLine(snapshot);
        break;
      case SerialStreamMode::kRuntime:
      case SerialStreamMode::kNormal:
      default:
        printSimpleLine(snapshot);
        break;
    }
  }

  if (nowMs - lastPhoneTelemetryMs >= MasterConfig::kPhoneTelemetryIntervalMs) {
    setPhase("TX");
    lastPhoneTelemetryMs = nowMs;
    const KneePhoneBle::TelemetryPacketV1 telemetry = makePhoneTelemetryPacket(snapshot);
    const KneePhoneBle::StatusPacketV1 status = makePhoneStatusPacket(telemetry.sequence);
    phoneBle.updateTelemetry(telemetry, status);
  }

  if (nowMs - lastOledUpdateMs >= MasterConfig::kOledUpdateIntervalMs) {
    setPhase("OLED");
    lastOledUpdateMs = nowMs;
    const bool oledOk = oledDisplay.render({snapshot.masterImuDeg,
                                            snapshot.slaveImuDeg,
                                            snapshot.kneeImuDeg,
                                            zeroReferences.applied,
                                            phoneBle.isPhoneConnected(),
                                            bleCentral.stateText(),
                                            currentPhase});
    if (!oledOk) {
      Serial.println(F("# OLED render timeout/failure detected."));
      if (oledDisplay.recoverFromTimeout()) {
        Serial.println(F("# OLED recovered after timeout."));
      } else {
        Serial.println(F("# OLED recovery failed; continuing without display."));
      }
    }
  }

  setPhase("IDLE");
}
