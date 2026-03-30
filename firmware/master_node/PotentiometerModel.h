#pragma once

#include <Arduino.h>

#include "AnalogChannel.h"

struct PotentiometerReading {
  uint16_t rawAdc;
  float filteredAdc;
  float voltage;
  float angleDeg;
};

class PotentiometerModel {
 public:
  explicit PotentiometerModel(uint8_t pin);

  void begin();
  void update();

  const PotentiometerReading& reading() const;

 private:
  AnalogChannel channel_;
  PotentiometerReading reading_;
};
