import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movie_box_app/api.dart';
import 'package:movie_box_app/library.dart';
import 'package:movie_box_app/screens.dart';
import 'package:shared_preferences/shared_preferences.dart';

MovieApi _api(String server, List<Uri> requests) {
  var calls = 0;
  return MovieApi(
    baseUrl: 'https://$server.example.test',
    client: MockClient((request) async {
      requests.add(request.url);
      expect(request.method, 'GET');
      expect(request.url.path, '/v1/home');
      calls++;
      return http.Response(
        jsonEncode({
          'banners': [],
          'sections': [
            {
              'title': 'Latest releases',
              'items': [
                {
                  'id': '$server-$calls',
                  'detail_path': '$server-$calls',
                  'kind': 'movie',
                  'title': '$server title $calls',
                  'has_resource': true,
                },
              ],
            },
          ],
        }),
        200,
      );
    }),
  );
}

Widget _home(MovieApi api, MovieLibrary library) => MaterialApp(
  home: Scaffold(
    body: HomeScreen(key: const ValueKey('home'), api: api, library: library),
  ),
);

void main() {
  late MovieLibrary library;
  late MovieApi originalApi;
  late List<Uri> originalRequests;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    library = MovieLibrary(await SharedPreferences.getInstance());
    originalRequests = [];
    originalApi = _api('original', originalRequests);
  });

  tearDown(() {
    originalApi.close();
  });

  testWidgets('Home loads and rebuilding with the same API does not reload', (
    tester,
  ) async {
    await tester.pumpWidget(_home(originalApi, library));
    await tester.pumpAndSettle();
    expect(find.text('original title 1'), findsOneWidget);
    expect(originalRequests, hasLength(1));
    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);

    final state = tester.state(find.byType(HomeScreen));
    await tester.pumpWidget(_home(originalApi, library));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(HomeScreen)), same(state));
    expect(originalRequests, hasLength(1));
    expect(find.text('original title 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Home pull-to-refresh completes and replaces the displayed data',
    (tester) async {
      await tester.pumpWidget(_home(originalApi, library));
      await tester.pumpAndSettle();
      expect(find.text('original title 1'), findsOneWidget);
      expect(originalRequests, hasLength(1));

      final refresh = tester.widget<RefreshIndicator>(
        find.byType(RefreshIndicator),
      );
      await expectLater(
        refresh.onRefresh(),
        completes,
        reason: 'Refreshing must not return the setState callback Future assertion.',
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(originalRequests, hasLength(2));
      expect(find.text('original title 2'), findsOneWidget);
      expect(find.text('original title 1'), findsNothing);
    },
  );

  testWidgets(
    'Home switches API instances without throwing and shows the new server data',
    (tester) async {
      final replacementRequests = <Uri>[];
      final replacementApi = _api('replacement', replacementRequests);
      addTearDown(replacementApi.close);

      await tester.pumpWidget(_home(originalApi, library));
      await tester.pumpAndSettle();
      expect(find.text('original title 1'), findsOneWidget);
      final state = tester.state(find.byType(HomeScreen));

      await tester.pumpWidget(_home(replacementApi, library));
      expect(
        tester.takeException(),
        isNull,
        reason: 'didUpdateWidget must reload without returning a Future from setState.',
      );
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(HomeScreen)), same(state));
      expect(originalRequests, hasLength(1));
      expect(replacementRequests, hasLength(1));
      expect(replacementRequests.single.host, 'replacement.example.test');
      expect(find.text('replacement title 1'), findsOneWidget);
      expect(find.text('original title 1'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
