import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:movie_box_app/api.dart';
import 'package:movie_box_app/download_probe.dart';

class ProbeClient extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  bool closed = false;
  ProbeClient(this.handler);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
  @override
  void close() => closed = true;
}

void main() {
  test('206 validates exact range and byte, preserves required headers and strong ETag', () async {
    final client = ProbeClient((request) async {
      expect(request.method, 'GET');
      expect(request.headers['Range'], 'bytes=0-0');
      expect(request.headers['Accept-Encoding'], 'identity');
      expect(request.headers['Referer'], 'https://origin.test');
      expect(request.headers['Authorization'], 'Bearer fixture');
      expect(request.headers['User-Agent'], 'Required agent');
      return http.StreamedResponse(
        Stream.value([7]),
        206,
        contentLength: 1,
        headers: {'content-range': 'bytes 0-0/8000', 'etag': '"strong"'},
      );
    });
    final metadata = await DownloadMetadataProbe(clientFactory: () => client)
        .probe('https://video.test/file', {
          'Referer': 'https://origin.test',
          'Authorization': 'Bearer fixture',
          'User-Agent': 'Required agent',
          'Range': 'bytes=99-',
          'Accept-Encoding': 'gzip',
        });
    expect(metadata.length, 8000);
    expect(metadata.etag, '"strong"');
    expect(client.closed, isTrue);
  });

  test('200 positive Content-Length closes promptly without listening to movie body', () async {
    var listened = false;
    final body = StreamController<List<int>>(onListen: () => listened = true);
    final client = ProbeClient(
      (_) async => http.StreamedResponse(
        body.stream,
        200,
        contentLength: 9000000,
        headers: {'etag': 'W/"weak"'},
      ),
    );
    final metadata = await DownloadMetadataProbe(clientFactory: () => client)
        .probe('https://video.test/file', {});
    expect(metadata.length, 9000000);
    expect(metadata.etag, isNull);
    expect(listened, isFalse);
    expect(client.closed, isTrue);
    unawaited(body.close());
  });

  for (final code in [401, 403]) {
    test('$code is surfaced for bounded coordinator refresh', () async {
      final client = ProbeClient(
        (_) async => http.StreamedResponse(const Stream.empty(), code),
      );
      await expectLater(
        DownloadMetadataProbe(clientFactory: () => client)
            .probe('https://video.test/file', {}),
        throwsA(
          isA<DownloadProbeHttpException>().having(
            (e) => e.statusCode,
            'code',
            code,
          ),
        ),
      );
      expect(client.closed, isTrue);
    });
  }

  for (final response in [
    http.StreamedResponse(
      Stream.value([1]),
      206,
      headers: {'content-range': 'bytes 1-1/100'},
    ),
    http.StreamedResponse(
      Stream.value([1]),
      206,
      headers: {'content-range': 'bytes 0-0/*'},
    ),
    http.StreamedResponse(
      Stream.value([1, 2]),
      206,
      headers: {'content-range': 'bytes 0-0/100'},
    ),
    http.StreamedResponse(
      const Stream.empty(),
      206,
      headers: {'content-range': 'bytes 0-0/100'},
    ),
    http.StreamedResponse(
      Stream.value([1]),
      206,
      contentLength: 2,
      headers: {'content-range': 'bytes 0-0/100'},
    ),
    http.StreamedResponse(const Stream.empty(), 200),
    http.StreamedResponse(const Stream.empty(), 200, contentLength: 0),
    http.StreamedResponse(
      const Stream.empty(),
      200,
      contentLength: 100,
      headers: {'content-encoding': 'gzip'},
    ),
  ].indexed) {
    test('Invalid or unknown metadata ${response.$1} is rejected', () async {
      final client = ProbeClient((_) async => response.$2);
      await expectLater(
        DownloadMetadataProbe(clientFactory: () => client)
            .probe('https://video.test/file', {}),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'action',
            contains('Choose another quality'),
          ),
        ),
      );
      expect(client.closed, isTrue);
    });
  }

  test('Header timeout closes client and remains retriable', () async {
    final client = ProbeClient(
      (_) => Completer<http.StreamedResponse>().future,
    );
    await expectLater(
      DownloadMetadataProbe(
        clientFactory: () => client,
        timeout: const Duration(milliseconds: 20),
      ).probe('https://video.test/file', {}),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'action',
          contains('Retry'),
        ),
      ),
    );
    expect(client.closed, isTrue);
  });

  test('206 body timeout closes client and remains retriable', () async {
    final body = StreamController<List<int>>();
    final client = ProbeClient(
      (_) async => http.StreamedResponse(
        body.stream,
        206,
        contentLength: 1,
        headers: {'content-range': 'bytes 0-0/100'},
      ),
    );
    await expectLater(
      DownloadMetadataProbe(
        clientFactory: () => client,
        timeout: const Duration(milliseconds: 20),
      ).probe('https://video.test/file', {}),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'action',
          contains('Retry'),
        ),
      ),
    );
    expect(client.closed, isTrue);
    await body.close();
  });
}
