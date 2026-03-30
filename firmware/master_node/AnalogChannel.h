#pragma once

#include <Arduino.h>

#include "AppConfig.h"
#include "MovingAverageFilter.h"

class AnalogChannel {
 public:
  explicit AnalogChannel(uint8_t pin);

  void begin();
  void update();

  uint16_t rawAdc() const;
  float filteredAdc() const;
  float voltage() const;

 private:
  uint8_t pin_;
  uint16_t rawAdc_;
  float filteredAdc_;
  MovingAverageFilter<MasterConfig::kAnalogMovingAverageWindow> filter_;
};
