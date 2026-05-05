import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../ble/knee_ble_contract.dart';
import '../ble/knee_ble_controller.dart';
import '../ble/knee_telemetry.dart';
import '../models/exercise_session_record.dart';
import '../models/session_angle_sample.dart';
import '../models/session_upload_payload.dart';
import '../models/user_profile.dart';
import '../repositories/profile_repository.dart';
import '../repositories/session_repository.dart';

enum RehabExercise {
  heelSlides,
  seatedKneeFlexion,
  quadSets,
  straightLegRaises,
}

enum _RepDetectionMode {
  flexionReturn,
  extensionRelease,
}

class _ExerciseProfile {
  const _ExerciseProfile({
    required this.label,
    required this.subtitle,
    required this.targetMinDeg,
    required this.targetMaxDeg,
    required this.armThresholdDeg,
    required this.holdThresholdDeg,
    required this.releaseThresholdDeg,
    required this.minHoldDuration,
    required this.minApproachSpeedDegPerSec,
    required this.minReleaseSpeedDegPerSec,
    required this.mode,
  });

  final String label;
  final String subtitle;
  final double targetMinDeg;
  final double targetMaxDeg;
  final double armThresholdDeg;
  final double holdThresholdDeg;
  final double releaseThresholdDeg;
  final Duration minHoldDuration;
  final double minApproachSpeedDegPerSec;
  final double minReleaseSpeedDegPerSec;
  final _RepDetectionMode mode;
}

const Map<RehabExercise, _ExerciseProfile> _exerciseProfiles = {
  RehabExercise.heelSlides: _ExerciseProfile(
    label: 'Heel Slides',
    subtitle: 'Bend the knee smoothly, pause at flexion, then return toward extension.',
    targetMinDeg: 10.0,
    targetMaxDeg: 95.0,
    armThresholdDeg: 35.0,
    holdThresholdDeg: 45.0,
    releaseThresholdDeg: 20.0,
    minHoldDuration: Duration(milliseconds: 350),
    minApproachSpeedDegPerSec: 6.0,
    minReleaseSpeedDegPerSec: 6.0,
    mode: _RepDetectionMode.flexionReturn,
  ),
  RehabExercise.seatedKneeFlexion: _ExerciseProfile(
    label: 'Seated Knee Flexion',
    subtitle: 'Drive to a deeper bend, hold briefly, and return under control.',
    targetMinDeg: 20.0,
    targetMaxDeg: 115.0,
    armThresholdDeg: 60.0,
    holdThresholdDeg: 75.0,
    releaseThresholdDeg: 30.0,
    minHoldDuration: Duration(milliseconds: 500),
    minApproachSpeedDegPerSec: 6.0,
    minReleaseSpeedDegPerSec: 6.0,
    mode: _RepDetectionMode.flexionReturn,
  ),
  RehabExercise.quadSets: _ExerciseProfile(
    label: 'Quad Sets',
    subtitle: 'Straighten the knee fully, hold the squeeze, then relax.',
    targetMinDeg: 0.0,
    targetMaxDeg: 12.0,
    armThresholdDeg: 12.0,
    holdThresholdDeg: 6.0,
    releaseThresholdDeg: 16.0,
    minHoldDuration: Duration(milliseconds: 800),
    minApproachSpeedDegPerSec: 4.0,
    minReleaseSpeedDegPerSec: 3.0,
    mode: _RepDetectionMode.extensionRelease,
  ),
  RehabExercise.straightLegRaises: _ExerciseProfile(
    label: 'Straight-Leg Raises',
    subtitle: 'Keep the knee straight, hold the extension, then relax back down.',
    targetMinDeg: 0.0,
    targetMaxDeg: 15.0,
    armThresholdDeg: 14.0,
    holdThresholdDeg: 8.0,
    releaseThresholdDeg: 18.0,
    minHoldDuration: Duration(milliseconds: 900),
    minApproachSpeedDegPerSec: 4.0,
    minReleaseSpeedDegPerSec: 3.0,
    mode: _RepDetectionMode.extensionRelease,
  ),
};

