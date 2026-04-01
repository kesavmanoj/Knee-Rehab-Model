import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

abstract final class KneeBleContract {
  static const String deviceName = 'KneeMaster';

  static const String serviceName = 'Knee Rehab Phone Service';
  static const String telemetryName = 'Telemetry';
  static const String commandName = 'Command';
  static const String statusName = 'Status';

  static const String serviceUuid = '19B10020-E8F2-537E-4F6C-D104768A1214';
  static const String telemetryCharacteristicUuid =
      '19B10021-E8F2-537E-4F6C-D104768A1214';
  static const String commandCharacteristicUuid =
      '19B10022-E8F2-537E-4F6C-D104768A1214';
  static const String statusCharacteristicUuid =
      '19B10023-E8F2-537E-4F6C-D104768A1214';

  static final Uuid serviceId = Uuid.parse(serviceUuid);
  static final Uuid telemetryCharacteristicId =
      Uuid.parse(telemetryCharacteristicUuid);
  static final Uuid commandCharacteristicId =
      Uuid.parse(commandCharacteristicUuid);
  static final Uuid statusCharacteristicId = Uuid.parse(statusCharacteristicUuid);
}
