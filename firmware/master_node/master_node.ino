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
uint32_t lastDebugHeartbeatMs = 0;
uint16_t phoneTelemetrySequence = 0;
uint32_t recoveryStartedMs = 0;
uint32_t connectedSinceMs = 0;
bool lastSlaveLinkHealthy = false;
uint8_t recoveryDisconnectCount = 0;
const char* currentPhase = "BOOT";

uint32_t loopCount = 0;
uint32_t centralPollCount = 0;
uint32_t phonePollCount = 0;
uint32_t imuUpdateCount = 0;
uint32_t analogUpdateCount = 0;
uint32_t dashboardPrintCount = 0;
uint32_t oledRenderCount = 0;
uint32_t oledRecoverCount = 0;
uint32_t oledTimeoutCount = 0;
uint32_t phoneTxBeginCount = 0;
uint32_t phoneTxEndCount = 0;
uint32_t phoneTxFailCount = 0;
uint32_t serialCommandCount = 0;
uint32_t phoneCommandCount = 0;
bool potCalibrationLabelActive = false;
float potCalibrationLabelDeg = 0.0f;
uint32_t potCalibrationLabelEndMs = 0;

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
  Serial.println(F("# Commands: h, z, r, x/reset, or any numeric angle 0..145 for POT calibration labels"));
  Serial.println(F("# Fusion weights: IMU=0.475 POT=0.475 FLEX=0.05"));
  Serial.print(F("# Primary IMU axis: "));
  Serial.println(MasterConfig::kUsePitchAsPrimaryAxis ? F("PITCH") : F("ROLL"));
  Serial.println(F("# Phone telemetry profile: final-angle only (currently IMU knee)"));
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

void handleCommand(const char* command) {
  ++serialCommandCount;
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

  float calibrationAngleDeg = 0.0f;
  if (tryParsePotCalibrationAngle(command, calibrationAngleDeg)) {
    startPotCalibrationLabel(calibrationAngleDeg, millis());
    Serial.print(F("# POT calibration label accepted: "));
    Serial.println(calibrationAngleDeg, 1);
    return;
  }

  Serial.println(F("# Ignored command. Use h, z, r, x/reset, or a numeric angle label."));
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

  ++phoneCommandCount;
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

void printDebugHeartbeat(const RuntimeSnapshot& snapshot) {
  Serial.print(F("# HEARTBEAT,"));
  Serial.print(millis());
  Serial.print(F(",phase="));
  Serial.print(currentPhase);
  Serial.print(F(",ble="));
  Serial.print(bleCentral.stateText());
  Serial.print(F(",pkt_age="));
  Serial.print(bleCentral.hasPacket() ? bleCentral.packetAgeMs() : 0UL);
  Serial.print(F(",master="));
  Serial.print(snapshot.masterImuDeg, 2);
  Serial.print(F(",slave="));
  Serial.print(snapshot.slaveImuDeg, 2);
  Serial.print(F(",knee="));
  Serial.print(snapshot.kneeImuDeg, 2);
  Serial.print(F(",fused="));
  Serial.print(snapshot.fusedKneeDeg, 2);
  Serial.print(F(",w_imu="));
  Serial.print(snapshot.fusedImuWeight, 3);
  Serial.print(F(",w_flex="));
  Serial.print(snapshot.fusedFlexWeight, 3);
  Serial.print(F(",w_pot="));
  Serial.print(snapshot.fusedPotWeight, 3);
  Serial.print(F(",loops="));
  Serial.print(loopCount);
  Serial.print(F(",cen="));
  Serial.print(centralPollCount);
  Serial.print(F(",phn="));
  Serial.print(phonePollCount);
  Serial.print(F(",imu="));
  Serial.print(imuUpdateCount);
  Serial.print(F(",adc="));
  Serial.print(analogUpdateCount);
  Serial.print(F(",dash="));
  Serial.print(dashboardPrintCount);
  Serial.print(F(",oled="));
  Serial.print(oledRenderCount);
  Serial.print(F(",oled_rec="));
  Serial.print(oledRecoverCount);
  Serial.print(F(",oled_to="));
  Serial.print(oledTimeoutCount);
  Serial.print(F(",tx_beg="));
  Serial.print(phoneTxBeginCount);
  Serial.print(F(",tx_end="));
  Serial.print(phoneTxEndCount);
  Serial.print(F(",tx_fail="));
  Serial.print(phoneTxFailCount);
  Serial.print(F(",ser_cmd="));
  Serial.print(serialCommandCount);
  Serial.print(F(",phn_cmd="));
  Serial.println(phoneCommandCount);
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
  if (Serial) {
    Serial.println(F("# Debug heartbeat enabled."));
  }
}

void loop() {
  ++loopCount;
  const uint32_t nowMs = millis();

  setPhase("CEN");
  bleCentral.poll();
  ++centralPollCount;
  setPhase("PHN");
  phoneBle.poll();
  ++phonePollCount;
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
    ++imuUpdateCount;
  }

  if (nowMs - lastAnalogSampleMs >= MasterConfig::kAnalogSampleIntervalMs) {
    setPhase("ADC");
    lastAnalogSampleMs = nowMs;
    flexSensor.update();
    potSensor.update();
    ++analogUpdateCount;
  }

  setPhase("SNAP");
  const RuntimeSnapshot snapshot = makeSnapshot();

  if (nowMs - lastDashboardMs >= MasterConfig::kDashboardIntervalMs) {
    setPhase("DASH");
    lastDashboardMs = nowMs;
    printSimpleLine(snapshot);
    printPotCalibrationLine(snapshot);
    ++dashboardPrintCount;
  }

  if (nowMs - lastDebugHeartbeatMs >= MasterConfig::kDebugHeartbeatIntervalMs) {
    setPhase("HBT");
    lastDebugHeartbeatMs = nowMs;
    printDebugHeartbeat(snapshot);
  }

  if (nowMs - lastPhoneTelemetryMs >= MasterConfig::kPhoneTelemetryIntervalMs) {
    setPhase("TX");
    lastPhoneTelemetryMs = nowMs;
    const KneePhoneBle::TelemetryPacketV1 telemetry = makePhoneTelemetryPacket(snapshot);
    const KneePhoneBle::StatusPacketV1 status = makePhoneStatusPacket(telemetry.sequence);
    ++phoneTxBeginCount;
    Serial.print(F("# DBG,TX_BEGIN,"));
    Serial.print(nowMs);
    Serial.print(F(","));
    Serial.println(telemetry.sequence);
    const bool txOk = phoneBle.updateTelemetry(telemetry, status);
    ++phoneTxEndCount;
    if (!txOk) {
      ++phoneTxFailCount;
    }
    Serial.print(F("# DBG,TX_END,"));
    Serial.print(millis());
    Serial.print(F(","));
    Serial.print(telemetry.sequence);
    Serial.print(F(","));
    Serial.println(txOk ? F("OK") : F("FAIL"));
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
    ++oledRenderCount;
    if (!oledOk) {
      ++oledTimeoutCount;
      Serial.println(F("# OLED render timeout/failure detected."));
      if (oledDisplay.recoverFromTimeout()) {
        ++oledRecoverCount;
        Serial.println(F("# OLED recovered after timeout."));
      } else {
        Serial.println(F("# OLED recovery failed; continuing without display."));
      }
    }
  }

  setPhase("IDLE");
}
