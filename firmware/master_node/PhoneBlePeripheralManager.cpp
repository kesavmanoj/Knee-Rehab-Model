#include "PhoneBlePeripheralManager.h"

#include "AppConfig.h"

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
      hasPendingCommand_(false) {}

bool PhoneBlePeripheralManager::begin() {
  BLE.setDeviceName(MasterConfig::kPhoneBleDeviceName);
  BLE.setLocalName(MasterConfig::kPhoneBleDeviceName);
  BLE.setAdvertisedService(service_);

  service_.addCharacteristic(telemetryCharacteristic_);
  service_.addCharacteristic(commandCharacteristic_);
  service_.addCharacteristic(statusCharacteristic_);

  BLE.addService(service_);

  KneePhoneBle::TelemetryPacketV1 telemetry{};
  telemetry.version = KneePhoneBle::kTelemetryVersion;
  telemetryCharacteristic_.writeValue(reinterpret_cast<const uint8_t*>(&telemetry), sizeof(telemetry));

  KneePhoneBle::StatusPacketV1 status{};
  status.version = KneePhoneBle::kStatusVersion;
  statusCharacteristic_.writeValue(reinterpret_cast<const uint8_t*>(&status), sizeof(status));

  BLE.advertise();
  return true;
}

void PhoneBlePeripheralManager::poll() {
  if (commandCharacteristic_.written()) {
    KneePhoneBle::CommandPacketV1 command{};
    const int bytesRead =
        commandCharacteristic_.readValue(reinterpret_cast<uint8_t*>(&command), sizeof(command));
    if (bytesRead == static_cast<int>(sizeof(command)) &&
        command.version == KneePhoneBle::kCommandVersion) {
      pendingCommand_ = command;
      hasPendingCommand_ = true;
    }
  }
}

bool PhoneBlePeripheralManager::updateTelemetry(const KneePhoneBle::TelemetryPacketV1& telemetry,
                                                const KneePhoneBle::StatusPacketV1& status) {
  const bool telemetryOk =
      telemetryCharacteristic_.writeValue(reinterpret_cast<const uint8_t*>(&telemetry),
                                          sizeof(telemetry)) ==
      static_cast<int>(sizeof(telemetry));
  const bool statusOk =
      statusCharacteristic_.writeValue(reinterpret_cast<const uint8_t*>(&status), sizeof(status)) ==
      static_cast<int>(sizeof(status));
  return telemetryOk && statusOk;
}

bool PhoneBlePeripheralManager::hasPendingCommand() const {
  return hasPendingCommand_;
}

KneePhoneBle::CommandPacketV1 PhoneBlePeripheralManager::consumePendingCommand() {
  hasPendingCommand_ = false;
  return pendingCommand_;
}
