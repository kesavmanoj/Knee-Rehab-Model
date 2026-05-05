import 'dart:convert';

import 'session_angle_sample.dart';

class SessionUploadPayload {
  const SessionUploadPayload({
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
    required this.samples,
  });

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
  final List<SessionAngleSample> samples;

  Map<String, dynamic> toSessionInsertMap() {
    return <String, dynamic>{
      'patient_id': patientId,
      'started_at': startedAt.toIso8601String(),
      'ended_at': endedAt.toIso8601String(),
      'exercise_type': exerciseType,
      'rep_count': repCount,
      'peak_flexion_deg': peakFlexionDeg,
      'extension_lag_deg': extensionLagDeg,
      'duration_ms': durationMs,
      'session_status': sessionStatus,
      'device_name': deviceName,
      'firmware_protocol_version': firmwareProtocolVersion,
    };
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'patient_id': patientId,
      'started_at': startedAt.toIso8601String(),
      'ended_at': endedAt.toIso8601String(),
      'exercise_type': exerciseType,
      'rep_count': repCount,
      'peak_flexion_deg': peakFlexionDeg,
      'extension_lag_deg': extensionLagDeg,
      'duration_ms': durationMs,
      'session_status': sessionStatus,
      'device_name': deviceName,
      'firmware_protocol_version': firmwareProtocolVersion,
      'samples': samples.map((sample) => sample.toJson()).toList(growable: false),
    };
  }

  factory SessionUploadPayload.fromJson(Map<String, dynamic> map) {
    return SessionUploadPayload(
      patientId: map['patient_id'] as String,
      startedAt: DateTime.parse(map['started_at'] as String),
      endedAt: DateTime.parse(map['ended_at'] as String),
      exerciseType: map['exercise_type'] as String,
      repCount: (map['rep_count'] as num).toInt(),
      peakFlexionDeg: (map['peak_flexion_deg'] as num).toDouble(),
      extensionLagDeg: (map['extension_lag_deg'] as num).toDouble(),
      durationMs: (map['duration_ms'] as num).toInt(),
      sessionStatus: map['session_status'] as String,
      deviceName: map['device_name'] as String?,
      firmwareProtocolVersion: map['firmware_protocol_version'] as String?,
      samples: ((map['samples'] as List<dynamic>? ?? const <dynamic>[]))
          .map((sample) => SessionAngleSample.fromJson(
                Map<String, dynamic>.from(sample as Map),
              ))
          .toList(growable: false),
    );
  }

  String encode() => jsonEncode(toJson());

  factory SessionUploadPayload.decode(String source) =>
      SessionUploadPayload.fromJson(jsonDecode(source) as Map<String, dynamic>);
}
