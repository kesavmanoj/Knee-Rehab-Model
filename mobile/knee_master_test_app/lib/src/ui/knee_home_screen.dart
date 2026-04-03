import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../ble/knee_ble_contract.dart';
import '../ble/knee_ble_controller.dart';
import '../ble/knee_telemetry.dart';

class KneeHomeScreen extends StatefulWidget {
  const KneeHomeScreen({super.key});

  @override
  State<KneeHomeScreen> createState() => _KneeHomeScreenState();
}

class _KneeHomeScreenState extends State<KneeHomeScreen> {
  late final KneeBleController _controller;

  @override
  void initState() {
    super.initState();
    _controller = KneeBleController();
    _controller.requestPermissions();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final telemetry = _controller.telemetry;
        final status = _controller.status;

        return Scaffold(
          appBar: AppBar(
            title: const Text('KneeMaster BLE Test'),
            actions: <Widget>[
              IconButton(
                tooltip: _controller.isScanning ? 'Stop scan' : 'Start scan',
                onPressed: _controller.isScanning
                    ? _controller.stopScan
                    : _controller.startScan,
                icon: Icon(
                  _controller.isScanning
                      ? Icons.stop_circle
                      : Icons.bluetooth_searching,
                ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              _buildConnectionCard(context),
              const SizedBox(height: 12),
              if (_controller.lastError != null) _buildErrorCard(_controller.lastError!),
              if (_controller.lastError != null) const SizedBox(height: 12),
              _buildTelemetrySection(telemetry, status),
              const SizedBox(height: 12),
              _buildCommandSection(),
              const SizedBox(height: 12),
              _buildScanSection(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildConnectionCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Connection',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _StatusChip(
                  label: 'BLE',
                  value: _bleStatusLabel(_controller.bleStatus),
                ),
                _StatusChip(
                  label: 'Permissions',
                  value: _controller.permissionsGranted ? 'Granted' : 'Needed',
                ),
                _StatusChip(
                  label: 'Device',
                  value: _controller.connectedDeviceName ?? 'None',
                ),
                _StatusChip(
                  label: 'State',
                  value: _controller.connectionState.name,
                ),
                _StatusChip(
                  label: 'MTU',
                  value: _controller.negotiatedMtu?.toString() ?? 'n/a',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                FilledButton.icon(
                  onPressed: _controller.startScan,
                  icon: const Icon(Icons.search),
                  label: const Text('Scan'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _controller.isConnected || _controller.isConnecting
                      ? _controller.disconnect
                      : null,
                  icon: const Icon(Icons.link_off),
                  label: const Text('Disconnect'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(String error) {
    return Card(
      color: const Color(0xFFFFF0F0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.error_outline, color: Color(0xFFAA1D1D)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                error,
                style: const TextStyle(color: Color(0xFF7A1111)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTelemetrySection(
    KneeTelemetryPacket? telemetry,
    KneeStatusPacket? status,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
              const Text('Live Telemetry'),
            const SizedBox(height: 12),
            if (telemetry == null)
              const Text('No telemetry received yet. Connect to KneeMaster and wait for the next telemetry poll.')
            else
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  _ValueTile(label: 'Final Angle', value: _formatAngle(telemetry.finalAngleDeg)),
                  _ValueTile(label: 'Sequence', value: telemetry.sequence.toString()),
                  _ValueTile(
                    label: 'Payload Bytes',
                    value:
                        _controller.lastTelemetryPayloadLength?.toString() ?? 'n/a',
                  ),
                  _ValueTile(
                    label: 'Flags',
                    value: _flagsLabel(telemetry.flags),
                    wide: true,
                  ),
                  _ValueTile(
                    label: 'Last Packet',
                    value: _controller.lastTelemetryAt?.toLocal().toString() ?? 'n/a',
                    wide: true,
                  ),
                  if (status != null)
                    _ValueTile(
                      label: 'Status Snapshot',
                      value:
                          'seq ${status.lastSequence}, uptime ${status.uptimeMs} ms',
                      wide: true,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommandSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Commands'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: _controller.canSendCommands
                      ? _controller.sendZeroImu
                      : null,
                  icon: const Icon(Icons.exposure_zero),
                  label: const Text('Zero IMU'),
                ),
                OutlinedButton.icon(
                  onPressed: _controller.canSendCommands
                      ? _controller.sendClearZero
                      : null,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Clear Zero'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanSection() {
    final devices = _controller.devices;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Discovered Devices'),
            const SizedBox(height: 12),
            if (devices.isEmpty)
              Text(
                _controller.isScanning
                    ? 'Scanning for ${KneeBleContract.deviceName}...'
                    : 'Tap Scan to search for KneeMaster.',
              )
            else
              Column(
                children: devices
                    .map(
                      (device) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          device.name.isNotEmpty
                              ? device.name
                              : KneeBleContract.deviceName,
                        ),
                        subtitle: Text('${device.id}\nRSSI ${device.rssi} dBm'),
                        trailing: FilledButton(
                          onPressed: () => _controller.connectToDevice(device),
                          child: const Text('Connect'),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
          ],
        ),
      ),
    );
  }

  String _formatAngle(double angle) => '${angle.toStringAsFixed(2)} deg';

  String _bleStatusLabel(BleStatus status) {
    switch (status) {
      case BleStatus.ready:
        return 'Ready';
      case BleStatus.poweredOff:
        return 'Powered Off';
      case BleStatus.unauthorized:
        return 'Unauthorized';
      case BleStatus.unsupported:
        return 'Unsupported';
      case BleStatus.locationServicesDisabled:
        return 'Location Off';
      default:
        return status.name;
    }
  }

  String _flagsLabel(KneeTelemetryFlags flags) {
    final labels = <String>[];
    if (flags.slaveConnected) labels.add('Slave');
    if (flags.imuZeroed) labels.add('Zeroed');
    if (flags.imuValid) labels.add('IMU');
    if (labels.isEmpty) {
      return 'None';
    }
    return labels.join(' | ');
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: $value'),
    );
  }
}

class _ValueTile extends StatelessWidget {
  const _ValueTile({
    required this.label,
    required this.value,
    this.wide = false,
  });

  final String label;
  final String value;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: wide ? 320 : 150,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
