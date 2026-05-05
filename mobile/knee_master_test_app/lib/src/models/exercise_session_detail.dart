import 'exercise_session_record.dart';
import 'session_angle_sample.dart';

class ExerciseSessionDetail {
  const ExerciseSessionDetail({
    required this.record,
    required this.samples,
  });

  final ExerciseSessionRecord record;
  final List<SessionAngleSample> samples;
}
