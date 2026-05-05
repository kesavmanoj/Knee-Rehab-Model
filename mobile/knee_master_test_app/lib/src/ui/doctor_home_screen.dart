import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/exercise_session_detail.dart';
import '../models/exercise_session_record.dart';
import '../models/patient_summary.dart';
import '../models/session_angle_sample.dart';
import '../models/user_profile.dart';
import '../repositories/doctor_repository.dart';
import '../repositories/session_repository.dart';

class DoctorHomeScreen extends StatefulWidget {
  const DoctorHomeScreen({
    super.key,
    required this.profile,
    required this.doctorRepository,
    required this.sessionRepository,
    required this.onLogout,
  });

  final UserProfile profile;
  final DoctorRepository doctorRepository;
  final SessionRepository sessionRepository;
  final Future<void> Function() onLogout;

  @override
  State<DoctorHomeScreen> createState() => _DoctorHomeScreenState();
}

class _DoctorHomeScreenState extends State<DoctorHomeScreen> {
  bool _loading = true;
  String? _error;
  List<PatientSummary> _patients = const <PatientSummary>[];

  @override
  void initState() {
    super.initState();
    _loadPatients();
  }

  Future<void> _loadPatients() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final patients = await widget.doctorRepository.listAssignedPatients(
        widget.profile.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _patients = patients;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Failed to load patients: $error';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Doctor Dashboard'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadPatients,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : ListView(
                        padding: const EdgeInsets.all(16),
                        children: <Widget>[
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    'Welcome, ${widget.profile.displayName}',
                                    style: Theme.of(context).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Review assigned patients, their completed sessions, and fused-angle session graphs.',
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          'Your patient link code',
                                          style: Theme.of(context).textTheme.labelLarge,
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          widget.profile.doctorLinkCode ?? 'Code unavailable',
                                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 1.6,
                                              ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Share this code with patients so they can link their accounts to you from the app.',
                                          style: Theme.of(context).textTheme.bodyMedium,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: <Widget>[
                                      _DoctorMetricCard(
                                        label: 'Assigned patients',
                                        value: _patients.length.toString(),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Patients',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          if (_patients.isEmpty)
                            const Card(
                              child: Padding(
                                padding: EdgeInsets.all(20),
                                child: Text(
                                  'No patients are assigned to this doctor account yet. Share your doctor code above so a patient can link to you from the app.',
                                ),
                              ),
                            )
                          else
                            ..._patients.map(
                              (patient) => Card(
                                child: ListTile(
                                  leading: const CircleAvatar(
                                    child: Icon(Icons.person_outline),
                                  ),
                                  title: Text(patient.displayName),
                                  subtitle: Text(
                                    'Linked ${_formatDate(patient.linkedAt)}',
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => _DoctorPatientDetailScreen(
                                          patient: patient,
                                          sessionRepository: widget.sessionRepository,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                        ],
                      ),
      ),
    );
  }

  String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();
    return '$day/$month/$year';
  }
}

class _DoctorPatientDetailScreen extends StatefulWidget {
  const _DoctorPatientDetailScreen({
    required this.patient,
    required this.sessionRepository,
  });

  final PatientSummary patient;
  final SessionRepository sessionRepository;

  @override
  State<_DoctorPatientDetailScreen> createState() =>
      _DoctorPatientDetailScreenState();
}

class _DoctorPatientDetailScreenState extends State<_DoctorPatientDetailScreen> {
  bool _loading = true;
  String? _error;
  List<ExerciseSessionRecord> _sessions = const <ExerciseSessionRecord>[];

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sessions = await widget.sessionRepository.listPatientSessions(
        widget.patient.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _sessions = sessions;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Failed to load patient sessions: $error';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.patient.displayName),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadSessions,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : _sessions.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'This patient has no completed exercise sessions yet.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: <Widget>[
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: <Widget>[
                                  _DoctorMetricCard(
                                    label: 'Sessions',
                                    value: _sessions.length.toString(),
                                  ),
                                  _DoctorMetricCard(
                                    label: 'Best flexion',
                                    value:
                                        '${_sessions.map((s) => s.peakFlexionDeg).fold<double>(0.0, math.max).toStringAsFixed(1)} deg',
                                  ),
                                  _DoctorMetricCard(
                                    label: 'Lowest extension lag',
                                    value:
                                        '${_sessions.map((s) => s.extensionLagDeg).reduce(math.min).toStringAsFixed(1)} deg',
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ..._sessions.map(
                            (session) => Card(
                              child: ListTile(
                                title: Text(_titleForSession(session)),
                                subtitle: Text(
                                  '${_exerciseLabel(session.exerciseType)} • Reps ${session.repCount} • Peak ${session.peakFlexionDeg.toStringAsFixed(1)} deg • Lag ${session.extensionLagDeg.toStringAsFixed(1)} deg',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => _DoctorSessionDetailScreen(
                                        session: session,
                                        sessionRepository: widget.sessionRepository,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
      ),
    );
  }

  String _titleForSession(ExerciseSessionRecord session) {
    final started = session.startedAt;
    final day = started.day.toString().padLeft(2, '0');
    final month = started.month.toString().padLeft(2, '0');
    final hour = started.hour.toString().padLeft(2, '0');
    final minute = started.minute.toString().padLeft(2, '0');
    return '${_exerciseLabel(session.exerciseType)} • $day/$month $hour:$minute';
  }

  String _exerciseLabel(String type) {
    switch (type) {
      case 'heel_slides':
        return 'Heel Slides';
      case 'seated_knee_flexion':
        return 'Seated Knee Flexion';
      case 'quad_sets':
        return 'Quad Sets';
      case 'straight_leg_raises':
        return 'Straight-Leg Raises';
      default:
        return type;
    }
  }
}

class _DoctorSessionDetailScreen extends StatefulWidget {
  const _DoctorSessionDetailScreen({
    required this.session,
    required this.sessionRepository,
  });

  final ExerciseSessionRecord session;
  final SessionRepository sessionRepository;

  @override
  State<_DoctorSessionDetailScreen> createState() =>
      _DoctorSessionDetailScreenState();
}

class _DoctorSessionDetailScreenState extends State<_DoctorSessionDetailScreen> {
  bool _loading = true;
  String? _error;
  ExerciseSessionDetail? _detail;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.sessionRepository.getSessionDetail(
        widget.session,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Failed to load session detail: $error';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Detail'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : detail == null
                    ? const Center(child: Text('No session detail available.'))
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: <Widget>[
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: <Widget>[
                                  _DoctorMetricCard(
                                    label: 'Exercise',
                                    value: _exerciseLabel(detail.record.exerciseType),
                                  ),
                                  _DoctorMetricCard(
                                    label: 'Reps',
                                    value: detail.record.repCount.toString(),
                                  ),
                                  _DoctorMetricCard(
                                    label: 'Peak flexion',
                                    value:
                                        '${detail.record.peakFlexionDeg.toStringAsFixed(1)} deg',
                                  ),
                                  _DoctorMetricCard(
                                    label: 'Extension lag',
                                    value:
                                        '${detail.record.extensionLagDeg.toStringAsFixed(1)} deg',
                                  ),
                                  _DoctorMetricCard(
                                    label: 'Duration',
                                    value: _durationLabel(detail.record.duration),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: SizedBox(
                                height: 280,
                                child: detail.samples.isEmpty
                                    ? const Center(
                                        child: Text(
                                          'No fused-angle graph samples were stored for this session.',
                                          textAlign: TextAlign.center,
                                        ),
                                      )
                                    : _DoctorSessionGraph(samples: detail.samples),
                              ),
                            ),
                          ),
                        ],
                      ),
      ),
    );
  }

  String _durationLabel(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _exerciseLabel(String type) {
    switch (type) {
      case 'heel_slides':
        return 'Heel Slides';
      case 'seated_knee_flexion':
        return 'Seated Knee Flexion';
      case 'quad_sets':
        return 'Quad Sets';
      case 'straight_leg_raises':
        return 'Straight-Leg Raises';
      default:
        return type;
    }
  }
}

class _DoctorMetricCard extends StatelessWidget {
  const _DoctorMetricCard({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _DoctorSessionGraph extends StatelessWidget {
  const _DoctorSessionGraph({
    required this.samples,
  });

  final List<SessionAngleSample> samples;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DoctorSessionGraphPainter(
        samples,
        lineColor: Theme.of(context).colorScheme.primary,
        axisColor: Theme.of(context).colorScheme.outline,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _DoctorSessionGraphPainter extends CustomPainter {
  _DoctorSessionGraphPainter(
    this.samples, {
    required this.lineColor,
    required this.axisColor,
  });

  final List<SessionAngleSample> samples;
  final Color lineColor;
  final Color axisColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) {
      return;
    }

    const padding = EdgeInsets.fromLTRB(18, 18, 18, 28);
    final chartRect = Rect.fromLTWH(
      padding.left,
      padding.top,
      size.width - padding.left - padding.right,
      size.height - padding.top - padding.bottom,
    );

    final axisPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1;
    canvas.drawRect(chartRect, axisPaint..style = PaintingStyle.stroke);

    final minAngle = samples
        .map((sample) => sample.finalAngleDeg)
        .reduce(math.min);
    final maxAngle = samples
        .map((sample) => sample.finalAngleDeg)
        .reduce(math.max);
    final minTime = samples
        .map((sample) => sample.elapsedMs.toDouble())
        .reduce(math.min);
    final maxTime = samples
        .map((sample) => sample.elapsedMs.toDouble())
        .reduce(math.max);

    double normalizeX(double elapsedMs) {
      if (maxTime == minTime) {
        return chartRect.left;
      }
      return chartRect.left +
          ((elapsedMs - minTime) / (maxTime - minTime)) * chartRect.width;
    }

    double normalizeY(double angleDeg) {
      if (maxAngle == minAngle) {
        return chartRect.center.dy;
      }
      return chartRect.bottom -
          ((angleDeg - minAngle) / (maxAngle - minAngle)) * chartRect.height;
    }

    final path = Path();
    for (var i = 0; i < samples.length; i += 1) {
      final sample = samples[i];
      final dx = normalizeX(sample.elapsedMs.toDouble());
      final dy = normalizeY(sample.finalAngleDeg);
      if (i == 0) {
        path.moveTo(dx, dy);
      } else {
        path.lineTo(dx, dy);
      }
    }

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _DoctorSessionGraphPainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.axisColor != axisColor;
  }
}
