import 'dart:typed_data';

class KneeTelemetryFlags {
  const KneeTelemetryFlags(this.rawValue);

  final int rawValue;

  bool get slaveConnected => (rawValue & (1 << 0)) != 0;
  bool get imuZeroed => (rawValue & (1 << 1)) != 0;
  bool get imuValid => (rawValue & (1 << 2)) != 0;
}

class KneeTelemetryPacket {
  const KneeTelemetryPacket({
    required this.version,
    required this.flags,
    required this.sequence,
    required this.uptimeMs,
    required this.finalAngleDeg,
  });

  final int version;
  final KneeTelemetryFlags flags;
  final int sequence;
  final int uptimeMs;
  final double finalAngleDeg;

  factory KneeTelemetryPacket.fromBytes(List<int> bytes) {
    if (bytes.length < 12) {
      throw FormatException(
        'Telemetry payload must be 12 bytes, received ${bytes.length}.',
      );
    }

    final view = ByteData.sublistView(Uint8List.fromList(bytes));
    return KneeTelemetryPacket(
      version: view.getUint8(0),
      flags: KneeTelemetryFlags(view.getUint8(1)),
      sequence: view.getUint16(2, Endian.little),
      uptimeMs: view.getUint32(4, Endian.little),
      finalAngleDeg: view.getFloat32(8, Endian.little),
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