class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.exercise,
    required this.startedAt,
    required this.endedAt,
    required this.peakFlexionDeg,
    required this.extensionLagDeg,
    required this.repCount,
    required this.syncState,
  });

  final String id;
  final RehabExercise exercise;
  final DateTime startedAt;
  final DateTime endedAt;
  final double peakFlexionDeg;
  final double extensionLagDeg;
  final int repCount;
  final SessionSyncState syncState;

  Duration get duration => endedAt.difference(startedAt);
}

class KneeHomeScreen extends StatefulWidget {
  const KneeHomeScreen({
    super.key,
    required this.profile,
    required this.sessionRepository,
    required this.profileRepository,
    required this.onLogout,
  });

  final UserProfile profile;
  final SessionRepository sessionRepository;
  final ProfileRepository profileRepository;
  final Future<void> Function() onLogout;

  @override
  State<KneeHomeScreen> createState() => _KneeHomeScreenState();
}

class _KneeHomeScreenState extends State<KneeHomeScreen> {
  static const double _nearLimitBufferDeg = 10.0;

  late final KneeBleController _controller;

  int _selectedIndex = 0;
  RehabExercise _selectedExercise = RehabExercise.heelSlides;
  bool _sessionActive = false;
  DateTime? _sessionStartedAt;
  double _sessionPeakFlexionDeg = 0.0;
  double _sessionMinAngleDeg = 145.0;
  int _sessionRepCount = 0;
  bool _repArmed = false;
  bool _holdSatisfied = false;
  DateTime? _holdStartedAt;
  DateTime? _lastRepSampleAt;
  double? _lastRepSampleAngleDeg;
  double _lastAngularSpeedDegPerSec = 0.0;
  final List<SessionAngleSample> _sessionAngleSamples = <SessionAngleSample>[];
  final List<SessionSummary> _completedSessions = <SessionSummary>[];
  final List<UserProfile> _linkedDoctors = <UserProfile>[];
  final TextEditingController _doctorCodeController = TextEditingController();
  DateTime? _lastStoredSessionSampleAt;
  bool _loadingSessions = true;
  bool _syncingSessions = false;
  bool _loadingDoctors = false;
  bool _linkingDoctor = false;
  String? _sessionSyncMessage;
  String? _sessionLoadError;
  String? _doctorLinkMessage;
  String? _doctorLinkError;

