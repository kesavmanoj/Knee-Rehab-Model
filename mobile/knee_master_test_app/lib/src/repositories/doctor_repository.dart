import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/patient_summary.dart';

class DoctorRepository {
  DoctorRepository(this._client);

  final SupabaseClient _client;

  Future<List<PatientSummary>> listAssignedPatients(String doctorId) async {
    final response = await _client
        .from('doctor_patient_links')
        .select('linked_at, patient:profiles!doctor_patient_links_patient_id_fkey(id, display_name, created_at)')
        .eq('doctor_id', doctorId)
        .order('linked_at', ascending: false);

    return (response as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(PatientSummary.fromJoinedMap)
        .toList(growable: false);
  }
}
