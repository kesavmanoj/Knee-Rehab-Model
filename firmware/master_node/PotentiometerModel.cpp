#include "PotentiometerModel.h"

#include "AppConfig.h"

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
  reading_.angleDeg = (reading_.filteredAdc / MasterConfig::kAdcFullScale) * MasterConfig::kPotMaxAngleDeg;
}

const PotentiometerReading& PotentiometerModel::reading() const {
  return reading_;
}
