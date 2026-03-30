#pragma once

#include <ArduinoBLE.h>

#include "BleProtocol.h"

class BlePeripheralManager {
 public:
  BlePeripheralManager();

  bool begin(const char* deviceName);
  void poll();
  bool publish(const KneeBle::OrientationPacketV1& packet);
  bool isConnected() const;

 private:
  static void onBleConnected(BLEDevice central);
  static void onBleDisconnected(BLEDevice central);

  static BlePeripheralManager* instance_;

  BLEService telemetryService_;
  BLECharacteristic orientationCharacteristic_;
  bool connected_;
};
