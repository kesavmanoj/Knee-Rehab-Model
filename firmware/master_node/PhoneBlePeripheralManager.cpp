#include "PhoneBlePeripheralManager.h"

#include "AppConfig.h"
#include <string.h>

PhoneBlePeripheralManager* PhoneBlePeripheralManager::instance_ = nullptr;

PhoneBlePeripheralManager::PhoneBlePeripheralManager()
    : service_(KneePhoneBle::kPhoneServiceUuid),
      telemetryCharacteristic_(KneePhoneBle::kTelemetryCharacteristicUuid,
                               BLERead,
                               sizeof(KneePhoneBle::TelemetryPacketV1)),
      commandCharacteristic_(KneePhoneBle::kCommandCharacteristicUuid,
                             BLEWrite,
                             sizeof(KneePhoneBle::CommandPacketV1)),
      statusCharacteristic_(KneePhoneBle::kStatusCharacteristicUuid,
                            BLERead,
                            sizeof(KneePhoneBle::StatusPacketV1)),
      pendingCommand_{},
      lastStatusPacket_{},
      hasPendingCommand_(false),
      phoneConnected_(false),
      lastStatusWriteMs_(0) {}

bool PhoneBlePeripheralManager::begin() {
  instance_ = this;
  BLE.setDeviceName(MasterConfig::kPhoneBleDeviceName);
  BLE.setLocalName(MasterConfig::kPhoneBleDeviceName);
  BLE.setAdvertisedService(service_);

  service_.addCharacteristic(telemetryCharacteristic_);
  service_.addCharacteristic(commandCharacteristic_);
  service_.addCharacteristic(statusCharacteristic_);

  commandCharacteristic_.setEventHandler(BLEWritten, PhoneBlePeripheralManager::onCommandCharacteristicWritten);

  BLE.addService(service_);

  KneePhoneBle::TelemetryPacketV1 telemetry{};
  telemetry.version = KneePhoneBle::kTelemetryVersion;
  telemetryCharacteristic_.writeValue(reinterpret_cast<const uint8_t*>(&telemetry), sizeof(telemetry));

  KneePhoneBle::StatusPacketV1 status{};
  status.version = KneePhoneBle::kStatusVersion;
  statusCharacteristic_.writeValue(reinterpret_cast<const uint8_t*>(&status), sizeof(status));
  lastStatusPacket_ = status;
  lastStatusWriteMs_ = millis();

  BLE.advertise();
  return true;
}

void PhoneBlePeripheralManager::poll() {
  BLEDevice central = BLE.central();
  const bool connectedNow = central && central.connected();
  if (connectedNow && !phoneConnected_) {
    phoneConnected_ = true;
    Serial.print(F("# Phone connected: "));
    Serial.println(central.address());
  } else if (!connectedNow && phoneConnected_) {
    phoneConnected_ = false;
    hasPendingCommand_ = false;
    BLE.advertise();
    Serial.println(F("# Phone disconnected; advertising resumed."));
  }
}

bool PhoneBlePeripheralManager::updateTelemetry(const KneePhoneBle::TelemetryPacketV1& telemetry,
                                                const KneePhoneBle::StatusPacketV1& status) {
  const bool telemetryOk =
      telemetryCharacteristic_.writeValue(reinterpret_cast<const uint8_t*>(&telemetry),
                                          sizeof(telemetry)) ==
      static_cast<int>(sizeof(telemetry));

  bool statusOk = true;
  const bool statusChanged = memcmp(&status, &lastStatusPacket_, sizeof(status)) != 0;
  const uint32_t nowMs = millis();
  if (statusChanged || (nowMs - lastStatusWriteMs_) >= MasterConfig::kPhoneStatusIntervalMs) {
    statusOk =
        statusCharacteristic_.writeValue(reinterpret_cast<const uint8_t*>(&status), sizeof(status)) ==
        static_cast<int>(sizeof(status));
    if (statusOk) {
      lastStatusPacket_ = status;
      lastStatusWriteMs_ = nowMs;
    }
  }

  return telemetryOk && statusOk;
}

bool PhoneBlePeripheralManager::hasPendingCommand() const {
  return hasPendingCommand_;
}

KneePhoneBle::CommandPacketV1 PhoneBlePeripheralManager::consumePendingCommand() {
  hasPendingCommand_ = false;
  return pendingCommand_;
}

bool PhoneBlePeripheralManager::isPhoneConnected() const {
  return phoneConnected_;
}

void PhoneBlePeripheralManager::onCommandCharacteristicWritten(BLEDevice central, BLECharacteristic characteristic) {
  (void)central;
  (void)characteristic;
  if (instance_ != nullptr) {
    instance_->handleCommandCharacteristicWritten();
  }
}

void PhoneBlePeripheralManager::handleCommandCharacteristicWritten() {
  KneePhoneBle::CommandPacketV1 command{};
  const int bytesRead =
      commandCharacteristic_.readValue(reinterpret_cast<uint8_t*>(&command), sizeof(command));
  if (bytesRead == static_cast<int>(sizeof(command)) &&
      command.version == KneePhoneBle::kCommandVersion) {
    pendingCommand_ = command;
    hasPendingCommand_ = true;
  }
}
