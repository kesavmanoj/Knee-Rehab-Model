#pragma once

#include <Arduino.h>

#include "AnalogChannel.h"
#include "AppConfig.h"

struct FlexSensorReading {
  uint16_t rawAdc;
  float filteredAdc;
  float voltage;
  float resistanceOhms;
  float angleDeg;
  bool valid;
};

class FlexSensorModel {
 public:
  FlexSensorModel(uint8_t pin,
                  float fixedResistorOhms,
                  const MasterConfig::FlexCalibrationPoint* calibrationTable,
                  size_t calibrationTableSize);

  void begin();
  void update();

  const FlexSensorReading& reading() const;

 private:
  float computeResistanceOhms(float voltage) const;
  float interpolateAngleDeg(float resistanceOhms) const;

  AnalogChannel channel_;
  float fixedResistorOhms_;
  const MasterConfig::FlexCalibrationPoint* calibrationTable_;
  size_t calibrationTableSize_;
  FlexSensorReading reading_;
};
