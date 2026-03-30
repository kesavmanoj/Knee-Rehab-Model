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
    return false;
  }

  startScan();
  return true;
}

void BleCentralManager::poll() {
  BLE.poll();

  if (state_ == State::Connected) {
    if (!peripheral_.connected()) {
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
}

void BleCentralManager::deferScan() {
  BLE.stopScan();
  state_ = State::Idle;
  nextScanAtMs_ = millis() + MasterConfig::kBleRetryIntervalMs;
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

  if (!peripheral.connect()) {
    deferScan();
    return false;
  }

  if (!peripheral.discoverAttributes()) {
    peripheral.disconnect();
    deferScan();
    return false;
  }

  BLECharacteristic orientationCharacteristic =
      peripheral.characteristic(KneeBle::kOrientationCharacteristicUuid);
  if (!orientationCharacteristic) {
    peripheral.disconnect();
    deferScan();
    return false;
  }

  if (!orientationCharacteristic.canSubscribe() || !orientationCharacteristic.subscribe()) {
    peripheral.disconnect();
    deferScan();
    return false;
  }

  peripheral_ = peripheral;
  orientationCharacteristic_ = orientationCharacteristic;
  state_ = State::Connected;
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