  @override
  void initState() {
    super.initState();
    _controller = KneeBleController();
    _controller.addListener(_handleControllerUpdate);
    _controller.requestPermissions();
    _loadCloudSessions();
    _loadLinkedDoctors();
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerUpdate);
    _controller.dispose();
    _doctorCodeController.dispose();
    super.dispose();
  }

  void _handleControllerUpdate() {
    if (!_sessionActive || !_controller.hasFreshTelemetry) {
      return;
    }

    final profile = _selectedProfile;
    final sampleTime = DateTime.now();
    final angle = _controller.currentAngleDeg;
    if (angle == null) {
      return;
    }

    final previousAt = _lastRepSampleAt;
    final previousAngle = _lastRepSampleAngleDeg;
    if (previousAt != null && previousAngle != null) {
      final dtMs = sampleTime.difference(previousAt).inMilliseconds;
      if (dtMs > 0) {
        final dtSeconds = dtMs / 1000.0;
        _lastAngularSpeedDegPerSec = (angle - previousAngle) / dtSeconds;
      }
    }
    _lastRepSampleAt = sampleTime;
    _lastRepSampleAngleDeg = angle;
    _captureSessionSample(sampleTime, angle);

    var changed = false;
    if (angle > _sessionPeakFlexionDeg) {
      _sessionPeakFlexionDeg = angle;
      changed = true;
    }
    if (angle < _sessionMinAngleDeg) {
      _sessionMinAngleDeg = angle;
      changed = true;
    }

    switch (profile.mode) {
      case _RepDetectionMode.flexionReturn:
        if (!_repArmed &&
            angle >= profile.armThresholdDeg &&
            _lastAngularSpeedDegPerSec >= profile.minApproachSpeedDegPerSec) {
          _repArmed = true;
          _holdStartedAt = null;
          _holdSatisfied = false;
          changed = true;
        }

        if (_repArmed) {
          if (angle >= profile.holdThresholdDeg) {
            _holdStartedAt ??= sampleTime;
            if (!_holdSatisfied &&
                sampleTime.difference(_holdStartedAt!) >= profile.minHoldDuration) {
              _holdSatisfied = true;
              changed = true;
            }
          } else if (!_holdSatisfied) {
            _holdStartedAt = null;
          }

          if (_holdSatisfied &&
              angle <= profile.releaseThresholdDeg &&
              _lastAngularSpeedDegPerSec <= -profile.minReleaseSpeedDegPerSec) {
            _sessionRepCount += 1;
            _repArmed = false;
            _holdStartedAt = null;
            _holdSatisfied = false;
            changed = true;
          }
        }
        break;
      case _RepDetectionMode.extensionRelease:
        if (!_repArmed &&
            angle <= profile.armThresholdDeg &&
            _lastAngularSpeedDegPerSec <= -profile.minApproachSpeedDegPerSec) {
          _repArmed = true;
          _holdStartedAt = null;
          _holdSatisfied = false;
          changed = true;
        }

        if (_repArmed) {
          if (angle <= profile.holdThresholdDeg) {
            _holdStartedAt ??= sampleTime;
            if (!_holdSatisfied &&
                sampleTime.difference(_holdStartedAt!) >= profile.minHoldDuration) {
              _holdSatisfied = true;
              changed = true;
            }
          } else if (!_holdSatisfied) {
            _holdStartedAt = null;
          }

          if (_holdSatisfied &&
              angle >= profile.releaseThresholdDeg &&
              _lastAngularSpeedDegPerSec >= profile.minReleaseSpeedDegPerSec) {
            _sessionRepCount += 1;
            _repArmed = false;
            _holdStartedAt = null;
            _holdSatisfied = false;
            changed = true;
          }
        }
        break;
    }

    if (changed && mounted) {
      setState(() {});
    }
  }

  Future<void> _loadCloudSessions() async {
    setState(() {
      _loadingSessions = true;
      _sessionLoadError = null;
    });

    try {
      final syncedCount = await widget.sessionRepository.retryPendingUploads();
      final records = await widget.sessionRepository.listMySessions(widget.profile.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _completedSessions
          ..clear()
          ..addAll(records.map(_summaryFromRecord));
        _loadingSessions = false;
        _syncingSessions = false;
        _sessionSyncMessage = syncedCount > 0
            ? 'Synced $syncedCount pending session${syncedCount == 1 ? '' : 's'}.'
            : null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingSessions = false;
        _syncingSessions = false;
        _sessionLoadError = 'Failed to load session history: $error';
      });
    }
  }

  Future<void> _loadLinkedDoctors() async {
    setState(() {
      _loadingDoctors = true;
      _doctorLinkError = null;
    });

    try {
      final doctors = await widget.profileRepository.listLinkedDoctors(widget.profile.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _linkedDoctors
          ..clear()
          ..addAll(doctors);
        _loadingDoctors = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingDoctors = false;
        _doctorLinkError = 'Failed to load linked doctors: $error';
      });
    }
  }

  Future<void> _linkDoctorCode() async {
    final code = _doctorCodeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() {
        _doctorLinkError = 'Enter the doctor code first.';
        _doctorLinkMessage = null;
      });
      return;
    }

    setState(() {
      _linkingDoctor = true;
      _doctorLinkError = null;
      _doctorLinkMessage = null;
    });

    try {
      final doctor = await widget.profileRepository.linkPatientToDoctorCode(code);
      if (!mounted) {
        return;
      }
      _doctorCodeController.clear();
      setState(() {
        final alreadyLinked = _linkedDoctors.any((entry) => entry.id == doctor.id);
        if (!alreadyLinked) {
          _linkedDoctors.insert(0, doctor);
        }
        _linkingDoctor = false;
        _doctorLinkMessage = 'Linked to ${doctor.displayName}.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _linkingDoctor = false;
        _doctorLinkError = 'Could not link doctor code: $error';
      });
    }
  }

  void _captureSessionSample(DateTime sampleTime, double angleDeg) {
    final startedAt = _sessionStartedAt;
    if (startedAt == null) {
      return;
    }

    const sampleInterval = Duration(milliseconds: 200);
    final previousAt = _lastStoredSessionSampleAt;
    if (previousAt != null && sampleTime.difference(previousAt) < sampleInterval) {
      return;
    }

    _lastStoredSessionSampleAt = sampleTime;
    _sessionAngleSamples.add(
      SessionAngleSample(
        sampleIndex: _sessionAngleSamples.length,
        elapsedMs: sampleTime.difference(startedAt).inMilliseconds,
        finalAngleDeg: angleDeg,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text('Knee Rehab Monitor • ${widget.profile.displayName}'),
            actions: <Widget>[
              IconButton(
                tooltip: _controller.isScanning ? 'Stop scan' : 'Start scan',
                onPressed: _controller.isScanning ? _controller.stopScan : _controller.startScan,
                icon: Icon(_controller.isScanning ? Icons.stop_circle : Icons.bluetooth_searching),
              ),
              IconButton(
                tooltip: 'Sync sessions',
                onPressed: _loadingSessions ? null : _loadCloudSessions,
                icon: const Icon(Icons.cloud_sync_outlined),
              ),
              IconButton(
                tooltip: 'Logout',
                onPressed: widget.onLogout,
                icon: const Icon(Icons.logout),
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _SectionCard(
          title: 'Welcome',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Welcome ${widget.profile.displayName}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Use this app to connect to KneeMaster, run your rehab sessions, and keep your doctor updated with your completed exercise history.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Find KneeMaster',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: _controller.isScanning ? _controller.stopScan : _controller.startScan,
                    icon: Icon(
                      _controller.isScanning ? Icons.stop_circle : Icons.bluetooth_searching,
                    ),
                    label: Text(_controller.isScanning ? 'Stop Scan' : 'Scan for Devices'),
                  ),
                  if (_controller.isConnected || _controller.isConnecting)
                    OutlinedButton.icon(
                      onPressed: _controller.disconnect,
                      icon: const Icon(Icons.link_off),
                      label: const Text('Disconnect'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _buildDeviceList(
                emptyMessage: _controller.isScanning
                    ? 'Searching for KneeMaster devices nearby...'
                    : 'Tap Scan for Devices to look for KneeMaster.',
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
              _MetricTile(label: 'Role', value: widget.profile.role.name),
              _MetricTile(label: 'Connection', value: _controller.connectionSummary),
              _MetricTile(label: 'Permissions', value: _controller.permissionsGranted ? 'Granted' : 'Needed'),
              _MetricTile(label: 'Angle Feed', value: _controller.hasFreshTelemetry ? 'Live' : 'Waiting'),
              _MetricTile(label: 'Device', value: _controller.connectedDeviceName ?? 'None'),
              _MetricTile(
                label: 'Cloud Sync',
                value: _syncingSessions
                    ? 'Syncing'
                    : _loadingSessions
                    ? 'Loading'
                    : (_completedSessions.any((session) => session.syncState == SessionSyncState.pendingUpload)
                        ? 'Pending'
                        : 'Up to date'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Care Team',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Enter your doctor code to connect your account with the right clinician. Once linked, your completed exercise sessions and final knee-angle graphs are available to that doctor.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _doctorCodeController,
                      enabled: !_linkingDoctor,
                      autocorrect: false,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Doctor code',
                        hintText: 'Enter 8-character code',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _linkingDoctor ? null : _linkDoctorCode,
                    child: Text(_linkingDoctor ? 'Linking...' : 'Link'),
                  ),
                ],
              ),
              if (_doctorLinkMessage != null) ...<Widget>[
                const SizedBox(height: 12),
                _InfoCard(message: _doctorLinkMessage!),
              ],
              if (_doctorLinkError != null) ...<Widget>[
                const SizedBox(height: 12),
                _ErrorCard(error: _doctorLinkError!),
              ],
              const SizedBox(height: 12),
              if (_loadingDoctors)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Text('Loading linked doctors...'),
                    ],
                  ),
                )
              else if (_linkedDoctors.isEmpty)
                const Text(
                  'No doctor is linked yet. Ask your doctor for their code and enter it here.',
                )
              else
                Column(
                  children: _linkedDoctors
                      .map(
                        (doctor) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(
                            child: Icon(Icons.medical_services_outlined),
                          ),
                          title: Text(doctor.displayName),
                          subtitle: Text(
                            doctor.doctorLinkCode == null
                                ? 'Doctor account linked'
                                : 'Code ${doctor.doctorLinkCode}',
                          ),
                        ),
                      )
                      .toList(growable: false),
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
              OutlinedButton.icon(
                onPressed: _controller.canSendCommands ? _controller.sendClearZero : null,
                icon: const Icon(Icons.refresh),
                label: const Text('Reset Zero'),
              ),
              FilledButton.icon(
                onPressed: _controller.canSendCommands && !_sessionActive ? _startSession : null,
                icon: const Icon(Icons.play_arrow),
                label: Text(_sessionActive ? 'Session Running' : 'Start Session'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _HeroAngleCard(
          angleDeg: _controller.currentAngleDeg,
          connectionSummary: _controller.connectionSummary,
          deviceName: _controller.connectedDeviceName ?? KneeBleContract.deviceName,
          telemetryFresh: _controller.hasFreshTelemetry,
        ),
        if (_sessionSyncMessage != null) ...<Widget>[
          const SizedBox(height: 16),
          _InfoCard(message: _sessionSyncMessage!),
        ],
        if (_sessionLoadError != null) ...<Widget>[
          const SizedBox(height: 16),
          _ErrorCard(error: _sessionLoadError!),
        ],
        if (_controller.lastError != null) ...<Widget>[
          const SizedBox(height: 16),
          _ErrorCard(error: _controller.lastError!),
        ],
      ],
    );
  }

  Widget _buildLiveSessionPage(BuildContext context) {
    final feedback = _feedbackPresentation;
    final profile = _selectedProfile;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _SectionCard(
          title: 'Live Session',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _SectionCard(
                title: 'Exercise Plan',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    DropdownButtonFormField<RehabExercise>(
                      initialValue: _selectedExercise,
                      decoration: const InputDecoration(
                        labelText: 'Exercise',
                        border: OutlineInputBorder(),
                      ),
                      items: RehabExercise.values
                          .map(
                            (exercise) => DropdownMenuItem<RehabExercise>(
                              value: exercise,
                              child: Text(_exerciseProfiles[exercise]!.label),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: _sessionActive
                          ? null
                          : (exercise) {
                              if (exercise == null) {
                                return;
                              }
                              setState(() {
                                _selectedExercise = exercise;
                                _resetRepTracking();
                              });
                            },
                    ),
                    const SizedBox(height: 12),
                    _FeedbackBanner(
                      title: feedback.title,
                      message: feedback.message,
                      color: feedback.color,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: <Widget>[
                        _MetricTile(
                          label: 'Target Range',
                          value:
                              '${profile.targetMinDeg.toStringAsFixed(0)}-${profile.targetMaxDeg.toStringAsFixed(0)} deg',
                        ),
                        const _MetricTile(label: 'Near Limit', value: 'Within 10 deg'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      profile.subtitle,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 360,
                child: _AngleGaugeCard(
                  angleDeg: _controller.currentAngleDeg,
                  targetMinDeg: profile.targetMinDeg,
                  targetMaxDeg: profile.targetMaxDeg,
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
                  _MetricTile(
                    label: 'Hold',
                    value: '${profile.minHoldDuration.inMilliseconds} ms',
                  ),
                  _MetricTile(
                    label: 'Speed',
                    value: '${_lastAngularSpeedDegPerSec.toStringAsFixed(1)} deg/s',
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
                  targetBandMinDeg: profile.targetMinDeg,
                  targetBandMaxDeg: profile.targetMaxDeg,
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
                  OutlinedButton.icon(
                    onPressed: _controller.canSendCommands ? _controller.sendClearZero : null,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reset Zero'),
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
        if (_loadingSessions)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                  SizedBox(width: 12),
                  Text('Loading cloud-backed session history...'),
                ],
              ),
            ),
          ),
        if (_sessionLoadError != null) ...<Widget>[
          _ErrorCard(error: _sessionLoadError!),
          const SizedBox(height: 16),
        ],
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
                            '${_exerciseProfiles[session.exercise]!.label}'
                            ' | Peak flexion ${session.peakFlexionDeg.toStringAsFixed(1)} deg'
                            ' | Extension lag ${session.extensionLagDeg.toStringAsFixed(1)} deg'
                            ' | Reps ${session.repCount}'
                            ' | ${session.syncState == SessionSyncState.synced ? 'Synced' : 'Pending upload'}',
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
    final startedAt = DateTime.now();
    final currentAngle = _controller.currentAngleDeg;
    setState(() {
      _sessionActive = true;
      _sessionStartedAt = startedAt;
      _sessionPeakFlexionDeg = 0.0;
      _sessionMinAngleDeg = 145.0;
      _sessionRepCount = 0;
      _sessionAngleSamples.clear();
      _lastStoredSessionSampleAt = null;
      _resetRepTracking();
      _selectedIndex = 1;
    });
    if (currentAngle != null) {
      _captureSessionSample(startedAt, currentAngle);
    }
  }

  Future<void> _finishSession() async {
    final startedAt = _sessionStartedAt;
    if (startedAt != null) {
      final endedAt = DateTime.now();
      final finalAngle = _controller.currentAngleDeg;
      if (finalAngle != null) {
        _captureSessionSample(endedAt, finalAngle);
      }

      final payload = SessionUploadPayload(
        patientId: widget.profile.id,
        startedAt: startedAt,
        endedAt: endedAt,
        exerciseType: _exerciseTypeForCloud(_selectedExercise),
        repCount: _sessionRepCount,
        peakFlexionDeg: _sessionPeakFlexionDeg,
        extensionLagDeg: _sessionExtensionLagDeg,
        durationMs: endedAt.difference(startedAt).inMilliseconds,
        sessionStatus: 'completed',
        deviceName: _controller.connectedDeviceName ?? KneeBleContract.deviceName,
        firmwareProtocolVersion: 'phone-v1',
        samples: List<SessionAngleSample>.from(_sessionAngleSamples),
      );

      setState(() {
        _sessionSyncMessage = null;
        _sessionLoadError = null;
        _syncingSessions = true;
        _sessionActive = false;
        _sessionStartedAt = null;
        _resetRepTracking();
        _selectedIndex = 2;
      });
      try {
        await widget.sessionRepository.uploadCompletedSession(payload);
        if (!mounted) {
          return;
        }
        setState(() {
          _sessionSyncMessage = 'Session uploaded successfully.';
        });
      } catch (_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _sessionSyncMessage =
              'Session saved locally and marked pending upload. It will retry on the next sync.';
        });
      } finally {
        if (mounted) {
          await _loadCloudSessions();
        }
      }
      return;
    }

    setState(() {
      _sessionActive = false;
      _sessionStartedAt = null;
      _resetRepTracking();
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
    return '${_exerciseProfiles[session.exercise]!.label} • $day/$month at $hour:$minute';
  }

  SessionSummary _summaryFromRecord(ExerciseSessionRecord record) {
    return SessionSummary(
      id: record.id,
      exercise: _exerciseFromCloud(record.exerciseType),
      startedAt: record.startedAt,
      endedAt: record.endedAt,
      peakFlexionDeg: record.peakFlexionDeg,
      extensionLagDeg: record.extensionLagDeg,
      repCount: record.repCount,
      syncState: record.syncState,
    );
  }

  RehabExercise _exerciseFromCloud(String value) {
    switch (value) {
      case 'heel_slides':
        return RehabExercise.heelSlides;
      case 'seated_knee_flexion':
        return RehabExercise.seatedKneeFlexion;
      case 'quad_sets':
        return RehabExercise.quadSets;
      case 'straight_leg_raises':
        return RehabExercise.straightLegRaises;
      default:
        return RehabExercise.heelSlides;
    }
  }

  String _exerciseTypeForCloud(RehabExercise exercise) {
    switch (exercise) {
      case RehabExercise.heelSlides:
        return 'heel_slides';
      case RehabExercise.seatedKneeFlexion:
        return 'seated_knee_flexion';
      case RehabExercise.quadSets:
        return 'quad_sets';
      case RehabExercise.straightLegRaises:
        return 'straight_leg_raises';
    }
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
    final profile = _selectedProfile;

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
    if (angle < profile.targetMinDeg || angle > profile.targetMaxDeg) {
      return const _FeedbackPresentation(
        title: 'Outside target range',
        message: 'Adjust your movement to bring the knee back inside the prescribed range.',
        color: Color(0xFFDC2626),
      );
    }
    final nearLower = angle <= profile.targetMinDeg + _nearLimitBufferDeg;
    final nearUpper = angle >= profile.targetMaxDeg - _nearLimitBufferDeg;
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

  _ExerciseProfile get _selectedProfile => _exerciseProfiles[_selectedExercise]!;

  void _resetRepTracking() {
    _repArmed = false;
    _holdSatisfied = false;
    _holdStartedAt = null;
    _lastRepSampleAt = null;
    _lastRepSampleAngleDeg = null;
    _lastAngularSpeedDegPerSec = 0.0;
  }
}

class _HeroAngleCard extends StatelessWidget {
  const _HeroAngleCard({
    required this.angleDeg,
    required this.connectionSummary,
    required this.deviceName,
    required this.telemetryFresh,
  });

  final double? angleDeg;
  final String connectionSummary;
  final String deviceName;
  final bool telemetryFresh;

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
            _AnimatedAngleText(
              angleDeg: angleDeg,
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

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFEAF7F6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.info_outline, color: Color(0xFF0B8F8C)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium,
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
  });

  final String title;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: angleDeg ?? 0.0, end: angleDeg ?? 0.0),
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              builder: (context, animatedAngle, _) {
                return Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        feedback.title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 6),
                      _AnimatedAngleText(
                        angleDeg: angleDeg == null ? null : animatedAngle,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Gauge scale 0-180 deg  •  Target ${targetMinDeg.toStringAsFixed(0)}-${targetMaxDeg.toStringAsFixed(0)} deg',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.white70,
                            ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: _AngleGaugePainter(
                              angleDeg: angleDeg == null ? null : animatedAngle,
                              targetMinDeg: targetMinDeg,
                              targetMaxDeg: targetMaxDeg,
                              accentColor: feedback.color,
                              textStyle: Theme.of(context).textTheme,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
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
            : RepaintBoundary(
                child: CustomPaint(
                  painter: _AngleTrendPainter(
                    samples: samples,
                    targetBandMinDeg: targetBandMinDeg,
                    targetBandMaxDeg: targetBandMaxDeg,
                  ),
                  size: Size.infinite,
                ),
              ),
      ),
    );
  }
}

class _AnimatedAngleText extends StatelessWidget {
  const _AnimatedAngleText({
    required this.angleDeg,
    required this.style,
    this.textAlign,
  });

  final double? angleDeg;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    if (angleDeg == null) {
      return Text('--', textAlign: textAlign, style: style);
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: angleDeg!, end: angleDeg!),
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return Text(
          '${value.toStringAsFixed(1)} deg',
          textAlign: textAlign,
          style: style,
        );
      },
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
  static const double _maxAngle = 180.0;

  @override
  void paint(Canvas canvas, Size size) {
    final horizontalPadding = 8.0;
    final availableWidth = size.width - (horizontalPadding * 2);
    final radius = math.min(availableWidth / 2, size.height * 0.82);
    final center = Offset(size.width / 2, size.height - 10);
    final strokeWidth = 20.0;
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
        center.dx + radius * 0.78 * math.cos(theta),
        center.dy + radius * 0.78 * math.sin(theta),
      );
      canvas.drawLine(center, needleEnd, needlePaint);
      canvas.drawCircle(center, 8, Paint()..color = Colors.white);
    }

    _paintTickLabel(canvas, '0', Offset(center.dx - radius - 4, center.dy - 20));
    _paintTickLabel(canvas, '90', Offset(center.dx - 12, center.dy - radius - 24));
    _paintTickLabel(canvas, '180', Offset(center.dx + radius - 28, center.dy - 20));
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

    final points = <Offset>[];
    for (final sample in samples) {
      final x = rect.left + (((sample.uptimeMs - startMs) / spanMs) * rect.width);
      final clamped = sample.angleDeg.clamp(0.0, 145.0);
      final y = rect.bottom - ((clamped / 145.0) * rect.height);
      points.add(Offset(x, y));
    }

    final path = Path();
    path.moveTo(points.first.dx, points.first.dy);
    if (points.length == 2) {
      path.lineTo(points.last.dx, points.last.dy);
    } else {
      for (int i = 0; i < points.length - 1; i++) {
        final current = points[i];
        final next = points[i + 1];
        final mid = Offset((current.dx + next.dx) / 2, (current.dy + next.dy) / 2);
        if (i == 0) {
          path.quadraticBezierTo(current.dx, current.dy, mid.dx, mid.dy);
        } else {
          path.quadraticBezierTo(current.dx, current.dy, mid.dx, mid.dy);
        }
      }
      path.lineTo(points.last.dx, points.last.dy);
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
