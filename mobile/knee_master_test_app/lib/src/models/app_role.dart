enum AppRole {
  patient,
  doctor;

  factory AppRole.fromDatabase(String value) {
    switch (value) {
      case 'patient':
        return AppRole.patient;
      case 'doctor':
        return AppRole.doctor;
      default:
        throw FormatException('Unsupported role: $value');
    }
  }

  String get dbValue => switch (this) {
        AppRole.patient => 'patient',
        AppRole.doctor => 'doctor',
      };
}
