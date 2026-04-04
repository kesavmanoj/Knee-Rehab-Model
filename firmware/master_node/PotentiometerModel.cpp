#include "PotentiometerModel.h"

#include "AppConfig.h"
#include "GeneratedCalibration.h"

PotentiometerModel::PotentiometerModel(uint8_t pin) : channel_(pin), reading_{} {}

void PotentiometerModel::begin() {
  channel_.begin();
  update();
}

void PotentiometerModel::update() {
  channel_.update();

  reading_.rawAdc = channel_.rawAdc();
  reading_.filteredAdc = channel_.filteredAdc();
  reading_.voltage = channel_.voltage();
  reading_.angleDeg =
      (GeneratedCalibration::kPotRawAdcSlope * reading_.filteredAdc) +
      GeneratedCalibration::kPotRawAdcIntercept;
}

const PotentiometerReading& PotentiometerModel::reading() const {
  return reading_;
}
