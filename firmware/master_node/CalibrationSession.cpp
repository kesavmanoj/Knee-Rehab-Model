#include "CalibrationSession.h"

CalibrationSession::CalibrationSession()
    : active_(false),
      activeLabelDeg_(0.0f),
      startMs_(0),
      endMs_(0) {}

void CalibrationSession::beginLabel(float labelDeg, uint32_t durationMs, uint32_t startMs) {
  active_ = true;
  activeLabelDeg_ = labelDeg;
  startMs_ = startMs;
  endMs_ = startMs + durationMs;
}

void CalibrationSession::update(uint32_t nowMs) {
  if (active_ && nowMs >= endMs_) {
    active_ = false;
  }
}

void CalibrationSession::clear() {
  active_ = false;
  activeLabelDeg_ = 0.0f;
  startMs_ = 0;
  endMs_ = 0;
}

bool CalibrationSession::isActive() const {
  return active_;
}

float CalibrationSession::activeLabelDeg() const {
  return activeLabelDeg_;
}

uint32_t CalibrationSession::startMs() const {
  return startMs_;
}

uint32_t CalibrationSession::endMs() const {
  return endMs_;
}

uint32_t CalibrationSession::remainingMs(uint32_t nowMs) const {
  if (!active_ || nowMs >= endMs_) {
    return 0UL;
  }
  return endMs_ - nowMs;
}
