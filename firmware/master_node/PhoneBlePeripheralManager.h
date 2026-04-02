#pragma once

#include <ArduinoBLE.h>

#include "PhoneBleProtocol.h"

class PhoneBlePeripheralManager {
 public:
  PhoneBlePeripheralManager();

  bool begin();
  void poll();
  bool updateTelemetry(const KneePhoneBle::TelemetryPacketV1& telemetry,
                       const KneePhoneBle::StatusPacketV1& status);

  bool hasPendingCommand() const;
  KneePhoneBle::CommandPacketV1 consumePendingCommand();

 private:
  BLEService service_;
  BLECharacteristic telemetryCharacteristic_;
  BLECharacteristic commandCharacteristic_;
  BLECharacteristic statusCharacteristic_;

  KneePhoneBle::CommandPacketV1 pendingCommand_;
  bool hasPendingCommand_;
};
