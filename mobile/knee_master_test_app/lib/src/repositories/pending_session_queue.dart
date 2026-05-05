import 'package:shared_preferences/shared_preferences.dart';

import '../models/session_upload_payload.dart';

class PendingSessionQueue {
  static const String _storageKey = 'pending_session_uploads_v1';

  Future<List<SessionUploadPayload>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getStringList(_storageKey) ?? const <String>[];
    return raw.map(SessionUploadPayload.decode).toList(growable: false);
  }

  Future<void> add(SessionUploadPayload payload) async {
    final preferences = await SharedPreferences.getInstance();
    final current = preferences.getStringList(_storageKey) ?? <String>[];
    current.add(payload.encode());
    await preferences.setStringList(_storageKey, current);
  }

  Future<void> replaceAll(List<SessionUploadPayload> payloads) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _storageKey,
      payloads.map((payload) => payload.encode()).toList(growable: false),
    );
  }
}
