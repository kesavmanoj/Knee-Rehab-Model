#include "SensorFusion.h"

#include <math.h>

#include "AppConfig.h"

namespace {

float normalizeWeight(float weight, float totalWeight) {
  if (totalWeight <= 0.0f) {
    return 0.0f;
  }
  return weight / totalWeight;
}

}  // namespace

SensorFusionResult SensorFusion::fuse(const SensorFusionInput& input) const {
  float imuWeight = input.imuValid ? MasterConfig::kImuFusionBaseWeight : 0.0f;
  float flexWeight = input.flexValid ? MasterConfig::kFlexFusionBaseWeight : 0.0f;
  float potWeight = input.potValid ? MasterConfig::kPotFusionBaseWeight : 0.0f;

  const float totalWeight = imuWeight + flexWeight + potWeight;
  if (totalWeight <= 0.0f) {
    return {false, 0.0f, 0.0f, 0.0f, 0.0f};
  }

  imuWeight = normalizeWeight(imuWeight, totalWeight);
  flexWeight = normalizeWeight(flexWeight, totalWeight);
  potWeight = normalizeWeight(potWeight, totalWeight);

  const float fusedAngleDeg = clampKneeAngle((imuWeight * input.imuAngleDeg) +
                                             (flexWeight * input.flexAngleDeg) +
                                             (potWeight * input.potAngleDeg));
  return {true, fusedAngleDeg, imuWeight, flexWeight, potWeight};
}

float SensorFusion::clampKneeAngle(float angleDeg) {
  if (!isfinite(angleDeg)) {
    return 0.0f;
  }

  if (angleDeg < MasterConfig::kKneeAngleMinDeg) {
    return MasterConfig::kKneeAngleMinDeg;
  }
  if (angleDeg > MasterConfig::kKneeAngleMaxDeg) {
    return MasterConfig::kKneeAngleMaxDeg;
  }
  return angleDeg;
}
