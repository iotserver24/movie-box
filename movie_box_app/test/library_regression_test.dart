import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_box_app/api.dart';
import 'package:movie_box_app/library.dart';
import 'package:movie_box_app/model.dart';
import 'package:movie_box_app/screens.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _LocalHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  late MovieLibrary library;
  final title = MovieTitle.fromJson({
    'id': 'qa',
    'detail_path': 'qa-series',
    'kind': 'series',
    'title': 'QA series',
    'has_resource': true,
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('moviebox-library-test-');
    SharedPreferences.setMockInitialValues({});
    library = MovieLibrary(await SharedPreferences.getInstance());
    messenger.setMockMethodCallHandler(mediaChannel, (_) async => null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => directory.path,
    );
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(mediaChannel, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    library.dispose();
    await directory.delete(recursive: true);
  });

  test('Thumbnail platform failures leave downloads usable', () async {
    messenger.setMockMethodCallHandler(
      mediaChannel,
      (_) async => throw PlatformException(code: 'THUMBNAIL_FAILED'),
    );
    expect(await extractThumbnail('/missing.mp4'), isNull);
    messenger.setMockMethodCallHandler(mediaChannel, null);
    expect(await extractThumbnail('/missing.mp4'), isNull);
  });

  test('Backfill creates and persists a missing thumbnail once', () async {
    final video = await File('${directory.path}/video.mp4')
        .writeAsBytes([1, 2, 3]);
    final preview = File('${video.path}.preview.jpg');
    var calls = 0;
    messenger.setMockMethodCallHandler(mediaChannel, (call) async {
      expect(call.method, 'thumbnail');
      expect(call.arguments, video.path);
      calls++;
      await preview.writeAsBytes([4, 5]);
      return preview.path;
    });
    await library.addDownload(
      SavedDownload(title, 1, 1, '360', video.path, null),
    );
    await library.backfillThumbnails();
    expect(library.downloads.values.single.thumbnailPath, preview.path);
    expect(
      MovieLibrary(library.prefs).downloads.values.single.thumbnailPath,
      preview.path,
    );
    await library.backfillThumbnails();
    expect(calls, 1);
  });

  test('Backfill skips missing videos', () async {
    var called = false;
    messenger.setMockMethodCallHandler(mediaChannel, (_) async {
      called = true;
      return null;
    });
    await library.addDownload(
      SavedDownload(title, 1, 1, '360', '${directory.path}/missing.mp4', null),
    );
    await library.backfillThumbnails();
    expect(called, isFalse);
    expect(library.downloads, hasLength(1));
  });

  test(
    'Deleting a download removes its video, subtitles, and thumbnail',
    () async {
      final video = await File('${directory.path}/video.mp4').writeAsBytes([1]);
      final captions = await File('${video.path}.srt').writeAsString('caption');
      final preview = await File('${video.path}.preview.jpg').writeAsBytes([2]);
      final saved = SavedDownload(
        title,
        1,
        2,
        '360',
        video.path,
        captions.path,
        thumbnailPath: preview.path,
      );
      await library.addDownload(saved);
      await library.removeDownload(saved);
      expect(await video.exists(), isFalse);
      expect(await captions.exists(), isFalse);
      expect(await preview.exists(), isFalse);
      expect(MovieLibrary(library.prefs).downloads, isEmpty);
    },
  );

  test(
    'Backfill cannot resurrect a download deleted during extraction',
    () async {
      final video = await File('${directory.path}/video.mp4').writeAsBytes([1]);
      final saved = SavedDownload(title, 1, 1, '360', video.path, null);
      await library.addDownload(saved);
      final started = Completer<void>();
      final extracted = Completer<String>();
      messenger.setMockMethodCallHandler(mediaChannel, (_) {
        started.complete();
        return extracted.future;
      });
      final pending = library.backfillThumbnails();
      await started.future;
      await library.removeDownload(saved);
      extracted.complete('${video.path}.preview.jpg');
      await pending;
      expect(library.downloads, isEmpty);
    },
  );

  test('Continue Watching groups each series and survives restart', () async {
    await library.record(WatchEntry(title, 1, 1, 30, 300));
    await library.record(WatchEntry(title, 1, 2, 40, 300));
    await library.record(WatchEntry(title, 1, 1, 50, 300));
    final restored = MovieLibrary(library.prefs);
    final latest = latestWatchEntries(restored.history.values);
    expect(latest, hasLength(1));
    expect(latest.single.episode, 1);
    expect(latest.single.positionSeconds, 50);
    expect(restored.history, hasLength(2));
  });

  for (final supportsRange in [true, false]) {
    test(
      'Download resume handles ${supportsRange ? '206 partial content' : '200 full response'} without duplicate bytes',
      () async {
        final bytes = List<int>.generate(1024, (i) => i % 256);
        final partial = await File(
          '${directory.path}/${title.path}-1-1-360.mp4.part',
        ).writeAsBytes(bytes.take(200).toList());
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final ranges = <String?>[];
        server.listen((request) async {
          ranges.add(request.headers.value('range'));
          final body = supportsRange ? bytes.sublist(200) : bytes;
          request.response.statusCode = supportsRange ? 206 : 200;
          request.response.contentLength = body.length;
          if (supportsRange) {
            request.response.headers.set(
              'Content-Range',
              'bytes 200-1023/1024',
            );
          }
          request.response.add(body);
          await request.response.close();
        });
        final api = MovieApi(baseUrl: 'http://127.0.0.1:${server.port}');
        addTearDown(api.close);
        final stream = MovieStream.fromJson({
          'id': '360',
          'format': 'MP4',
          'resolutions': '360',
          'url': 'http://127.0.0.1:${server.port}/video',
        });
        final task = DownloadTask();
        addTearDown(task.dispose);
        final saved = await HttpOverrides.runWithHttpOverrides(
          () => task.start(api, library, title, 1, 1, stream, null),
          _LocalHttpOverrides(),
        );
        expect(saved, isNotNull);
        expect(await File(saved!.path).readAsBytes(), bytes);
        expect(await partial.exists(), isFalse);
        expect(ranges, ['bytes=200-']);
        expect(task.active, isFalse);
        expect(library.downloads, hasLength(1));
      },
    );
  }
}
