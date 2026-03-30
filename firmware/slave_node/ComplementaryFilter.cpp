#include "ComplementaryFilter.h"

ComplementaryFilter::ComplementaryFilter() : angleDeg_(0.0f), initialized_(false) {}

void ComplementaryFilter::begin(float initialAngleDeg) {
  angleDeg_ = initialAngleDeg;
  initialized_ = true;
}

float ComplementaryFilter::update(float gyroRateDegPerSec, float accelAngleDeg, float dtSeconds, float alpha) {
  if (!initialized_) {
    begin(accelAngleDeg);
  }

  const float gyroIntegratedDeg = angleDeg_ + (gyroRateDegPerSec * dtSeconds);
  angleDeg_ = (alpha * gyroIntegratedDeg) + ((1.0f - alpha) * accelAngleDeg);
  return angleDeg_;
}

float ComplementaryFilter::angleDeg() const {
  return angleDeg_;
}
