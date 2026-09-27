import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'model.dart';

class MovieLibrary extends ChangeNotifier {
  final SharedPreferences prefs;
  late String server = prefs.getString('server') ?? 'http://10.0.2.2:8000';
  late String token = prefs.getString('token') ?? '';
  late final Map<String, WatchEntry> history = {
    for (final item in jsonDecode(prefs.getString('history') ?? '[]') as List)
      (WatchEntry.fromJson(item as Map<String, dynamic>))
          .key: WatchEntry.fromJson(
        item,
      ),
  };
  late final Map<String, SavedDownload> downloads = {
    for (final item in jsonDecode(prefs.getString('downloads') ?? '[]') as List)
      (SavedDownload.fromJson(item as Map<String, dynamic>))
          .key: SavedDownload.fromJson(
        item,
      ),
  };

  MovieLibrary(this.prefs);

  Future<void> configure(String address, String apiToken) async {
    server = address.replaceAll(RegExp(r'/$'), '');
    token = apiToken;
    await prefs.setString('server', server);
    await prefs.setString('token', token);
    notifyListeners();
  }

  Future<void> record(WatchEntry entry) async {
    if (entry.positionSeconds <= 0) return;
    if (entry.durationSeconds > 0 &&
        entry.positionSeconds >= entry.durationSeconds - 20) {
      history.remove(entry.key);
    } else {
      history.remove(entry.key);
      history[entry.key] = entry;
    }
    await prefs.setString(
      'history',
      jsonEncode(history.values.map((e) => e.toJson()).toList()),
    );
    notifyListeners();
  }

  Future<void> addDownload(SavedDownload entry) async {
    downloads[entry.key] = entry;
    await _saveDownloads();
  }

  Future<void> removeDownload(SavedDownload entry) async {
    downloads.remove(entry.key);
    await _saveDownloads();
    final file = File(entry.path);
    if (await file.exists()) await file.delete();
    if (entry.subtitlePath != null) {
      final subtitle = File(entry.subtitlePath!);
      if (await subtitle.exists()) await subtitle.delete();
    }
  }

  Future<void> _saveDownloads() async {
    await prefs.setString(
      'downloads',
      jsonEncode(downloads.values.map((e) => e.toJson()).toList()),
    );
    notifyListeners();
  }
}

class DownloadTask extends ChangeNotifier {
  bool active = false;
  bool cancelled = false;
  int received = 0;
  int? total;
  String? error;
  void cancel() => cancelled = true;

  Future<SavedDownload?> start(
    MovieApi api,
    MovieLibrary library,
    MovieTitle title,
    int season,
    int episode,
    MovieStream stream,
    MovieCaption? caption,
  ) async {
    if (active) return null;
    active = true;
    cancelled = false;
    error = null;
    notifyListeners();
    final directory = await getApplicationDocumentsDirectory();
    final file = File(
      '${directory.path}/${title.path}-$season-$episode-${stream.resolution}.mp4.part',
    );
    final completed = File(file.path.substring(0, file.path.length - 5));
    final downloadClient = http.Client();
    try {
      var candidate = stream;
      for (var attempt = 0; attempt < 2; attempt++) {
        final offset = await file.exists() ? await file.length() : 0;
        final request = http.Request('GET', Uri.parse(candidate.url));
        request.headers.addAll(candidate.headers);
        if (offset > 0) request.headers['Range'] = 'bytes=$offset-';
        final response = await downloadClient.send(request);
        if (response.statusCode == 403 || response.statusCode == 401) {
          await response.stream.drain();
          if (attempt == 0) {
            final refreshed = await api.playback(title.path, season, episode);
            candidate = refreshed.streams.firstWhere(
              (s) =>
                  s.format == stream.format &&
                  s.resolution == stream.resolution,
            );
            continue;
          }
        }
        if (response.statusCode != 200 && response.statusCode != 206) {
          await response.stream.drain();
          throw ApiException('Download returned HTTP ${response.statusCode}.');
        }
        if (offset > 0 && response.statusCode == 200) {
          await file.writeAsBytes([]);
        }
        received = response.statusCode == 206 ? offset : 0;
        final length = response.contentLength;
        total = length == null ? null : received + length;
        final sink = file.openWrite(mode: FileMode.append);
        try {
          await for (final chunk in response.stream) {
            if (cancelled) break;
            sink.add(chunk);
            received += chunk.length;
            notifyListeners();
          }
        } finally {
          await sink.flush();
          await sink.close();
        }
        if (cancelled) return null;
        if (total != null && received != total) {
          throw ApiException('Download ended early. Retry to resume it.');
        }
        if (await completed.exists()) await completed.delete();
        await file.rename(completed.path);
        String? subtitlePath;
        if (caption != null) {
          try {
            final result = await http.get(
              Uri.parse(caption.url),
              headers: caption.headers,
            );
            if (result.statusCode == 200 || result.statusCode == 206) {
              final subtitle = File('${completed.path}.srt');
              await subtitle.writeAsBytes(result.bodyBytes);
              subtitlePath = subtitle.path;
            }
          } catch (_) {}
        }
        final saved = SavedDownload(
          title,
          season,
          episode,
          stream.resolution,
          completed.path,
          subtitlePath,
        );
        await library.addDownload(saved);
        return saved;
      }
      throw ApiException('The download link expired. Try again.');
    } catch (e) {
      error = '$e';
      notifyListeners();
      rethrow;
    } finally {
      downloadClient.close();
      active = false;
      notifyListeners();
    }
  }
}
