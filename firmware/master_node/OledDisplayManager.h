#pragma once

#include <Arduino.h>
#include <U8g2lib.h>
#include <Wire.h>

struct OledDisplayData {
  float masterAngleDeg;
  float slaveAngleDeg;
  float kneeAngleDeg;
  bool zeroed;
  const char* bleState;
};

class OledDisplayManager {
 public:
  OledDisplayManager();

  bool begin();
  void render(const OledDisplayData& data);
  bool isAvailable() const;

 private:
  U8G2_SSD1306_128X64_NONAME_F_HW_I2C display_;
  bool available_;
};
