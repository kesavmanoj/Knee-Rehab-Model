import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../ble/knee_ble_contract.dart';
import '../ble/knee_ble_controller.dart';
import '../ble/knee_telemetry.dart';

class SessionSummary {
  const SessionSummary({
    required this.startedAt,
    required this.endedAt,
    required this.peakFlexionDeg,
    required this.extensionLagDeg,
    required this.repCount,
  });

  final DateTime startedAt;
  final DateTime endedAt;
  final double peakFlexionDeg;
  final double extensionLagDeg;
  final int repCount;

  Duration get duration => endedAt.difference(startedAt);
}

class KneeHomeScreen extends StatefulWidget {
  const KneeHomeScreen({super.key});

  @override
  State<KneeHomeScreen> createState() => _KneeHomeScreenState();
}

class _KneeHomeScreenState extends State<KneeHomeScreen> {
  static const double _targetRangeMinDeg = 10.0;
  static const double _targetRangeMaxDeg = 110.0;
  static const double _nearLimitBufferDeg = 10.0;

  late final KneeBleController _controller;

  int _selectedIndex = 0;
  bool _sessionActive = false;
  DateTime? _sessionStartedAt;
  double _sessionPeakFlexionDeg = 0.0;
  double _sessionMinAngleDeg = 145.0;
  int _sessionRepCount = 0;
  bool _repArmed = false;
  final List<SessionSummary> _completedSessions = <SessionSummary>[];

