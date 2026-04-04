#pragma once

#include <Arduino.h>
#include <U8g2lib.h>
#include <Wire.h>

struct OledDisplayData {
  float masterAngleDeg;
  float slaveAngleDeg;
  float kneeAngleDeg;
  bool zeroed;
  bool phoneConnected;
  const char* bleState;
  const char* phaseText;
};

class OledDisplayManager {
 public:
  OledDisplayManager();

  bool begin();
  bool render(const OledDisplayData& data);
  bool isAvailable() const;
  bool recoverFromTimeout();

 private:
  U8G2_SSD1306_128X64_NONAME_F_HW_I2C display_;
  bool available_;
};
