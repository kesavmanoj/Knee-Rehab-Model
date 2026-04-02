#pragma once

#include <Arduino.h>

namespace KneePhoneBle {

static constexpr char kPhoneServiceUuid[] = "19B10020-E8F2-537E-4F6C-D104768A1214";
static constexpr char kTelemetryCharacteristicUuid[] = "19B10021-E8F2-537E-4F6C-D104768A1214";
static constexpr char kCommandCharacteristicUuid[] = "19B10022-E8F2-537E-4F6C-D104768A1214";
static constexpr char kStatusCharacteristicUuid[] = "19B10023-E8F2-537E-4F6C-D104768A1214";

static constexpr uint8_t kTelemetryVersion = 1;
static constexpr uint8_t kCommandVersion = 1;
static constexpr uint8_t kStatusVersion = 1;

enum TelemetryFlags : uint8_t {
  kFlagNone = 0,
  kFlagSlaveConnected = 1 << 0,
  kFlagImuZeroed = 1 << 1,
  kFlagImuValid = 1 << 2,
  kFlagFlexValid = 1 << 3,
  kFlagPotValid = 1 << 4,
};

enum CommandId : uint8_t {
  kCmdNoOp = 0,
  kCmdZeroImu = 1,
  kCmdClearZero = 2,
};

#pragma pack(push, 1)

struct TelemetryPacketV1 {
  uint8_t version;
  uint8_t flags;
  uint16_t sequence;
  uint32_t uptimeMs;

  float masterImuDeg;
  float slaveImuDeg;
  float imuKneeDeg;

  uint16_t flexRawAdc;
  float flexAngleDeg;

  uint16_t potRawAdc;
  float potAngleDeg;
};

struct CommandPacketV1 {
  uint8_t version;
  uint8_t commandId;
  float value;
};

struct StatusPacketV1 {
  uint8_t version;
  uint8_t flags;
  uint16_t lastSequence;
  uint32_t uptimeMs;
};

#pragma pack(pop)

static_assert(sizeof(TelemetryPacketV1) == 32, "Unexpected TelemetryPacketV1 size");
static_assert(sizeof(CommandPacketV1) == 6, "Unexpected CommandPacketV1 size");
static_assert(sizeof(StatusPacketV1) == 8, "Unexpected StatusPacketV1 size");

}  // namespace KneePhoneBle
