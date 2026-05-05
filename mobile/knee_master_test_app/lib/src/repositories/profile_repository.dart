import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_profile.dart';

class ProfileRepository {
  ProfileRepository(this._client);

  final SupabaseClient _client;

  Future<List<UserProfile>> listLinkedDoctors(String patientId) async {
    final response = await _client
        .from('doctor_patient_links')
        .select('linked_at, doctor:profiles!doctor_patient_links_doctor_id_fkey(id, role, display_name, created_at, doctor_link_code)')
        .eq('patient_id', patientId)
        .order('linked_at', ascending: false);

    return (response as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((row) => UserProfile.fromMap(Map<String, dynamic>.from(row['doctor'] as Map)))
        .toList(growable: false);
  }

  Future<UserProfile> linkPatientToDoctorCode(String code) async {
    final response = await _client.rpc(
      'link_patient_to_doctor',
      params: <String, dynamic>{'input_code': code},
    );
    return UserProfile.fromMap(Map<String, dynamic>.from(response as Map));
  }
}
