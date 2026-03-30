#pragma once

#include <ArduinoBLE.h>

#include "BleProtocol.h"

class BleCentralManager {
 public:
  enum class State : uint8_t {
    Idle,
    Scanning,
    Connecting,
    Connected,
  };

  BleCentralManager();

  bool begin();
  void poll();

  bool hasPacket() const;
  bool hasFreshPacket() const;
  bool consumeNewPacketFlag();
  uint32_t packetAgeMs() const;
  const KneeBle::OrientationPacketV1& latestPacket() const;
  State state() const;
  const char* stateText() const;

 private:
  void startScan();
  void deferScan();
  void resetConnection();
  bool connectToPeripheral(BLEDevice peripheral);
  void readIncomingPacket();

  BLEDevice peripheral_;
  BLECharacteristic orientationCharacteristic_;
  KneeBle::OrientationPacketV1 latestPacket_;
  State state_;
  uint32_t nextScanAtMs_;
  uint32_t lastPacketMs_;
  bool hasPacket_;
  bool newPacketAvailable_;
};
