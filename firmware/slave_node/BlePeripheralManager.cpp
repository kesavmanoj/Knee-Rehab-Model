#include "BlePeripheralManager.h"

BlePeripheralManager* BlePeripheralManager::instance_ = nullptr;

BlePeripheralManager::BlePeripheralManager()
    : telemetryService_(KneeBle::kTelemetryServiceUuid),
      orientationCharacteristic_(KneeBle::kOrientationCharacteristicUuid,
                                 BLERead | BLENotify,
                                 sizeof(KneeBle::OrientationPacketV1)),
      connected_(false) {}

bool BlePeripheralManager::begin(const char* deviceName) {
  instance_ = this;

  if (!BLE.begin()) {
    Serial.println(F("# Slave BLE peripheral init failed."));
    return false;
  }

  BLE.setDeviceName(deviceName);
  BLE.setLocalName(deviceName);
  BLE.setAdvertisedService(telemetryService_);

  telemetryService_.addCharacteristic(orientationCharacteristic_);
  BLE.addService(telemetryService_);

  KneeBle::OrientationPacketV1 initialPacket{};
  initialPacket.version = KneeBle::kProtocolVersion;
  orientationCharacteristic_.writeValue(reinterpret_cast<const uint8_t*>(&initialPacket),
                                        sizeof(initialPacket));

  BLE.setEventHandler(BLEConnected, BlePeripheralManager::onBleConnected);
  BLE.setEventHandler(BLEDisconnected, BlePeripheralManager::onBleDisconnected);
  BLE.advertise();
  Serial.print(F("# Slave advertising as "));
  Serial.print(deviceName);
  Serial.print(F(" service "));
  Serial.println(KneeBle::kTelemetryServiceUuid);
  return true;
}

void BlePeripheralManager::poll() {
  BLE.poll();
}

bool BlePeripheralManager::publish(const KneeBle::OrientationPacketV1& packet) {
  return orientationCharacteristic_.writeValue(reinterpret_cast<const uint8_t*>(&packet),
                                               sizeof(packet));
}

bool BlePeripheralManager::isConnected() const {
  return connected_;
}

void BlePeripheralManager::onBleConnected(BLEDevice) {
  if (instance_ != nullptr) {
    instance_->connected_ = true;
  }
  Serial.println(F("# Slave connected to central."));
}

void BlePeripheralManager::onBleDisconnected(BLEDevice) {
  if (instance_ != nullptr) {
    instance_->connected_ = false;
    BLE.advertise();
  }
  Serial.println(F("# Slave disconnected, advertising resumed."));
}
