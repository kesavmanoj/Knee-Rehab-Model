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
 bool isPhoneConnected() const;

 private:
  static void onCommandCharacteristicWritten(BLEDevice central, BLECharacteristic characteristic);
  void handleCommandCharacteristicWritten();

  BLEService service_;
  BLECharacteristic telemetryCharacteristic_;
  BLECharacteristic commandCharacteristic_;
  BLECharacteristic statusCharacteristic_;

  KneePhoneBle::CommandPacketV1 pendingCommand_;
  KneePhoneBle::StatusPacketV1 lastStatusPacket_;
  bool hasPendingCommand_;
  bool phoneConnected_;
  uint32_t lastStatusWriteMs_;

  static PhoneBlePeripheralManager* instance_;
};
