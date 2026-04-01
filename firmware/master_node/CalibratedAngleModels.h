#pragma once

#include <Arduino.h>

#include "AppConfig.h"
#include "GeneratedCalibration.h"

namespace CalibratedAngleModels {

inline float clampAngle(float angleDeg) {
  if (angleDeg < MasterConfig::kCalibrationMinAngleDeg) {
    return MasterConfig::kCalibrationMinAngleDeg;
  }
  if (angleDeg > MasterConfig::kCalibrationMaxAngleDeg) {
    return MasterConfig::kCalibrationMaxAngleDeg;
  }
  return angleDeg;
}

inline float potAngleFromRawAdc(uint16_t rawAdc) {
  const float adc = static_cast<float>(rawAdc);
  return clampAngle((GeneratedCalibration::kPotRawAdcSlope * adc) + GeneratedCalibration::kPotRawAdcIntercept);
}

inline float flexAngleFromRawAdc(uint16_t rawAdc) {
  const float adc = static_cast<float>(rawAdc);
  const auto& coefficients = GeneratedCalibration::kFlexQuadraticCoefficients;
  const float angleDeg = ((coefficients[0] * adc * adc) + (coefficients[1] * adc) + coefficients[2]);
  return clampAngle(angleDeg);
}

inline float imuAngleFromRawKneeAngle(float rawKneeAngleDeg) {
  return clampAngle(rawKneeAngleDeg);
}

}  // namespace CalibratedAngleModels
