import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'ble_permissions.dart';
import 'knee_ble_contract.dart';
import 'knee_command.dart';
import 'knee_telemetry.dart';

class KneeBleController extends ChangeNotifier {
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

  bool get isConnected => connectionState == DeviceConnectionState.connected;
  bool get canSendCommands => isConnected;

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
    _telemetryPollTimer = Timer.periodic(const Duration(milliseconds: 500), (
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

    try {
      await _ble.writeCharacteristicWithResponse(
        _commandCharacteristic(deviceId),
        value: packet.toBytes(),
      );
      lastError = null;
    } catch (error) {
      lastError = 'Command write failed: $error';
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
