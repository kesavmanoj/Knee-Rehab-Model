import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ble/knee_ble_controller.dart';

class TelemetryGraphCard extends StatelessWidget {
  const TelemetryGraphCard({
    super.key,
    required this.samples,
  });

  final List<TelemetryGraphSample> samples;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Live IMU Graph',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Wrap(
              spacing: 12,
              runSpacing: 8,
              children: <Widget>[
                _LegendChip(label: 'Master', color: Color(0xFF1D4ED8)),
                _LegendChip(label: 'Slave', color: Color(0xFF15803D)),
                _LegendChip(label: 'Knee', color: Color(0xFFDC2626)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 280,
              child: samples.length < 2
                  ? const Center(
                      child: Text(
                        'Waiting for enough telemetry samples to draw the graph.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : CustomPaint(
                      painter: _TelemetryGraphPainter(samples: samples),
                      size: Size.infinite,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}

class _TelemetryGraphPainter extends CustomPainter {
  _TelemetryGraphPainter({
    required this.samples,
  });

  final List<TelemetryGraphSample> samples;

  @override
  void paint(Canvas canvas, Size size) {
    const double leftPad = 40;
    const double topPad = 12;
    const double rightPad = 12;
    const double bottomPad = 28;

    final Rect plotRect = Rect.fromLTWH(
      leftPad,
      topPad,
      math.max(0, size.width - leftPad - rightPad),
      math.max(0, size.height - topPad - bottomPad),
    );

    final Paint borderPaint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final Paint gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawRect(plotRect, borderPaint);

    final TextPainter textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    final List<double> values = <double>[
      for (final sample in samples) sample.masterImuDeg,
      for (final sample in samples) sample.slaveImuDeg,
      for (final sample in samples) sample.imuKneeDeg,
    ];
    final double rawMin = values.reduce(math.min);
    final double rawMax = values.reduce(math.max);
    final double center = (rawMin + rawMax) / 2.0;
    final double halfRange = math.max(10.0, (rawMax - rawMin) / 2.0 + 5.0);
    final double minAngle = center - halfRange;
    final double maxAngle = center + halfRange;

    for (int i = 0; i <= 4; i++) {
      final double ratio = i / 4;
      final double y = plotRect.bottom - (plotRect.height * ratio);
      canvas.drawLine(
        Offset(plotRect.left, y),
        Offset(plotRect.right, y),
        gridPaint,
      );

      final double value = minAngle + ((maxAngle - minAngle) * ratio);
      textPainter.text = TextSpan(
        text: value.toStringAsFixed(0),
        style: const TextStyle(
          color: Color(0xFF475569),
          fontSize: 11,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(plotRect.left - textPainter.width - 6, y - (textPainter.height / 2)),
      );
    }

    final int startMs = samples.first.uptimeMs;
    final int endMs = samples.last.uptimeMs;
    final int spanMs = math.max(1, endMs - startMs);

    Offset pointFor(int uptimeMs, double angleDeg) {
      final double xRatio = (uptimeMs - startMs) / spanMs;
      final double clampedAngle = angleDeg.clamp(minAngle, maxAngle);
      final double yRatio = (clampedAngle - minAngle) / (maxAngle - minAngle);
      return Offset(
        plotRect.left + (plotRect.width * xRatio),
        plotRect.bottom - (plotRect.height * yRatio),
      );
    }

    void drawTrace(Color color, double Function(TelemetryGraphSample sample) valueOf) {
      final Path path = Path();
      for (int i = 0; i < samples.length; i++) {
        final sample = samples[i];
        final Offset point = pointFor(sample.uptimeMs, valueOf(sample));
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }

      final Paint paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, paint);
    }

    drawTrace(const Color(0xFF1D4ED8), (sample) => sample.masterImuDeg);
    drawTrace(const Color(0xFF15803D), (sample) => sample.slaveImuDeg);
    drawTrace(const Color(0xFFDC2626), (sample) => sample.imuKneeDeg);

    final String durationLabel = '${(spanMs / 1000).toStringAsFixed(1)} s window';
    textPainter.text = const TextSpan(
      text: '0',
      style: TextStyle(
        color: Color(0xFF475569),
        fontSize: 11,
      ),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(plotRect.left, plotRect.bottom + 6));

    textPainter.text = TextSpan(
      text: durationLabel,
      style: const TextStyle(
        color: Color(0xFF475569),
        fontSize: 11,
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(plotRect.right - textPainter.width, plotRect.bottom + 6),
    );
  }

  @override
  bool shouldRepaint(covariant _TelemetryGraphPainter oldDelegate) {
    return oldDelegate.samples != samples;
  }
}
