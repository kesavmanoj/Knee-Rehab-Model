class SessionAngleSample {
  const SessionAngleSample({
    required this.sampleIndex,
    required this.elapsedMs,
    required this.finalAngleDeg,
  });

  final int sampleIndex;
  final int elapsedMs;
  final double finalAngleDeg;

  Map<String, dynamic> toInsertMap(String sessionId) {
    return <String, dynamic>{
      'session_id': sessionId,
      'sample_index': sampleIndex,
      'elapsed_ms': elapsedMs,
      'final_angle_deg': finalAngleDeg,
    };
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'sample_index': sampleIndex,
      'elapsed_ms': elapsedMs,
      'final_angle_deg': finalAngleDeg,
    };
  }

  factory SessionAngleSample.fromJson(Map<String, dynamic> map) {
    return SessionAngleSample(
      sampleIndex: (map['sample_index'] as num).toInt(),
      elapsedMs: (map['elapsed_ms'] as num).toInt(),
      finalAngleDeg: (map['final_angle_deg'] as num).toDouble(),
    );
  }

  factory SessionAngleSample.fromMap(Map<String, dynamic> map) {
    return SessionAngleSample(
      sampleIndex: (map['sample_index'] as num).toInt(),
      elapsedMs: (map['elapsed_ms'] as num).toInt(),
      finalAngleDeg: (map['final_angle_deg'] as num).toDouble(),
    );
  }
}
