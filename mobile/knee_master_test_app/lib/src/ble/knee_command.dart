import 'dart:typed_data';

enum KneeCommandId {
  noOp(0),
  zeroImu(1),
  clearZero(2);

  const KneeCommandId(this.value);

  final int value;
}

class KneeCommandPacket {
  const KneeCommandPacket({
    required this.commandId,
    this.value = 0.0,
    this.version = 1,
  });

  final int version;
  final KneeCommandId commandId;
  final double value;

  Uint8List toBytes() {
    final byteData = ByteData(6);
    byteData.setUint8(0, version);
    byteData.setUint8(1, commandId.value);
    byteData.setFloat32(2, value, Endian.little);
    return byteData.buffer.asUint8List();
  }
}
