import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:movie_box_app/api.dart';
import 'package:movie_box_app/library.dart';
import 'package:movie_box_app/model.dart';
import 'package:movie_box_app/player.dart';
import 'package:movie_box_app/screens.dart';

void main() {
  test('API sends token, search page and episode parameters', () async {
    final seen = <Uri>[];
    final api = MovieApi(
      baseUrl: 'http://example.test:8000/',
      token: 'secret',
      client: MockClient((request) async {
        seen.add(request.url);
        expect(request.headers['Authorization'], 'Bearer secret');
        return http.Response(
          jsonEncode(
            request.url.path.endsWith('search')
                ? {'items': [], 'page': 2, 'next_page': 3, 'has_more': true}
                : {'streams': [], 'limited': false, 'vip_locked': false},
          ),
          200,
        );
      }),
    );
    expect((await api.search('master & universe', 2)).next, 3);
    await api.playback('sample-title', 1, 3);
    expect(seen.first.queryParameters, {'q': 'master & universe', 'page': '2'});
    expect(seen.last.queryParameters, {'season': '1', 'episode': '3'});
  });

  test('Artwork requests a small CDN thumbnail', () {
    expect(
      artworkUrl('https://pbcdnw.aoneroom.com/image/poster.jpg', 420),
      contains('x-oss-process=image%2Fresize%2Cw_420'),
    );
    expect(
      artworkUrl('https://other.example/poster.jpg', 420),
      'https://other.example/poster.jpg',
    );
  });

  test('SRT subtitles parse timestamps and multiline text', () {
    final captions = SrtCaptions(
      '1\n00:00:01,000 --> 00:00:02,500\nHello\nworld\n\n2\n00:00:03,000 --> 00:00:04,000\nNext',
    );
    expect(captions.captions.length, 2);
    expect(captions.captions.first.text, 'Hello\nworld');
    expect(captions.captions.first.end.inMilliseconds, 2500);
  });

  testWidgets('Catalog loads, paginates and opens details', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final library = MovieLibrary(await SharedPreferences.getInstance());
    final title = {
      'id': '1',
      'detail_path': 'example-title',
      'kind': 'movie',
      'title': 'Example Title',
      'has_resource': true,
    };
    final api = MovieApi(
      baseUrl: 'http://example.test',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/catalog/movies')) {
          final page = int.parse(request.url.queryParameters['page']!);
          return http.Response(
            jsonEncode({
              'items': [
                {
                  ...title,
                  'title': page == 1 ? 'Example Title' : 'Second Page',
                },
              ],
              'page': page,
              'next_page': page == 1 ? 2 : null,
              'has_more': page == 1,
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({'title': title, 'seasons': [], 'dubs': []}),
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CatalogScreen(
            api: api,
            library: library,
            name: 'movies',
            label: 'Movies',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Example Title'), findsOneWidget);
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(find.text('Second Page'), findsOneWidget);
    await tester.tap(find.text('Example Title'));
    await tester.pumpAndSettle();
    expect(find.text('Download video + subtitles'), findsOneWidget);
    expect(find.text('Title details'), findsNothing);
  });

  testWidgets('Search waits for results while typing and replaces the query', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final library = MovieLibrary(await SharedPreferences.getInstance());
    final seen = <String>[];
    final api = MovieApi(
      baseUrl: 'http://example.test',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/popular')) {
          return http.Response('[]', 200);
        }
        final query = request.url.queryParameters['q']!;
        seen.add(query);
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': query,
                'detail_path': 'title-$query',
                'title': '$query result',
                'kind': 'movie',
                'has_resource': true,
              },
            ],
            'page': 1,
            'next_page': null,
            'has_more': false,
          }),
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchScreen(api: api, library: library),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'master');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('No results found.'), findsNothing);
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(find.text('master result'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'universe');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(find.text('universe result'), findsOneWidget);
    expect(find.text('master result'), findsNothing);
    expect(seen, ['master', 'universe']);
  });

  testWidgets(
    'Downloads screen offers offline entries and delete confirmation',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final library = MovieLibrary(await SharedPreferences.getInstance());
      final title = MovieTitle.fromJson({
        'id': '1',
        'detail_path': 'film',
        'kind': 'movie',
        'title': 'Film',
      });
      await library.addDownload(
        SavedDownload(
          title,
          0,
          0,
          '720',
          '/tmp/not-a-real-video.mp4',
          '/tmp/not-a-real-caption.srt',
        ),
      );
      final api = MovieApi(
        baseUrl: 'http://example.test',
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibraryScreen(api: api, library: library),
          ),
        ),
      );
      expect(find.text('Downloads'), findsOneWidget);
      expect(find.text('Film'), findsOneWidget);
      await tester.tap(find.byTooltip('Delete download'));
      await tester.pumpAndSettle();
      expect(find.text('Delete download?'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(library.downloads, isEmpty);
    },
  );

  testWidgets('Continue Watching opens the tapped episode', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final library = MovieLibrary(await SharedPreferences.getInstance());
    final title = MovieTitle.fromJson({
      'id': '1',
      'detail_path': 'series',
      'kind': 'series',
      'title': 'Series',
    });
    await library.record(WatchEntry(title, 1, 1, 60, 600));
    await library.record(WatchEntry(title, 1, 2, 120, 600));
    final api = MovieApi(
      baseUrl: 'http://example.test',
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ContinueRow(
              library.history.values.toList(),
              (entry) =>
                  openTitle(context, api, library, entry.title, resume: entry),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('S1 E1 · 1 min'));
    await tester.pumpAndSettle();
    expect(tester.widget<PlayerScreen>(find.byType(PlayerScreen)).episode, 1);
  });

  test('watch progress and downloads persist locally', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final library = MovieLibrary(prefs);
    final title = MovieTitle.fromJson({
      'id': '1',
      'detail_path': 'film',
      'kind': 'movie',
      'title': 'Film',
    });
    await library.toggleBookmark(title);
    expect(MovieLibrary(prefs).bookmarks['film']?.title, 'Film');
    await library.toggleBookmark(title);
    expect(MovieLibrary(prefs).bookmarks, isEmpty);
    await library.record(WatchEntry(title, 0, 0, 90, 200));
    expect(MovieLibrary(prefs).history['film:0:0']!.positionSeconds, 90);
    await library.record(WatchEntry(title, 0, 0, 199, 200));
    expect(MovieLibrary(prefs).history, isEmpty);
  });
}
