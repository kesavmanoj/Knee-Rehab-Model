#pragma once

#include <Arduino.h>

#include "ComplementaryFilter.h"
#include "ImuManager.h"

class SegmentOrientationEstimator {
 public:
  SegmentOrientationEstimator();

  bool begin();
  bool update();

  bool isHealthy() const;
  const ImuSample& sample() const;
  float fusedPitchDeg() const;
  float fusedRollDeg() const;
  float primaryAngleDeg() const;

 private:
  ImuManager imu_;
  ComplementaryFilter pitchFilter_;
  ComplementaryFilter rollFilter_;
  ImuSample latestSample_;
  float fusedPitchDeg_;
  float fusedRollDeg_;
  uint32_t lastUpdateMicros_;
  bool healthy_;
};
