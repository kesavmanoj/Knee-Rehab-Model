#pragma once

#include <Arduino.h>

namespace KneeBle {

// Custom UUIDs for the shin node telemetry service.
// Keep these stable once the master firmware is built against them.
static constexpr char kTelemetryServiceUuid[] = "19B10010-E8F2-537E-4F6C-D104768A1214";
static constexpr char kOrientationCharacteristicUuid[] = "19B10011-E8F2-537E-4F6C-D104768A1214";

static constexpr uint8_t kProtocolVersion = 1;

enum PacketFlags : uint8_t {
  kFlagNone = 0,
  kFlagZeroed = 1 << 0,
  kFlagImuHealthy = 1 << 1,
};

#pragma pack(push, 1)
struct OrientationPacketV1 {
  uint8_t version;
  uint8_t flags;
  uint16_t sequence;
  uint32_t uptimeMs;
  float segmentAngleDeg;
  float pitchDeg;
  float rollDeg;
  float accelPitchDeg;
};
#pragma pack(pop)

static_assert(sizeof(OrientationPacketV1) == 24, "Unexpected BLE packet size");

}  // namespace KneeBle
