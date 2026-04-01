import 'dart:typed_data';

class KneeTelemetryFlags {
  const KneeTelemetryFlags(this.rawValue);

  final int rawValue;

  bool get slaveConnected => (rawValue & (1 << 0)) != 0;
  bool get imuZeroed => (rawValue & (1 << 1)) != 0;
  bool get imuValid => (rawValue & (1 << 2)) != 0;
  bool get flexValid => (rawValue & (1 << 3)) != 0;
  bool get potValid => (rawValue & (1 << 4)) != 0;
}

class KneeTelemetryPacket {
  const KneeTelemetryPacket({
    required this.version,
    required this.flags,
    required this.sequence,
    required this.uptimeMs,
    required this.masterImuDeg,
    required this.slaveImuDeg,
    required this.imuKneeDeg,
    required this.flexRawAdc,
    required this.flexAngleDeg,
    required this.potRawAdc,
    required this.potAngleDeg,
  });

  final int version;
  final KneeTelemetryFlags flags;
  final int sequence;
  final int uptimeMs;
  final double masterImuDeg;
  final double slaveImuDeg;
  final double imuKneeDeg;
  final int flexRawAdc;
  final double flexAngleDeg;
  final int potRawAdc;
  final double potAngleDeg;

  factory KneeTelemetryPacket.fromBytes(List<int> bytes) {
    if (bytes.length < 32) {
      throw FormatException(
        'Telemetry payload must be 32 bytes, received ${bytes.length}.',
      );
    }

    final view = ByteData.sublistView(Uint8List.fromList(bytes));
    return KneeTelemetryPacket(
      version: view.getUint8(0),
      flags: KneeTelemetryFlags(view.getUint8(1)),
      sequence: view.getUint16(2, Endian.little),
      uptimeMs: view.getUint32(4, Endian.little),
      masterImuDeg: view.getFloat32(8, Endian.little),
      slaveImuDeg: view.getFloat32(12, Endian.little),
      imuKneeDeg: view.getFloat32(16, Endian.little),
      flexRawAdc: view.getUint16(20, Endian.little),
      flexAngleDeg: view.getFloat32(22, Endian.little),
      potRawAdc: view.getUint16(26, Endian.little),
      potAngleDeg: view.getFloat32(28, Endian.little),
    );
  }
}

class KneeStatusPacket {
  const KneeStatusPacket({
    required this.version,
    required this.flags,
    required this.lastSequence,
    required this.uptimeMs,
  });

  final int version;
  final KneeTelemetryFlags flags;
  final int lastSequence;
  final int uptimeMs;

  factory KneeStatusPacket.fromBytes(List<int> bytes) {
    if (bytes.length < 8) {
      throw FormatException(
        'Status payload must be 8 bytes, received ${bytes.length}.',
      );
    }

    final view = ByteData.sublistView(Uint8List.fromList(bytes));
    return KneeStatusPacket(
      version: view.getUint8(0),
      flags: KneeTelemetryFlags(view.getUint8(1)),
      lastSequence: view.getUint16(2, Endian.little),
      uptimeMs: view.getUint32(4, Endian.little),
    );
  }
}
