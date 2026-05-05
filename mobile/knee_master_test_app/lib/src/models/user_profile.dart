import 'app_role.dart';

class UserProfile {
  const UserProfile({
    required this.id,
    required this.role,
    required this.displayName,
    required this.createdAt,
    this.doctorLinkCode,
  });

  final String id;
  final AppRole role;
  final String displayName;
  final DateTime createdAt;
  final String? doctorLinkCode;

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'] as String,
      role: AppRole.fromDatabase(map['role'] as String),
      displayName: (map['display_name'] as String?)?.trim().isNotEmpty == true
          ? (map['display_name'] as String).trim()
          : 'Unnamed user',
      createdAt: DateTime.parse(map['created_at'] as String),
      doctorLinkCode: (map['doctor_link_code'] as String?)?.trim().isNotEmpty == true
          ? (map['doctor_link_code'] as String).trim()
          : null,
    );
  }
}
