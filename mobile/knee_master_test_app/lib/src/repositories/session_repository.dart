import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/exercise_session_detail.dart';
import '../models/exercise_session_record.dart';
import '../models/session_angle_sample.dart';
import '../models/session_upload_payload.dart';
import 'pending_session_queue.dart';

class SessionRepository {
  SessionRepository(
    this._client, {
    PendingSessionQueue? pendingQueue,
  }) : _pendingQueue = pendingQueue ?? PendingSessionQueue();

  final SupabaseClient _client;
  final PendingSessionQueue _pendingQueue;

  Future<List<ExerciseSessionRecord>> listMySessions(String patientId) async {
    final remote = await listPatientSessions(patientId);
    final pending = await _pendingQueue.load();
    final pendingRecords = pending
        .where((payload) => payload.patientId == patientId)
        .map(_pendingPayloadToRecord)
        .toList(growable: false);
    final combined = <ExerciseSessionRecord>[...remote, ...pendingRecords];
    combined.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return combined;
  }

  Future<List<ExerciseSessionRecord>> listPatientSessions(String patientId) async {
    final response = await _client
        .from('exercise_sessions')
        .select()
        .eq('patient_id', patientId)
        .order('started_at', ascending: false);

    return (response as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(ExerciseSessionRecord.fromMap)
        .toList(growable: false);
  }

  Future<ExerciseSessionDetail> getSessionDetail(ExerciseSessionRecord record) async {
    if (record.syncState == SessionSyncState.pendingUpload) {
      final pendingPayloads = await _pendingQueue.load();
      SessionUploadPayload? payload;
      for (final candidate in pendingPayloads) {
        if (_pendingRecordId(candidate) == record.id) {
          payload = candidate;
          break;
        }
      }
      return ExerciseSessionDetail(
        record: record,
        samples: payload?.samples ?? const <SessionAngleSample>[],
      );
    }

    final response = await _client
        .from('session_angle_samples')
        .select()
        .eq('session_id', record.id)
        .order('sample_index', ascending: true);

    final samples = (response as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(SessionAngleSample.fromMap)
        .toList(growable: false);

    return ExerciseSessionDetail(record: record, samples: samples);
  }

  Future<void> uploadCompletedSession(SessionUploadPayload payload) async {
    try {
      await _uploadDirect(payload);
    } catch (_) {
      await _pendingQueue.add(payload);
      rethrow;
    }
  }

  Future<int> retryPendingUploads() async {
    final pending = await _pendingQueue.load();
    if (pending.isEmpty) {
      return 0;
    }

    final remaining = <SessionUploadPayload>[];
    var uploaded = 0;

    for (final payload in pending) {
      try {
        await _uploadDirect(payload);
        uploaded += 1;
      } catch (_) {
        remaining.add(payload);
      }
    }

    await _pendingQueue.replaceAll(remaining);
    return uploaded;
  }

  Future<void> _uploadDirect(SessionUploadPayload payload) async {
    final insertedSession = await _client
        .from('exercise_sessions')
        .insert(payload.toSessionInsertMap())
        .select()
        .single();

    final sessionId = insertedSession['id'] as String;
    if (payload.samples.isNotEmpty) {
      final rows = payload.samples
          .map((sample) => sample.toInsertMap(sessionId))
          .toList(growable: false);
      await _client.from('session_angle_samples').insert(rows);
    }
  }

  ExerciseSessionRecord _pendingPayloadToRecord(SessionUploadPayload payload) {
    return ExerciseSessionRecord(
      id: _pendingRecordId(payload),
      patientId: payload.patientId,
      startedAt: payload.startedAt,
      endedAt: payload.endedAt,
      exerciseType: payload.exerciseType,
      repCount: payload.repCount,
      peakFlexionDeg: payload.peakFlexionDeg,
      extensionLagDeg: payload.extensionLagDeg,
      durationMs: payload.durationMs,
      sessionStatus: payload.sessionStatus,
      deviceName: payload.deviceName,
      firmwareProtocolVersion: payload.firmwareProtocolVersion,
      syncState: SessionSyncState.pendingUpload,
    );
  }

  String _pendingRecordId(SessionUploadPayload payload) {
    return 'pending-${payload.startedAt.microsecondsSinceEpoch}';
  }
}
