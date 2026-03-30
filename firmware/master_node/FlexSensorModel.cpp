#include "FlexSensorModel.h"

#include <math.h>

namespace {
constexpr float kMinVoltageMargin = 0.001f;
}

FlexSensorModel::FlexSensorModel(uint8_t pin,
                                 float fixedResistorOhms,
                                 const MasterConfig::FlexCalibrationPoint* calibrationTable,
                                 size_t calibrationTableSize)
    : channel_(pin),
      fixedResistorOhms_(fixedResistorOhms),
      calibrationTable_(calibrationTable),
      calibrationTableSize_(calibrationTableSize),
      reading_{} {}

void FlexSensorModel::begin() {
  channel_.begin();
  update();
}

void FlexSensorModel::update() {
  channel_.update();

  reading_.rawAdc = channel_.rawAdc();
  reading_.filteredAdc = channel_.filteredAdc();
  reading_.voltage = channel_.voltage();
  reading_.resistanceOhms = computeResistanceOhms(reading_.voltage);
  reading_.valid = isfinite(reading_.resistanceOhms);
  reading_.angleDeg = reading_.valid ? interpolateAngleDeg(reading_.resistanceOhms) : 0.0f;
}

const FlexSensorReading& FlexSensorModel::reading() const {
  return reading_;
}

float FlexSensorModel::computeResistanceOhms(float voltage) const {
  const float vRef = MasterConfig::kAnalogReferenceVoltage;
  if (voltage <= kMinVoltageMargin || voltage >= (vRef - kMinVoltageMargin)) {
    return NAN;
  }

  if (MasterConfig::kFlexSensorUsesHighSideDivider) {
    return fixedResistorOhms_ * (voltage / (vRef - voltage));
  }

  return fixedResistorOhms_ * ((vRef - voltage) / voltage);
}

float FlexSensorModel::interpolateAngleDeg(float resistanceOhms) const {
  if (calibrationTableSize_ == 0U) {
    return 0.0f;
  }

  if (resistanceOhms <= calibrationTable_[0].resistanceOhms) {
    return calibrationTable_[0].angleDeg;
  }

  for (size_t i = 1; i < calibrationTableSize_; ++i) {
    const auto& left = calibrationTable_[i - 1];
    const auto& right = calibrationTable_[i];
    if (resistanceOhms <= right.resistanceOhms) {
      const float span = right.resistanceOhms - left.resistanceOhms;
      if (span <= 0.0f) {
        return right.angleDeg;
      }

      const float ratio = (resistanceOhms - left.resistanceOhms) / span;
      return left.angleDeg + (ratio * (right.angleDeg - left.angleDeg));
    }
  }

  return calibrationTable_[calibrationTableSize_ - 1U].angleDeg;
}
