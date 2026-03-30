#include <Arduino.h>
#include <Wire.h>
#include <math.h>

#include "AppConfig.h"
#include "BleCentralManager.h"
#include "FlexSensorModel.h"
#include "OledDisplayManager.h"
#include "PotentiometerModel.h"
#include "SegmentOrientationEstimator.h"

namespace {

struct ZeroReferences {
  float masterImuDeg;
  float slaveImuDeg;
  float flex1Deg;
  float flex2Deg;
  float potDeg;
  bool applied;
};

struct AlignedImuPair {
  float masterRawDeg;
  float slaveRawDeg;
  uint16_t slaveSequence;
  uint32_t capturedAtMs;
  bool valid;
};

SegmentOrientationEstimator thighImu;
BleCentralManager bleCentral;
OledDisplayManager oledDisplay;
FlexSensorModel flex1(MasterConfig::kFlex1Pin,
                      MasterConfig::kFlex1FixedResistorOhms,
                      MasterConfig::kFlexCalibrationTable,
                      MasterConfig::kFlexCalibrationPointCount);
FlexSensorModel flex2(MasterConfig::kFlex2Pin,
                      MasterConfig::kFlex2FixedResistorOhms,
                      MasterConfig::kFlexCalibrationTable,
                      MasterConfig::kFlexCalibrationPointCount);
PotentiometerModel potentiometer(MasterConfig::kPotPin);

ZeroReferences zeroReferences{0.0f, 0.0f, 0.0f, 0.0f, 0.0f, false};
AlignedImuPair alignedImuPair{0.0f, 0.0f, 0U, 0UL, false};

uint32_t lastImuSampleMs = 0;
uint32_t lastAnalogSampleMs = 0;
uint32_t lastDashboardMs = 0;
uint32_t lastOledUpdateMs = 0;

float masterImuZeroedDeg() {
  if (alignedImuPair.valid) {
    return alignedImuPair.masterRawDeg - zeroReferences.masterImuDeg;
  }
  return thighImu.primaryAngleDeg() - zeroReferences.masterImuDeg;
}

float slaveImuRawDeg() {
  if (alignedImuPair.valid) {
    return alignedImuPair.slaveRawDeg;
  }
  return bleCentral.hasPacket() ? bleCentral.latestPacket().segmentAngleDeg : 0.0f;
}

float slaveImuZeroedDeg() {
  return slaveImuRawDeg() - zeroReferences.slaveImuDeg;
}

float imuRelativeAngleDeg() {
  return slaveImuZeroedDeg() - masterImuZeroedDeg();
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

float kneeAngleDeg() {
  return fabsf(wrapAngle180(imuRelativeAngleDeg()));
}

float flex1ZeroedDeg() {
  return flex1.reading().angleDeg - zeroReferences.flex1Deg;
}

float flex2ZeroedDeg() {
  return flex2.reading().angleDeg - zeroReferences.flex2Deg;
}

float potZeroedDeg() {
  return potentiometer.reading().angleDeg - zeroReferences.potDeg;
}

void printHelp() {
  Serial.println(F("Commands:"));
  Serial.println(F("  z -> zero all currently observed channels"));
  Serial.println(F("  r -> clear zero offsets"));
  Serial.println(F("  h -> show help"));
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

void applyZeroReferences() {
  const bool hadFreshSlavePacket = bleCentral.hasFreshPacket();
  zeroReferences.masterImuDeg = alignedImuPair.valid ? alignedImuPair.masterRawDeg : thighImu.primaryAngleDeg();
  zeroReferences.slaveImuDeg = slaveImuRawDeg();
  zeroReferences.flex1Deg = flex1.reading().angleDeg;
  zeroReferences.flex2Deg = flex2.reading().angleDeg;
  zeroReferences.potDeg = potentiometer.reading().angleDeg;
  zeroReferences.applied = true;

  Serial.println(F("Zero reference stored for master IMU, slave IMU, flex sensors, and potentiometer."));
  if (!hadFreshSlavePacket) {
    Serial.println(F("Warning: slave IMU was not fresh during zeroing, so the slave offset may need to be captured again."));
  }
}

void clearZeroReferences() {
  zeroReferences = {0.0f, 0.0f, 0.0f, 0.0f, 0.0f, false};
  Serial.println(F("Zero references cleared."));
}

void handleSerialCommands() {
  while (Serial.available() > 0) {
    const char command = static_cast<char>(Serial.read());
    if (command == 'z' || command == 'Z') {
      applyZeroReferences();
    } else if (command == 'r' || command == 'R') {
      clearZeroReferences();
    } else if (command == 'h' || command == 'H') {
      printHelp();
    }
  }
}

void printDashboard() {
  char line[96];

  snprintf(line,
           sizeof(line),
           "FLEX_D0_RAW:[%4u] | FILTERED:[%7.2f] | V:[%1.3f]",
           static_cast<unsigned>(flex1.reading().rawAdc),
           flex1.reading().filteredAdc,
           flex1.reading().voltage);

  Serial.println(line);
}

}  // namespace

void setup() {
  Serial.begin(MasterConfig::kSerialBaud);
  const uint32_t serialStart = millis();
  while (!Serial && (millis() - serialStart < 2000UL)) {
  }

  Wire.begin();
  analogReadResolution(12);

  Serial.println();
  Serial.println(F("Knee Rehab Master Node"));
  printHelp();

  if (!thighImu.begin()) {
    Serial.println(F("ERROR: Failed to initialize local IMU."));
    while (true) {
      delay(100);
    }
  }

  if (!bleCentral.begin()) {
    Serial.println(F("ERROR: Failed to initialize BLE central."));
    while (true) {
      delay(100);
    }
  }

  if (oledDisplay.begin()) {
    Serial.println(F("OLED display detected on I2C."));
  } else {
    Serial.println(F("Warning: SSD1306 OLED not detected at 0x3C."));
  }

  flex1.begin();
  flex2.begin();
  potentiometer.begin();

  Serial.println(F("Master sensing pipeline ready."));
}

void loop() {
  const uint32_t nowMs = millis();

  bleCentral.poll();
  if (bleCentral.consumeNewPacketFlag()) {
    latchAlignedImuPair();
  }
  handleSerialCommands();

  if (nowMs - lastImuSampleMs >= MasterConfig::kImuSampleIntervalMs) {
    lastImuSampleMs = nowMs;
    thighImu.update();
  }

  if (nowMs - lastAnalogSampleMs >= MasterConfig::kAnalogSampleIntervalMs) {
    lastAnalogSampleMs = nowMs;
    flex1.update();
    flex2.update();
    potentiometer.update();
  }

  if (nowMs - lastDashboardMs >= MasterConfig::kDashboardIntervalMs) {
    lastDashboardMs = nowMs;
    printDashboard();
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
