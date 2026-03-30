#include "AnalogChannel.h"

AnalogChannel::AnalogChannel(uint8_t pin) : pin_(pin), rawAdc_(0), filteredAdc_(0.0f) {}

void AnalogChannel::begin() {
  pinMode(pin_, INPUT);
  rawAdc_ = static_cast<uint16_t>(analogRead(pin_));
  filteredAdc_ = rawAdc_;
  filter_.reset(filteredAdc_);
}

void AnalogChannel::update() {
  rawAdc_ = static_cast<uint16_t>(analogRead(pin_));
  filteredAdc_ = filter_.add(static_cast<float>(rawAdc_));
}

uint16_t AnalogChannel::rawAdc() const {
  return rawAdc_;
}

float AnalogChannel::filteredAdc() const {
  return filteredAdc_;
}

float AnalogChannel::voltage() const {
  return (filteredAdc_ / MasterConfig::kAdcFullScale) * MasterConfig::kAnalogReferenceVoltage;
}
