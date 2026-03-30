#include "SegmentOrientationEstimator.h"

#include <math.h>

#include "AppConfig.h"

namespace {

float computeAdaptiveAlpha(float gyroX_dps, float gyroY_dps) {
  const float motionDps = fmaxf(fabsf(gyroX_dps), fabsf(gyroY_dps));
  if (motionDps <= MasterConfig::kGyroQuietThresholdDps) {
    return MasterConfig::kComplementaryAlphaSettled;
  }
  if (motionDps >= MasterConfig::kGyroFastThresholdDps) {
    return MasterConfig::kComplementaryAlphaMoving;
  }

  const float span = MasterConfig::kGyroFastThresholdDps - MasterConfig::kGyroQuietThresholdDps;
  const float ratio = (motionDps - MasterConfig::kGyroQuietThresholdDps) / span;
  return MasterConfig::kComplementaryAlphaSettled +
         (ratio * (MasterConfig::kComplementaryAlphaMoving - MasterConfig::kComplementaryAlphaSettled));
}

}  // namespace

SegmentOrientationEstimator::SegmentOrientationEstimator()
    : latestSample_{},
      fusedPitchDeg_(0.0f),
      fusedRollDeg_(0.0f),
      lastUpdateMicros_(0),
      healthy_(false) {}

bool SegmentOrientationEstimator::begin() {
  if (!imu_.begin()) {
    healthy_ = false;
    return false;
  }

  if (!imu_.readSample(latestSample_)) {
    healthy_ = false;
    return false;
  }

  fusedPitchDeg_ = latestSample_.accelPitchDeg * MasterConfig::kPitchSign;
  fusedRollDeg_ = latestSample_.accelRollDeg * MasterConfig::kRollSign;
  pitchFilter_.begin(fusedPitchDeg_);
  rollFilter_.begin(fusedRollDeg_);
  healthy_ = true;
  return true;
}

bool SegmentOrientationEstimator::update() {
  ImuSample sample;
  if (!imu_.readSample(sample)) {
    healthy_ = false;
    return false;
  }

  latestSample_ = sample;

  const uint32_t nowMicros = micros();
  float dtSeconds = 0.0f;
  if (lastUpdateMicros_ != 0U) {
    dtSeconds = (nowMicros - lastUpdateMicros_) * 1.0e-6f;
  }
  lastUpdateMicros_ = nowMicros;

  if (dtSeconds <= 0.0f || dtSeconds > 0.25f) {
    fusedPitchDeg_ = sample.accelPitchDeg * MasterConfig::kPitchSign;
    fusedRollDeg_ = sample.accelRollDeg * MasterConfig::kRollSign;
    pitchFilter_.begin(fusedPitchDeg_);
    rollFilter_.begin(fusedRollDeg_);
  } else {
    const float adaptiveAlpha = computeAdaptiveAlpha(sample.gyroX_dps, sample.gyroY_dps);
    fusedPitchDeg_ = pitchFilter_.update(sample.gyroY_dps * MasterConfig::kPitchGyroSign,
                                         sample.accelPitchDeg * MasterConfig::kPitchSign,
                                         dtSeconds,
                                         adaptiveAlpha);
    fusedRollDeg_ = rollFilter_.update(sample.gyroX_dps * MasterConfig::kRollGyroSign,
                                       sample.accelRollDeg * MasterConfig::kRollSign,
                                       dtSeconds,
                                       adaptiveAlpha);
  }

  healthy_ = true;
  return true;
}

bool SegmentOrientationEstimator::isHealthy() const {
  return healthy_;
}

const ImuSample& SegmentOrientationEstimator::sample() const {
  return latestSample_;
}

float SegmentOrientationEstimator::fusedPitchDeg() const {
  return fusedPitchDeg_;
}

float SegmentOrientationEstimator::fusedRollDeg() const {
  return fusedRollDeg_;
}

float SegmentOrientationEstimator::primaryAngleDeg() const {
  return MasterConfig::kUsePitchAsPrimaryAxis ? fusedPitchDeg_ : fusedRollDeg_;
}
