#pragma once

#include <Arduino.h>
#include <LSM6DS3.h>
#include <Wire.h>

struct ImuSample {
  float accelX_g;
  float accelY_g;
  float accelZ_g;
  float gyroX_dps;
  float gyroY_dps;
  float gyroZ_dps;
  float accelPitchDeg;
  float accelRollDeg;
};

class ImuManager {
 public:
  ImuManager();

  bool begin();
  bool readSample(ImuSample& sample);

 private:
  LSM6DS3 imu_;
};
