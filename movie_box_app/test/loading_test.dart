import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_box_app/loading.dart';

Widget host({
  bool enabled = true,
  bool reduceMotion = false,
  bool accessibleNavigation = false,
  bool compact = false,
  double width = 320,
  double scale = 1,
}) => MaterialApp(
  theme: ThemeData.dark(),
  home: MediaQuery(
    data: MediaQueryData(
      disableAnimations: reduceMotion,
      accessibleNavigation: accessibleNavigation,
      textScaler: TextScaler.linear(scale),
    ),
    child: TickerMode(
      enabled: enabled,
      child: Center(
        child: SizedBox(
          width: width,
          child: MovieBoxLoader(
            label: 'Loading your next movie',
            compact: compact,
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('loader animates and exposes one meaningful status', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.bySemanticsLabel('Loading your next movie'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('hidden page stops its loader and resumes on return', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(host(enabled: false));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    expect(find.text('Loading your next movie'), findsOneWidget);
    await tester.pumpWidget(host());
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final accessible in [false, true]) {
    testWidgets('reduced motion keeps status without ticking ($accessible)', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(reduceMotion: !accessible, accessibleNavigation: accessible),
      );
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      expect(find.text('Loading your next movie'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('background app stops animation and foreground resumes', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(host());
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final compact in [false, true]) {
    testWidgets('loader fits narrow layouts with large text ($compact)', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(compact: compact, width: 180, scale: 1.8, reduceMotion: true),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Loading your next movie'), findsOneWidget);
    });
  }
}
