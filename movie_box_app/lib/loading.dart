import 'dart:math' as math;

import 'package:flutter/material.dart';

class MovieBoxLoader extends StatefulWidget {
  final String label;
  final bool compact;

  const MovieBoxLoader({
    super.key,
    this.label = 'Loading',
    this.compact = false,
  });

  @override
  State<MovieBoxLoader> createState() => _MovieBoxLoaderState();
}

class _MovieBoxLoaderState extends State<MovieBoxLoader>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  bool foreground = true;
  bool motionEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    motionEnabled =
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.accessibleNavigationOf(context);
    updateMotion();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    updateMotion();
  }

  void updateMotion() {
    if (motionEnabled && foreground) {
      if (!motion.isAnimating) motion.repeat();
    } else {
      motion.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mark = RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.compact ? 24 : 68,
        child: CustomPaint(
          painter: _MovieLoaderPainter(
            motion,
            Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
    final label = Text(
      widget.label,
      textAlign: widget.compact ? TextAlign.start : TextAlign.center,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w500,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
    return Semantics(
      label: widget.label,
      liveRegion: true,
      child: ExcludeSemantics(
        child: widget.compact
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  mark,
                  const SizedBox(width: 10),
                  Flexible(child: label),
                ],
              )
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [mark, const SizedBox(height: 16), label],
                ),
              ),
      ),
    );
  }
}

class _MovieLoaderPainter extends CustomPainter {
  final Animation<double> motion;
  final Color color;

  _MovieLoaderPainter(this.motion, this.color) : super(repaint: motion);

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.shortestSide / 68;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(unit);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final orbit = Rect.fromCircle(center: Offset.zero, radius: 30);
    canvas.drawOval(orbit, stroke..color = color.withValues(alpha: 0.14));
    final angle = motion.value * math.pi * 2 - math.pi / 2;
    canvas.drawArc(orbit, angle, math.pi * 0.62, false, stroke..color = color);
    canvas.drawArc(
      orbit,
      angle + math.pi,
      math.pi * 0.28,
      false,
      stroke..color = color.withValues(alpha: 0.5),
    );

    final frame = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-19, -14, 38, 28),
      const Radius.circular(5),
    );
    canvas.drawRRect(frame, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawRRect(frame, stroke..color = color);
    for (final y in [-10.0, 10.0]) {
      for (final x in [-12.0, -4.0, 4.0, 12.0]) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(x, y), width: 4, height: 2),
            const Radius.circular(0.7),
          ),
          Paint()..color = color.withValues(alpha: 0.65),
        );
      }
    }
    final play = Path()
      ..moveTo(-3, -5)
      ..lineTo(5, 0)
      ..lineTo(-3, 5)
      ..close();
    canvas.drawPath(play, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MovieLoaderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.motion != motion;
}
