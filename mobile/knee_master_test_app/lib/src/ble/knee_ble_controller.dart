import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'ble_permissions.dart';
import 'knee_ble_contract.dart';
import 'knee_command.dart';
import 'knee_telemetry.dart';

class AngleHistorySample {
  const AngleHistorySample({
    required this.receivedAt,
    required this.uptimeMs,
    required this.angleDeg,
  });

  final DateTime receivedAt;
  final int uptimeMs;
  final double angleDeg;
}

class KneeBleController extends ChangeNotifier {
  static const Duration _telemetryPollInterval = Duration(milliseconds: 75);
  static const Duration _commandQuietWindow = Duration(milliseconds: 150);

  KneeBleController({
    FlutterReactiveBle? ble,
    BlePermissions? permissions,
  })  : _ble = ble ?? FlutterReactiveBle(),
        _permissions = permissions ?? BlePermissions() {
    _bleStatusSubscription = _ble.statusStream.listen((status) {
      bleStatus = status;
      notifyListeners();
    });
  }

  final FlutterReactiveBle _ble;
  final BlePermissions _permissions;

  StreamSubscription<BleStatus>? _bleStatusSubscription;
  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  Timer? _telemetryPollTimer;

  final List<DiscoveredDevice> _devices = <DiscoveredDevice>[];
  final List<AngleHistorySample> _recentAngles = <AngleHistorySample>[];
  BleStatus bleStatus = BleStatus.unknown;
  bool permissionsGranted = false;
  bool isScanning = false;
  bool isConnecting = false;
  DeviceConnectionState connectionState = DeviceConnectionState.disconnected;
  String? connectedDeviceId;
  String? connectedDeviceName;
  KneeTelemetryPacket? telemetry;
  KneeStatusPacket? status;
  DateTime? lastTelemetryAt;
  int? lastTelemetryPayloadLength;
  int? negotiatedMtu;
  String? lastError;

  List<DiscoveredDevice> get devices => List.unmodifiable(_devices);
  List<AngleHistorySample> get recentAngles => List.unmodifiable(_recentAngles);

  bool get isConnected => connectionState == DeviceConnectionState.connected;
  bool get canSendCommands => isConnected;
  double? get currentAngleDeg => telemetry?.finalAngleDeg;
  bool get isSensorStale => isConnected && !hasFreshTelemetry;
  bool get hasFreshTelemetry {
    final stamp = lastTelemetryAt;
    if (stamp == null) {
      return false;
    }
    return DateTime.now().difference(stamp) < const Duration(seconds: 1);
  }
  String get connectionSummary {
    if (isConnecting) {
      return 'Connecting';
    }
    if (isConnected && hasFreshTelemetry) {
      return 'Connected';
    }
    if (isSensorStale) {
      return 'Sensor stale';
    }
    if (isScanning) {
      return 'Searching';
    }
    return 'Disconnected';
  }

  Future<void> requestPermissions() async {
    final result = await _permissions.requestForBle();
    permissionsGranted = result.granted;
    if (!result.granted) {
      lastError =
          'Bluetooth permissions are required. Missing: ${result.missingPermissions.join(', ')}';
    } else if (lastError?.startsWith('Bluetooth permissions are required') ??
        false) {
      lastError = null;
    }
    notifyListeners();
  }

  Future<void> startScan() async {
    await requestPermissions();
    if (!permissionsGranted) {
      return;
    }

    await stopScan();
    _devices.clear();
    isScanning = true;
    lastError = null;
    notifyListeners();

    _scanSubscription = _ble
        .scanForDevices(
          withServices: <Uuid>[KneeBleContract.serviceId],
          scanMode: ScanMode.lowLatency,
        )
        .listen(
          _upsertDevice,
          onError: (Object error) {
            isScanning = false;
            lastError = 'Scan failed: $error';
            notifyListeners();
          },
        );
  }

  Future<void> stopScan() async {
    isScanning = false;
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    notifyListeners();
  }

  Future<void> connectToDevice(DiscoveredDevice device) async {
    await stopScan();
    await disconnect();

    connectedDeviceId = device.id;
    connectedDeviceName = device.name.isNotEmpty ? device.name : device.id;
    isConnecting = true;
    connectionState = DeviceConnectionState.connecting;
    lastError = null;
    notifyListeners();

    _connectionSubscription = _ble
        .connectToAdvertisingDevice(
          id: device.id,
          withServices: <Uuid>[KneeBleContract.serviceId],
          prescanDuration: const Duration(seconds: 2),
          servicesWithCharacteristicsToDiscover: <Uuid, List<Uuid>>{
            KneeBleContract.serviceId: <Uuid>[
              KneeBleContract.telemetryCharacteristicId,
              KneeBleContract.commandCharacteristicId,
              KneeBleContract.statusCharacteristicId,
            ],
          },
          connectionTimeout: const Duration(seconds: 10),
        )
        .listen(
          (ConnectionStateUpdate update) {
            connectionState = update.connectionState;
            connectedDeviceId = update.deviceId;
            isConnecting =
                update.connectionState == DeviceConnectionState.connecting;

            if (update.connectionState == DeviceConnectionState.connected) {
              _subscribeToCharacteristics(update.deviceId);
            }

            if (update.connectionState == DeviceConnectionState.disconnected) {
              _clearCharacteristicSubscriptions();
            }

            notifyListeners();
          },
          onError: (Object error) {
            lastError = 'Connection failed: $error';
            isConnecting = false;
            connectionState = DeviceConnectionState.disconnected;
            _clearCharacteristicSubscriptions();
            notifyListeners();
          },
        );
  }

