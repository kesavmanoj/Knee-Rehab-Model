#include "ImuManager.h"

#include <math.h>

#include "AppConfig.h"

namespace {
constexpr float kRadToDeg = 57.2957795f;
}

ImuManager::ImuManager() : imu_(I2C_MODE, MasterConfig::kImuI2cAddress) {}

bool ImuManager::begin() {
  return imu_.begin() == 0;
}

bool ImuManager::readSample(ImuSample& sample) {
  sample.accelX_g = imu_.readFloatAccelX();
  sample.accelY_g = imu_.readFloatAccelY();
  sample.accelZ_g = imu_.readFloatAccelZ();
  sample.gyroX_dps = imu_.readFloatGyroX();
  sample.gyroY_dps = imu_.readFloatGyroY();
  sample.gyroZ_dps = imu_.readFloatGyroZ();

  const float ax = sample.accelX_g;
  const float ay = sample.accelY_g;
  const float az = sample.accelZ_g;

  sample.accelPitchDeg = atan2f(-ax, sqrtf((ay * ay) + (az * az))) * kRadToDeg;
  sample.accelRollDeg = atan2f(ay, az) * kRadToDeg;

  return isfinite(sample.accelPitchDeg) && isfinite(sample.accelRollDeg);
}
