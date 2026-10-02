import 'dart:async';

import 'package:http/http.dart' as http;

import 'api.dart';

class DownloadMetadata {
  final int length;
  final String? etag;
  const DownloadMetadata(this.length, {this.etag});

  Map<String, dynamic> toJson() => {'length': length, 'etag': etag};
  factory DownloadMetadata.fromJson(Map<String, dynamic> json) =>
      DownloadMetadata(json['length'] as int, etag: json['etag'] as String?);
}

class DownloadProbeHttpException extends ApiException {
  final int statusCode;
  DownloadProbeHttpException(this.statusCode)
    : super('Download metadata returned HTTP $statusCode. Retry to try again.');
}

Map<String, String> downloadRequestHeaders(Map<String, String> supplied) {
  final headers = <String, String>{
    for (final entry in supplied.entries)
      if (!const {
        'range',
        'if-range',
        'if-match',
        'known-content-length',
        'accept-encoding',
      }.contains(entry.key.toLowerCase()))
        entry.key: entry.value,
  };
  if (!headers.keys.any((key) => key.toLowerCase() == 'user-agent')) {
    headers['User-Agent'] = 'Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 Chrome/120.0 Mobile Safari/537.36';
  }
  headers['Accept-Encoding'] = 'identity';
  return headers;
}

/// Each probe owns its client so a full response can be closed without draining it.
class DownloadMetadataProbe {
  final http.Client Function() clientFactory;
  final Duration timeout;
  DownloadMetadataProbe({
    http.Client Function()? clientFactory,
    this.timeout = const Duration(seconds: 12),
  }) : clientFactory = clientFactory ?? http.Client.new;

  Future<DownloadMetadata> probe(
    String url,
    Map<String, String> headers,
  ) async {
    final client = clientFactory();
    try {
      return await _probe(client, url, headers).timeout(timeout);
    } on TimeoutException {
      throw ApiException('Download metadata timed out. Retry to try again.');
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(
        'Could not verify the download size. Retry to try again.',
      );
    } finally {
      client.close();
    }
  }

  Future<DownloadMetadata> _probe(
    http.Client client,
    String url,
    Map<String, String> headers,
  ) async {
    final request = http.Request('GET', Uri.parse(url))
      ..headers.addAll(downloadRequestHeaders(headers))
      ..headers['Range'] = 'bytes=0-0';
    final response = await client.send(request);
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw DownloadProbeHttpException(response.statusCode);
    }
    final encoding = response.headers['content-encoding']?.toLowerCase();
    if (encoding != null && encoding != 'identity') {
      throw ApiException(
        'The server cannot provide an exact download size. Choose another quality.',
      );
    }
    int? length;
    if (response.statusCode == 206) {
      final match = RegExp(r'^bytes 0-0/([1-9][0-9]*)$')
          .firstMatch(response.headers['content-range']?.trim() ?? '');
      if (match == null ||
          (response.contentLength != null && response.contentLength != 1)) {
        throw ApiException(
          'The server returned an invalid download range. Choose another quality.',
        );
      }
      length = int.tryParse(match.group(1)!);
      var received = 0;
      await for (final chunk in response.stream.timeout(timeout)) {
        received += chunk.length;
        if (received > 1) break;
      }
      if (received != 1) {
        throw ApiException(
          'The server returned an invalid download range. Choose another quality.',
        );
      }
    } else {
      length = response.contentLength;
      // Never consume an ignored Range request's full movie body.
    }
    if (length == null || length <= 0) {
      throw ApiException(
        'This quality has no verifiable download size. Choose another quality.',
      );
    }
    final rawEtag = response.headers['etag']?.trim();
    final strongEtag =
        rawEtag != null && RegExp(r'^"[^"\r\n]*"$').hasMatch(rawEtag)
        ? rawEtag
        : null;
    return DownloadMetadata(length, etag: strongEtag);
  }
}