  @override
  void initState() {
    super.initState();
    _controller = KneeBleController();
    _controller.addListener(_handleControllerUpdate);
    _controller.requestPermissions();
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerUpdate);
    _controller.dispose();
    super.dispose();
  }

  void _handleControllerUpdate() {
    if (!_sessionActive || !_controller.hasFreshTelemetry) {
      return;
    }

    final angle = _controller.currentAngleDeg;
    if (angle == null) {
      return;
    }

    var changed = false;
    if (angle > _sessionPeakFlexionDeg) {
      _sessionPeakFlexionDeg = angle;
      changed = true;
    }
    if (angle < _sessionMinAngleDeg) {
      _sessionMinAngleDeg = angle;
      changed = true;
    }

    if (!_repArmed && angle >= 40.0) {
      _repArmed = true;
      changed = true;
    } else if (_repArmed && angle <= 20.0) {
      _repArmed = false;
      _sessionRepCount += 1;
      changed = true;
    }

    if (changed && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Knee Rehab Monitor'),
            actions: <Widget>[
              IconButton(
                tooltip: _controller.isScanning ? 'Stop scan' : 'Start scan',
                onPressed: _controller.isScanning ? _controller.stopScan : _controller.startScan,
                icon: Icon(_controller.isScanning ? Icons.stop_circle : Icons.bluetooth_searching),
              ),
            ],
          ),
          body: SafeArea(
            child: IndexedStack(
              index: _selectedIndex,
              children: <Widget>[
                _buildHomePage(context),
                _buildLiveSessionPage(context),
                _buildProgressPage(context),
                _buildDebugPage(context),
              ],
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) => setState(() => _selectedIndex = index),
            destinations: const <NavigationDestination>[
              NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
              NavigationDestination(icon: Icon(Icons.monitor_heart_outlined), selectedIcon: Icon(Icons.monitor_heart), label: 'Live'),
              NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Progress'),
              NavigationDestination(icon: Icon(Icons.developer_mode_outlined), selectedIcon: Icon(Icons.developer_mode), label: 'Debug'),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHomePage(BuildContext context) {
    final feedback = _feedbackPresentation;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _HeroAngleCard(
          angleDeg: _controller.currentAngleDeg,
          connectionSummary: _controller.connectionSummary,
          deviceName: _controller.connectedDeviceName ?? KneeBleContract.deviceName,
          telemetryFresh: _controller.hasFreshTelemetry,
          feedback: feedback,
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Exercise Target',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _FeedbackBanner(
                title: feedback.title,
                message: feedback.message,
                color: feedback.color,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: const <Widget>[
                  _MetricTile(label: 'Target Range', value: '10-110 deg'),
                  _MetricTile(label: 'Near Limit', value: 'Within 10 deg'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Quick Actions',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              FilledButton.icon(
                onPressed: _controller.canSendCommands ? _controller.sendZeroImu : null,
                icon: const Icon(Icons.exposure_zero),
                label: const Text('Zero Leg'),
              ),
              FilledButton.icon(
                onPressed: _controller.canSendCommands ? _startSession : null,
                icon: const Icon(Icons.play_arrow),
                label: Text(_sessionActive ? 'Session Running' : 'Start Session'),
              ),
              OutlinedButton.icon(
                onPressed: _controller.isConnected || _controller.isConnecting ? _controller.disconnect : null,
                icon: const Icon(Icons.link_off),
                label: const Text('Disconnect'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Status',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              _MetricTile(label: 'Connection', value: _controller.connectionSummary),
              _MetricTile(label: 'Permissions', value: _controller.permissionsGranted ? 'Granted' : 'Needed'),
              _MetricTile(label: 'Angle Feed', value: _controller.hasFreshTelemetry ? 'Live' : 'Waiting'),
              _MetricTile(label: 'Device', value: _controller.connectedDeviceName ?? 'None'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Available Devices',
          child: _buildDeviceList(emptyMessage: 'Tap Scan to search for KneeMaster.'),
        ),
        if (_controller.lastError != null) ...<Widget>[
          const SizedBox(height: 16),
          _ErrorCard(error: _controller.lastError!),
        ],
      ],
    );
  }

  Widget _buildLiveSessionPage(BuildContext context) {
    final feedback = _feedbackPresentation;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _SectionCard(
          title: 'Live Session',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                height: 320,
                child: _AngleGaugeCard(
                  angleDeg: _controller.currentAngleDeg,
                  targetMinDeg: _targetRangeMinDeg,
                  targetMaxDeg: _targetRangeMaxDeg,
                  feedback: feedback,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  _MetricTile(
                    label: 'Current Angle',
                    value: _controller.currentAngleDeg == null
                        ? '--'
                        : '${_controller.currentAngleDeg!.toStringAsFixed(1)} deg',
                    emphasize: true,
                  ),
                  _MetricTile(
                    label: 'Peak Flexion',
                    value: '${_sessionPeakFlexionDeg.toStringAsFixed(1)} deg',
                  ),
                  _MetricTile(
                    label: 'Extension Lag',
                    value: '${_sessionExtensionLagDeg.toStringAsFixed(1)} deg',
                  ),
                  _MetricTile(label: 'Reps', value: _sessionRepCount.toString()),
                  _MetricTile(label: 'Duration', value: _sessionDurationLabel),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 260,
                child: _AngleTrendCard(
                  samples: _controller.recentAngles,
                  targetBandMinDeg: _targetRangeMinDeg,
                  targetBandMaxDeg: _targetRangeMaxDeg,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: _controller.canSendCommands
                        ? (_sessionActive ? null : _startSession)
                        : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start Session'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _sessionActive ? _finishSession : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('End Session'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _controller.canSendCommands ? _controller.sendZeroImu : null,
                    icon: const Icon(Icons.exposure_zero),
                    label: const Text('Zero'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProgressPage(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _SectionCard(
          title: 'Progress Overview',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              _MetricTile(label: 'Sessions', value: _completedSessions.length.toString()),
              _MetricTile(label: 'Best Flexion', value: '${_bestFlexionDeg.toStringAsFixed(1)} deg'),
              _MetricTile(label: 'Lowest Extension Lag', value: '${_bestExtensionLagDeg.toStringAsFixed(1)} deg'),
              _MetricTile(label: 'Total Reps', value: _totalReps.toString()),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Session History',
          child: _completedSessions.isEmpty
              ? const Text('No sessions recorded yet. Start a live session to begin tracking recovery progress.')
              : Column(
                  children: _completedSessions.reversed
                      .map(
                        (session) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(child: Icon(Icons.directions_walk)),
                          title: Text(_sessionTitle(session)),
                          subtitle: Text(
                            'Peak flexion ${session.peakFlexionDeg.toStringAsFixed(1)} deg'
                            ' | Extension lag ${session.extensionLagDeg.toStringAsFixed(1)} deg'
                            ' | Reps ${session.repCount}',
                          ),
                          trailing: Text(_durationLabel(session.duration)),
                        ),
                      )
                      .toList(growable: false),
                ),
        ),
      ],
    );
  }

  Widget _buildDebugPage(BuildContext context) {
    final telemetry = _controller.telemetry;
    final status = _controller.status;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _SectionCard(
          title: 'BLE Diagnostics',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              _MetricTile(label: 'BLE', value: _bleStatusLabel(_controller.bleStatus)),
              _MetricTile(label: 'State', value: _controller.connectionState.name),
              _MetricTile(label: 'MTU', value: _controller.negotiatedMtu?.toString() ?? 'n/a'),
              _MetricTile(label: 'Payload', value: _controller.lastTelemetryPayloadLength?.toString() ?? 'n/a'),
              _MetricTile(label: 'Flags', value: telemetry == null ? 'n/a' : _flagsLabel(telemetry.flags), wide: true),
              _MetricTile(
                label: 'Status Snapshot',
                value: status == null ? 'n/a' : 'seq ${status.lastSequence}, uptime ${status.uptimeMs} ms',
                wide: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Device Discovery',
          child: _buildDeviceList(
            emptyMessage: _controller.isScanning
                ? 'Scanning for KneeMaster...'
                : 'No devices yet. Tap the scan button in the app bar.',
          ),
        ),
        if (_controller.lastError != null) ...<Widget>[
          const SizedBox(height: 16),
          _ErrorCard(error: _controller.lastError!),
        ],
      ],
    );
  }

  Widget _buildDeviceList({required String emptyMessage}) {
    final devices = _controller.devices;
    if (devices.isEmpty) {
      return Text(emptyMessage);
    }

    return Column(
      children: devices
          .map(
            (device) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(device.name.isNotEmpty ? device.name : KneeBleContract.deviceName),
              subtitle: Text('${device.id}\nRSSI ${device.rssi} dBm'),
              trailing: FilledButton(
                onPressed: () => _controller.connectToDevice(device),
                child: const Text('Connect'),
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  void _startSession() {
    setState(() {
      _sessionActive = true;
      _sessionStartedAt = DateTime.now();
      _sessionPeakFlexionDeg = 0.0;
      _sessionMinAngleDeg = 145.0;
      _sessionRepCount = 0;
      _repArmed = false;
      _selectedIndex = 1;
    });
  }

  void _finishSession() {
    final startedAt = _sessionStartedAt;
    if (startedAt != null) {
      final summary = SessionSummary(
        startedAt: startedAt,
        endedAt: DateTime.now(),
        peakFlexionDeg: _sessionPeakFlexionDeg,
        extensionLagDeg: _sessionExtensionLagDeg,
        repCount: _sessionRepCount,
      );
      setState(() {
        _completedSessions.add(summary);
      });
    }

    setState(() {
      _sessionActive = false;
      _sessionStartedAt = null;
      _repArmed = false;
      _selectedIndex = 2;
    });
  }

  double get _sessionExtensionLagDeg => _sessionMinAngleDeg == 145.0 ? 0.0 : _sessionMinAngleDeg;

  String get _sessionDurationLabel {
    final startedAt = _sessionStartedAt;
    if (!_sessionActive || startedAt == null) {
      return '00:00';
    }
    return _durationLabel(DateTime.now().difference(startedAt));
  }

  double get _bestFlexionDeg {
    if (_completedSessions.isEmpty) {
      return 0.0;
    }
    return _completedSessions
        .map((session) => session.peakFlexionDeg)
        .reduce((a, b) => a > b ? a : b);
  }

  double get _bestExtensionLagDeg {
    if (_completedSessions.isEmpty) {
      return 0.0;
    }
    return _completedSessions
        .map((session) => session.extensionLagDeg)
        .reduce((a, b) => a < b ? a : b);
  }

  int get _totalReps => _completedSessions.fold(0, (total, session) => total + session.repCount);

  String _sessionTitle(SessionSummary session) {
    final started = session.startedAt;
    final hour = started.hour.toString().padLeft(2, '0');
    final minute = started.minute.toString().padLeft(2, '0');
    final day = started.day.toString().padLeft(2, '0');
    final month = started.month.toString().padLeft(2, '0');
    return 'Session $day/$month at $hour:$minute';
  }

  String _durationLabel(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

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

  _FeedbackPresentation get _feedbackPresentation {
    final angle = _controller.currentAngleDeg;

    if (_controller.isConnecting) {
      return const _FeedbackPresentation(
        title: 'Connecting to device',
        message: 'Stay still while the app establishes the live knee angle feed.',
        color: Color(0xFF475569),
      );
    }
    if (_controller.isScanning) {
      return const _FeedbackPresentation(
        title: 'Searching for KneeMaster',
        message: 'The app is scanning for the wearable monitor.',
        color: Color(0xFF2563EB),
      );
    }
    if (!_controller.isConnected) {
      return const _FeedbackPresentation(
        title: 'Device disconnected',
        message: 'Connect to KneeMaster to begin live knee angle feedback.',
        color: Color(0xFF6B7280),
      );
    }
    if (_controller.isSensorStale || angle == null) {
      return const _FeedbackPresentation(
        title: 'Sensor stale',
        message: 'The wearable is connected but not sending a fresh knee angle yet.',
        color: Color(0xFFD97706),
      );
    }
    if (angle < _targetRangeMinDeg || angle > _targetRangeMaxDeg) {
      return const _FeedbackPresentation(
        title: 'Outside target range',
        message: 'Adjust your movement to bring the knee back inside the prescribed range.',
        color: Color(0xFFDC2626),
      );
    }
    final nearLower = angle <= _targetRangeMinDeg + _nearLimitBufferDeg;
    final nearUpper = angle >= _targetRangeMaxDeg - _nearLimitBufferDeg;
    if (nearLower || nearUpper) {
      return const _FeedbackPresentation(
        title: 'Near target limit',
        message: 'You are close to the target boundary. Move with control and hold steady.',
        color: Color(0xFFD97706),
      );
    }
    return const _FeedbackPresentation(
      title: 'Within target range',
      message: 'Good job. Your current knee angle is safely inside the prescribed exercise zone.',
      color: Color(0xFF15803D),
    );
  }
}

class _HeroAngleCard extends StatelessWidget {
  const _HeroAngleCard({
    required this.angleDeg,
    required this.connectionSummary,
    required this.deviceName,
    required this.telemetryFresh,
    required this.feedback,
  });

  final double? angleDeg;
  final String connectionSummary;
  final String deviceName;
  final bool telemetryFresh;
  final _FeedbackPresentation feedback;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: <Color>[
              colorScheme.primaryContainer,
              colorScheme.surfaceContainerHighest,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Current Knee Angle',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Text(
              angleDeg == null ? '--' : '${angleDeg!.toStringAsFixed(1)} deg',
              style: Theme.of(context).textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                Chip(label: Text(connectionSummary)),
                Chip(label: Text(deviceName)),
                Chip(label: Text(telemetryFresh ? 'Live data' : 'Waiting for telemetry')),
              ],
            ),
            const SizedBox(height: 12),
            _FeedbackBanner(
              title: feedback.title,
              message: feedback.message,
              color: feedback.color,
              compact: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    this.emphasize = false,
    this.wide = false,
  });

  final String label;
  final String value;
  final bool emphasize;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: wide ? 320 : 156,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 6),
              Text(
                value,
                style: emphasize
                    ? Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)
                    : Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.error,
  });

  final String error;

  @override
  Widget build(BuildContext context) {
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
}

class _FeedbackBanner extends StatelessWidget {
  const _FeedbackBanner({
    required this.title,
    required this.message,
    required this.color,
    this.compact = false,
  });

  final String title;
  final String message;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: compact ? 0.10 : 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.favorite, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF334155),
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AngleGaugeCard extends StatelessWidget {
  const _AngleGaugeCard({
    required this.angleDeg,
    required this.targetMinDeg,
    required this.targetMaxDeg,
    required this.feedback,
  });

  final double? angleDeg;
  final double targetMinDeg;
  final double targetMaxDeg;
  final _FeedbackPresentation feedback;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(24),
      ),
      child: CustomPaint(
        painter: _AngleGaugePainter(
          angleDeg: angleDeg,
          targetMinDeg: targetMinDeg,
          targetMaxDeg: targetMaxDeg,
          accentColor: feedback.color,
          textStyle: Theme.of(context).textTheme,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              Text(
                feedback.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                angleDeg == null ? '--' : '${angleDeg!.toStringAsFixed(1)} deg',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Target range ${targetMinDeg.toStringAsFixed(0)}-${targetMaxDeg.toStringAsFixed(0)} deg',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AngleTrendCard extends StatelessWidget {
  const _AngleTrendCard({
    required this.samples,
    required this.targetBandMinDeg,
    required this.targetBandMaxDeg,
  });

  final List<AngleHistorySample> samples;
  final double targetBandMinDeg;
  final double targetBandMaxDeg;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: samples.length < 2
            ? const Center(
                child: Text(
                  'Waiting for enough live data to draw the session trend.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
              )
            : CustomPaint(
                painter: _AngleTrendPainter(
                  samples: samples,
                  targetBandMinDeg: targetBandMinDeg,
                  targetBandMaxDeg: targetBandMaxDeg,
                ),
                size: Size.infinite,
              ),
      ),
    );
  }
}

class _AngleGaugePainter extends CustomPainter {
  _AngleGaugePainter({
    required this.angleDeg,
    required this.targetMinDeg,
    required this.targetMaxDeg,
    required this.accentColor,
    required this.textStyle,
  });

  final double? angleDeg;
  final double targetMinDeg;
  final double targetMaxDeg;
  final Color accentColor;
  final TextTheme textStyle;

  static const double _minAngle = 0.0;
  static const double _maxAngle = 145.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.84);
    final radius = size.width < size.height ? size.width * 0.34 : size.height * 0.34;
    final strokeWidth = 18.0;
    const startAngle = 3.141592653589793;
    const sweepAngle = 3.141592653589793;

    final backgroundPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final targetPaint = Paint()
      ..color = const Color(0xFF14B8A6).withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final valuePaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final needlePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final arcRect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(arcRect, startAngle, sweepAngle, false, backgroundPaint);

    final targetStart = _angleToSweep(targetMinDeg);
    final targetSweep = _angleToSweep(targetMaxDeg) - targetStart;
    canvas.drawArc(arcRect, startAngle + targetStart, targetSweep, false, targetPaint);

    if (angleDeg != null) {
      final clamped = angleDeg!.clamp(_minAngle, _maxAngle);
      final valueSweep = _angleToSweep(clamped);
      canvas.drawArc(arcRect, startAngle, valueSweep, false, valuePaint);

      final theta = startAngle + valueSweep;
      final needleEnd = Offset(
        center.dx + radius * 0.84 * math.cos(theta),
        center.dy + radius * 0.84 * math.sin(theta),
      );
      canvas.drawLine(center, needleEnd, needlePaint);
      canvas.drawCircle(center, 8, Paint()..color = Colors.white);
    }

    _paintTickLabel(canvas, '0', Offset(center.dx - radius - 4, center.dy - 8));
    _paintTickLabel(canvas, '72', Offset(center.dx - 12, center.dy - radius - 20));
    _paintTickLabel(canvas, '145', Offset(center.dx + radius - 22, center.dy - 8));
  }

  double _angleToSweep(double angle) {
    final normalized = ((angle - _minAngle) / (_maxAngle - _minAngle)).clamp(0.0, 1.0);
    return normalized * 3.141592653589793;
  }

  void _paintTickLabel(Canvas canvas, String text, Offset offset) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: textStyle.labelLarge?.copyWith(
          color: Colors.white70,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _AngleGaugePainter oldDelegate) {
    return oldDelegate.angleDeg != angleDeg ||
        oldDelegate.targetMinDeg != targetMinDeg ||
        oldDelegate.targetMaxDeg != targetMaxDeg ||
        oldDelegate.accentColor != accentColor;
  }
}

class _AngleTrendPainter extends CustomPainter {
  _AngleTrendPainter({
    required this.samples,
    required this.targetBandMinDeg,
    required this.targetBandMaxDeg,
  });

  final List<AngleHistorySample> samples;
  final double targetBandMinDeg;
  final double targetBandMaxDeg;

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 36.0;
    const rightPad = 10.0;
    const topPad = 8.0;
    const bottomPad = 22.0;
    final rect = Rect.fromLTWH(
      leftPad,
      topPad,
      size.width - leftPad - rightPad,
      size.height - topPad - bottomPad,
    );

    final gridPaint = Paint()
      ..color = const Color(0xFF334155)
      ..strokeWidth = 1;
    final borderPaint = Paint()
      ..color = const Color(0xFF475569)
      ..style = PaintingStyle.stroke;
    final targetPaint = Paint()..color = const Color(0xFF0F766E).withValues(alpha: 0.18);
    final tracePaint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawRect(rect, borderPaint);

    final targetTop = rect.bottom - ((targetBandMaxDeg / 145.0) * rect.height);
    final targetBottom = rect.bottom - ((targetBandMinDeg / 145.0) * rect.height);
    canvas.drawRect(
      Rect.fromLTRB(rect.left, targetTop, rect.right, targetBottom),
      targetPaint,
    );

    for (int i = 1; i <= 4; i++) {
      final y = rect.top + ((rect.height / 5) * i);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), gridPaint);
    }

    final startMs = samples.first.uptimeMs;
    final endMs = samples.last.uptimeMs;
    final spanMs = (endMs - startMs).clamp(1, 1 << 30);

    final path = Path();
    for (int i = 0; i < samples.length; i++) {
      final sample = samples[i];
      final x = rect.left + (((sample.uptimeMs - startMs) / spanMs) * rect.width);
      final clamped = sample.angleDeg.clamp(0.0, 145.0);
      final y = rect.bottom - ((clamped / 145.0) * rect.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, tracePaint);

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    void paintLabel(String text, Offset offset) {
      textPainter.text = TextSpan(
        text: text,
        style: const TextStyle(color: Colors.white70, fontSize: 11),
      );
      textPainter.layout();
      textPainter.paint(canvas, offset);
    }

    paintLabel('145', const Offset(4, 4));
    paintLabel('0', Offset(14, rect.bottom - 8));
    paintLabel('${(spanMs / 1000).toStringAsFixed(1)} s', Offset(rect.right - 36, rect.bottom + 4));
  }

  @override
  bool shouldRepaint(covariant _AngleTrendPainter oldDelegate) {
    return oldDelegate.samples != samples;
  }
}

class _FeedbackPresentation {
  const _FeedbackPresentation({
    required this.title,
    required this.message,
    required this.color,
  });

  final String title;
  final String message;
  final Color color;
}
