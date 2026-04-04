#pragma once

#include <Arduino.h>

struct SensorFusionInput {
  bool imuValid;
  float imuAngleDeg;
  bool flexValid;
  float flexAngleDeg;
  bool potValid;
  float potAngleDeg;
};

struct SensorFusionResult {
  bool valid;
  float fusedAngleDeg;
  float imuWeight;
  float flexWeight;
  float potWeight;
};

class SensorFusion {
 public:
  SensorFusionResult fuse(const SensorFusionInput& input) const;

 private:
  static float clampKneeAngle(float angleDeg);
};
