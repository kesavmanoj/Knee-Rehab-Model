class PatientSummary {
  const PatientSummary({
    required this.id,
    required this.displayName,
    required this.linkedAt,
    required this.createdAt,
  });

  final String id;
  final String displayName;
  final DateTime linkedAt;
  final DateTime createdAt;

  factory PatientSummary.fromJoinedMap(Map<String, dynamic> map) {
    final patient = map['patient'] as Map<String, dynamic>;
    return PatientSummary(
      id: patient['id'] as String,
      displayName: (patient['display_name'] as String?)?.trim().isNotEmpty == true
          ? (patient['display_name'] as String).trim()
          : 'Unnamed patient',
      linkedAt: DateTime.parse(map['linked_at'] as String),
      createdAt: DateTime.parse(patient['created_at'] as String),
    );
  }
}
