#pragma once

#include <Arduino.h>

class CalibrationSession {
 public:
  CalibrationSession();

  void beginLabel(float labelDeg, uint32_t durationMs, uint32_t startMs);
  void update(uint32_t nowMs);
  void clear();

  bool isActive() const;
  float activeLabelDeg() const;
  uint32_t startMs() const;
  uint32_t endMs() const;
  uint32_t remainingMs(uint32_t nowMs) const;

 private:
  bool active_;
  float activeLabelDeg_;
  uint32_t startMs_;
  uint32_t endMs_;
};