  Future<void> disconnect() async {
    await _clearCharacteristicSubscriptions();
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    isConnecting = false;
    connectionState = DeviceConnectionState.disconnected;
    connectedDeviceId = null;
    connectedDeviceName = null;
    telemetry = null;
    status = null;
    lastTelemetryAt = null;
    lastTelemetryPayloadLength = null;
    _recentAngles.clear();
    notifyListeners();
  }

  Future<void> sendZeroImu() async {
    await _sendCommand(const KneeCommandPacket(commandId: KneeCommandId.zeroImu));
  }

  Future<void> sendClearZero() async {
    await _sendCommand(
      const KneeCommandPacket(commandId: KneeCommandId.clearZero),
    );
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    _telemetryPollTimer?.cancel();
    _bleStatusSubscription?.cancel();
    super.dispose();
  }

  void _upsertDevice(DiscoveredDevice device) {
    if (device.name.isEmpty &&
        !device.serviceUuids.contains(KneeBleContract.serviceId)) {
      return;
    }

    final existingIndex = _devices.indexWhere((item) => item.id == device.id);
    if (existingIndex >= 0) {
      _devices[existingIndex] = device;
    } else {
      _devices.add(device);
    }

    _devices.sort((a, b) {
      final aName = a.name.isNotEmpty ? a.name : a.id;
      final bName = b.name.isNotEmpty ? b.name : b.id;
      return aName.compareTo(bName);
    });

    notifyListeners();
  }

  Future<void> _subscribeToCharacteristics(String deviceId) async {
    await _clearCharacteristicSubscriptions();

    try {
      negotiatedMtu = await _ble.requestMtu(deviceId: deviceId, mtu: 128);
    } catch (error) {
      lastError = 'MTU request failed: $error';
    }

    await _readTelemetryOnce(deviceId);
    _telemetryPollTimer = Timer.periodic(_telemetryPollInterval, (
      _,
    ) async {
      if (!isConnected || connectedDeviceId != deviceId) {
        return;
      }
      await _readTelemetryOnce(deviceId);
    });

    try {
      final payload = await _ble.readCharacteristic(_statusCharacteristic(deviceId));
      status = KneeStatusPacket.fromBytes(payload);
    } catch (error) {
      lastError = 'Status read failed: $error';
    }

    notifyListeners();
  }

  Future<void> _sendCommand(KneeCommandPacket packet) async {
    final deviceId = connectedDeviceId;
    if (deviceId == null) {
      lastError = 'Not connected to a KneeMaster device.';
      notifyListeners();
      return;
    }

    final pollWasRunning = _telemetryPollTimer != null;
    if (pollWasRunning) {
      await _clearCharacteristicSubscriptions();
    }

    try {
      await _ble.writeCharacteristicWithResponse(
        _commandCharacteristic(deviceId),
        value: packet.toBytes(),
      );
      await Future<void>.delayed(_commandQuietWindow);
      if (isConnected && connectedDeviceId == deviceId) {
        await _readTelemetryOnce(deviceId);
      }
      lastError = null;
    } catch (error) {
      lastError = 'Command write failed: $error';
    } finally {
      if (pollWasRunning && isConnected && connectedDeviceId == deviceId) {
        _telemetryPollTimer = Timer.periodic(_telemetryPollInterval, (_) async {
          if (!isConnected || connectedDeviceId != deviceId) {
            return;
          }
          await _readTelemetryOnce(deviceId);
        });
      }
    }

    notifyListeners();
  }

  Future<void> _clearCharacteristicSubscriptions() async {
    _telemetryPollTimer?.cancel();
    _telemetryPollTimer = null;
  }

  Future<void> _readTelemetryOnce(String deviceId) async {
    try {
      final telemetryPayload = await _ble.readCharacteristic(
        _telemetryCharacteristic(deviceId),
      );
      lastTelemetryPayloadLength = telemetryPayload.length;
      telemetry = KneeTelemetryPacket.fromBytes(telemetryPayload);
      lastTelemetryAt = DateTime.now();
      _recentAngles.add(
        AngleHistorySample(
          receivedAt: lastTelemetryAt!,
          uptimeMs: telemetry!.uptimeMs,
          angleDeg: telemetry!.finalAngleDeg,
        ),
      );
      const int maxSamples = 300;
      if (_recentAngles.length > maxSamples) {
        _recentAngles.removeRange(0, _recentAngles.length - maxSamples);
      }
      lastError = null;
      notifyListeners();
    } catch (error) {
      lastError = 'Telemetry read failed: $error';
      notifyListeners();
    }
  }

  QualifiedCharacteristic _telemetryCharacteristic(String deviceId) {
    return QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: KneeBleContract.serviceId,
      characteristicId: KneeBleContract.telemetryCharacteristicId,
    );
  }

  QualifiedCharacteristic _statusCharacteristic(String deviceId) {
    return QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: KneeBleContract.serviceId,
      characteristicId: KneeBleContract.statusCharacteristicId,
    );
  }

  QualifiedCharacteristic _commandCharacteristic(String deviceId) {
    return QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: KneeBleContract.serviceId,
      characteristicId: KneeBleContract.commandCharacteristicId,
    );
  }
}
