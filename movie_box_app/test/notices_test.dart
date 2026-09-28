import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:movie_box_app/api.dart';
import 'package:movie_box_app/library.dart';
import 'package:movie_box_app/notices.dart';
import 'package:movie_box_app/screens.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final listScrollable = find
      .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
      .first;

  test('bundled notices exactly match the canonical source files', () async {
    for (final name in ['LICENSE', 'CREDITS.md']) {
      final bundled = await rootBundle.loadString('assets/notices/$name');
      expect(bundled, await File('../$name').readAsString());
    }
  });

  testWidgets('Settings opens credits without contacting the server', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final library = MovieLibrary(await SharedPreferences.getInstance());
    final api = MovieApi(
      baseUrl: 'https://example.test',
      client: MockClient((_) async {
        fail('Credits must not make an API request');
      }),
    );
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          api: api,
          library: library,
          onSaved: () {},
          standalone: true,
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Credits and licenses'),
      200,
      scrollable: listScrollable,
    );
    await tester.tap(find.text('Credits and licenses'));
    await tester.pumpAndSettle();
    expect(find.byType(CreditsScreen), findsOneWidget);
    expect(find.text('Movie Box by R3AP3R Editz'), findsOneWidget);
    expect(find.text(projectUrl), findsOneWidget);
  });

  testWidgets('full project license is readable offline', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CreditsScreen()));
    final license = await tester.runAsync(() async {
      await tester.tap(find.text('Movie Box license'));
      await tester.pump();
      await rootBundle.loadString('assets/notices/LICENSE');
      return File('../LICENSE').readAsString();
    });
    await tester.pumpAndSettle();
    final text = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(text.data, license);
    expect(text.data, contains('No advertising'));
    expect(text.data, contains('No selling or charging for access'));
  });

  testWidgets('dependency notices use the Flutter license registry', (
    tester,
  ) async {
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks(['notice-test-package'], 'Test notice.');
    });
    await tester.pumpWidget(const MaterialApp(home: CreditsScreen()));
    await tester.scrollUntilVisible(
      find.text('Dependency licenses'),
      150,
      scrollable: listScrollable,
    );
    await tester.tap(find.text('Dependency licenses'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.text('notice-test-package'), findsOneWidget);
  });

  testWidgets('donation link is optional and copied without opening a site', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    await tester.pumpWidget(const MaterialApp(home: CreditsScreen()));
    await tester.scrollUntilVisible(
      find.text('Copy donation link'),
      200,
      scrollable: listScrollable,
    );
    expect(
      find.textContaining('do not unlock features or access'),
      findsOneWidget,
    );
    await tester.tap(find.text('Copy donation link'));
    await tester.pump();
    expect(copied, donationUrl);
    expect(find.text('Donation link copied.'), findsOneWidget);
  });

  testWidgets('missing notice produces a visible distribution warning', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: BundledNoticeScreen(
          title: 'Missing notice',
          asset: 'missing.txt',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Get a complete build'), findsOneWidget);
  });
}
