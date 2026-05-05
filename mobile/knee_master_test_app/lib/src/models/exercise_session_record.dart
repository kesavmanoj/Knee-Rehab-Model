enum SessionSyncState {
  synced,
  pendingUpload;
}

class ExerciseSessionRecord {
  const ExerciseSessionRecord({
    required this.id,
    required this.patientId,
    required this.startedAt,
    required this.endedAt,
    required this.exerciseType,
    required this.repCount,
    required this.peakFlexionDeg,
    required this.extensionLagDeg,
    required this.durationMs,
    required this.sessionStatus,
    required this.deviceName,
    required this.firmwareProtocolVersion,
    required this.syncState,
  });

  final String id;
  final String patientId;
  final DateTime startedAt;
  final DateTime endedAt;
  final String exerciseType;
  final int repCount;
  final double peakFlexionDeg;
  final double extensionLagDeg;
  final int durationMs;
  final String sessionStatus;
  final String? deviceName;
  final String? firmwareProtocolVersion;
  final SessionSyncState syncState;

  Duration get duration => Duration(milliseconds: durationMs);

  factory ExerciseSessionRecord.fromMap(Map<String, dynamic> map) {
    return ExerciseSessionRecord(
      id: map['id'] as String,
      patientId: map['patient_id'] as String,
      startedAt: DateTime.parse(map['started_at'] as String),
      endedAt: DateTime.parse(map['ended_at'] as String),
      exerciseType: map['exercise_type'] as String,
      repCount: (map['rep_count'] as num).toInt(),
      peakFlexionDeg: (map['peak_flexion_deg'] as num).toDouble(),
      extensionLagDeg: (map['extension_lag_deg'] as num).toDouble(),
      durationMs: (map['duration_ms'] as num).toInt(),
      sessionStatus: map['session_status'] as String? ?? 'completed',
      deviceName: map['device_name'] as String?,
      firmwareProtocolVersion: map['firmware_protocol_version'] as String?,
      syncState: SessionSyncState.synced,
    );
  }
}
