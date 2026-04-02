#include <Arduino.h>

#include "BleCentralManager.h"

#include "AppConfig.h"

BleCentralManager::BleCentralManager()
    : latestPacket_{},
      state_(State::Idle),
      nextScanAtMs_(0),
      lastPacketMs_(0),
      hasPacket_(false),
      newPacketAvailable_(false) {}

bool BleCentralManager::begin() {
  if (!BLE.begin()) {
    Serial.println(F("# BLE central init failed."));
    return false;
  }

  Serial.println(F("# BLE central ready."));
  state_ = State::Idle;
  nextScanAtMs_ = 0;
  return true;
}

void BleCentralManager::poll() {
  BLE.poll();

  if (state_ == State::Connected) {
    if (!peripheral_.connected()) {
      Serial.println(F("# Slave link lost."));
      resetConnection();
      deferScan();
      return;
    }

    if (orientationCharacteristic_ && orientationCharacteristic_.valueUpdated()) {
      readIncomingPacket();
    }
    return;
  }

  if (state_ == State::Idle && millis() >= nextScanAtMs_) {
    startScan();
  }

  if (state_ == State::Scanning) {
    BLEDevice discoveredPeripheral = BLE.available();
    if (discoveredPeripheral) {
      Serial.print(F("# Found slave candidate: "));
      if (discoveredPeripheral.hasLocalName()) {
        Serial.print(discoveredPeripheral.localName());
      } else {
        Serial.print(F("<no-name>"));
      }
      Serial.print(F(" @ "));
      Serial.print(discoveredPeripheral.address());
      Serial.print(F(" RSSI "));
      Serial.println(discoveredPeripheral.rssi());
      connectToPeripheral(discoveredPeripheral);
    }
  }
}

bool BleCentralManager::hasPacket() const {
  return hasPacket_;
}

bool BleCentralManager::hasFreshPacket() const {
  return hasPacket_ && ((millis() - lastPacketMs_) <= MasterConfig::kBlePacketTimeoutMs);
}

bool BleCentralManager::consumeNewPacketFlag() {
  const bool hadNewPacket = newPacketAvailable_;
  newPacketAvailable_ = false;
  return hadNewPacket;
}

uint32_t BleCentralManager::packetAgeMs() const {
  if (!hasPacket_) {
    return 0UL;
  }
  return millis() - lastPacketMs_;
}

const KneeBle::OrientationPacketV1& BleCentralManager::latestPacket() const {
  return latestPacket_;
}

BleCentralManager::State BleCentralManager::state() const {
  return state_;
}

const char* BleCentralManager::stateText() const {
  switch (state_) {
    case State::Idle:
      return "IDLE";
    case State::Scanning:
      return "SCAN";
    case State::Connecting:
      return "CONN";
    case State::Connected:
      return hasFreshPacket() ? "LIVE" : "STAL";
    default:
      return "UNKN";
  }
}

void BleCentralManager::startScan() {
  BLE.stopScan();
  BLE.scanForUuid(KneeBle::kTelemetryServiceUuid);
  state_ = State::Scanning;
  Serial.print(F("# Scanning for slave service "));
  Serial.println(KneeBle::kTelemetryServiceUuid);
}

void BleCentralManager::deferScan() {
  BLE.stopScan();
  state_ = State::Idle;
  nextScanAtMs_ = millis() + MasterConfig::kBleRetryIntervalMs;
  Serial.print(F("# Slave scan deferred for "));
  Serial.print(MasterConfig::kBleRetryIntervalMs);
  Serial.println(F(" ms"));
}

void BleCentralManager::resetConnection() {
  if (peripheral_ && peripheral_.connected()) {
    peripheral_.disconnect();
  }

  orientationCharacteristic_ = BLECharacteristic();
  peripheral_ = BLEDevice();
  state_ = State::Idle;
}

bool BleCentralManager::connectToPeripheral(BLEDevice peripheral) {
  BLE.stopScan();
  state_ = State::Connecting;
  Serial.print(F("# Connecting to slave: "));
  if (peripheral.hasLocalName()) {
    Serial.print(peripheral.localName());
  } else {
    Serial.print(F("<no-name>"));
  }
  Serial.print(F(" @ "));
  Serial.println(peripheral.address());

  if (!peripheral.connect()) {
    Serial.println(F("# Slave connect failed."));
    deferScan();
    return false;
  }

  if (!peripheral.discoverAttributes()) {
    Serial.println(F("# Slave attribute discovery failed."));
    peripheral.disconnect();
    deferScan();
    return false;
  }

  BLECharacteristic orientationCharacteristic =
      peripheral.characteristic(KneeBle::kOrientationCharacteristicUuid);
  if (!orientationCharacteristic) {
    Serial.println(F("# Slave orientation characteristic missing."));
    peripheral.disconnect();
    deferScan();
    return false;
  }

  if (!orientationCharacteristic.canSubscribe() || !orientationCharacteristic.subscribe()) {
    Serial.println(F("# Slave orientation subscribe failed."));
    peripheral.disconnect();
    deferScan();
    return false;
  }

  peripheral_ = peripheral;
  orientationCharacteristic_ = orientationCharacteristic;
  state_ = State::Connected;
  Serial.println(F("# Slave connected and subscribed."));
  readIncomingPacket();
  return true;
}

void BleCentralManager::readIncomingPacket() {
  if (!orientationCharacteristic_) {
    return;
  }

  KneeBle::OrientationPacketV1 packet{};
  const int bytesRead =
      orientationCharacteristic_.readValue(reinterpret_cast<uint8_t*>(&packet), sizeof(packet));
  if (bytesRead != static_cast<int>(sizeof(packet))) {
    return;
  }

  if (packet.version != KneeBle::kProtocolVersion) {
    return;
  }

  latestPacket_ = packet;
  hasPacket_ = true;
  lastPacketMs_ = millis();
  newPacketAvailable_ = true;
}
