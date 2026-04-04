#include "OledDisplayManager.h"

#include "AppConfig.h"

OledDisplayManager::OledDisplayManager()
    : display_(U8G2_R0, U8X8_PIN_NONE),
      available_(false) {}

bool OledDisplayManager::begin() {
  Wire.beginTransmission(MasterConfig::kOledI2cAddress);
  available_ = (Wire.endTransmission() == 0);
  if (!available_) {
    return false;
  }

  display_.begin();
  display_.clearBuffer();
  display_.setFont(u8g2_font_6x12_tf);
  display_.drawStr(0, 12, "Knee OLED online");
  display_.sendBuffer();
  return true;
}

bool OledDisplayManager::render(const OledDisplayData& data) {
  if (!available_) {
    return false;
  }

  char line[32];

  display_.clearBuffer();

  display_.setFont(u8g2_font_6x12_tf);
  display_.drawStr(0, 10, "KNEE ANGLE");

  display_.setFont(u8g2_font_logisoso20_tn);
  snprintf(line, sizeof(line), "%5.1f", data.kneeAngleDeg);
  display_.drawStr(0, 36, line);

  display_.setFont(u8g2_font_6x12_tf);
  display_.drawStr(78, 32, "deg");

  snprintf(line, sizeof(line), "M:%6.1f", data.masterAngleDeg);
  display_.drawStr(0, 49, line);

  snprintf(line, sizeof(line), "S:%6.1f", data.slaveAngleDeg);
  display_.drawStr(64, 49, line);

  snprintf(line, sizeof(line), "B:%s", data.bleState);
  display_.drawStr(0, 62, line);

  snprintf(line, sizeof(line), "H:%s", data.phoneConnected ? "Y" : "N");
  display_.drawStr(42, 62, line);

  snprintf(line, sizeof(line), "P:%s", data.phaseText != nullptr ? data.phaseText : "----");
  display_.drawStr(66, 62, line);

  snprintf(line, sizeof(line), "Z:%s", data.zeroed ? "Y" : "N");
  display_.drawStr(108, 62, line);

  display_.sendBuffer();
  if (Wire.getWireTimeoutFlag()) {
    Wire.clearWireTimeoutFlag();
    available_ = false;
    return false;
  }

  return true;
}

bool OledDisplayManager::isAvailable() const {
  return available_;
}

bool OledDisplayManager::recoverFromTimeout() {
  Wire.clearWireTimeoutFlag();
  Wire.beginTransmission(MasterConfig::kOledI2cAddress);
  available_ = (Wire.endTransmission() == 0);
  if (!available_) {
    return false;
  }

  display_.begin();
  display_.clearBuffer();
  display_.setFont(u8g2_font_6x12_tf);
  display_.drawStr(0, 12, "OLED recovered");
  display_.sendBuffer();

  if (Wire.getWireTimeoutFlag()) {
    Wire.clearWireTimeoutFlag();
    available_ = false;
    return false;
  }

  return true;
}
