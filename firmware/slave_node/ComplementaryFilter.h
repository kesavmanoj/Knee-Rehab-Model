#pragma once

class ComplementaryFilter {
 public:
  ComplementaryFilter();

  void begin(float initialAngleDeg = 0.0f);
  float update(float gyroRateDegPerSec, float accelAngleDeg, float dtSeconds, float alpha);
  float angleDeg() const;

 private:
  float angleDeg_;
  bool initialized_;
};
