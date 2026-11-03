import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'model.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class MovieApi {
  String baseUrl;
  String token;
  String region;
  final http.Client client;
  MovieApi({
    required this.baseUrl,
    this.token = '',
    this.region = 'US',
    http.Client? client,
  }) : client = client ?? http.Client();

  Uri url(String path, [Map<String, String>? params]) {
    final query = <String, String>{
      if (region.isNotEmpty) 'region': region,
      if (region.isNotEmpty) 'lang': 'en',
      ...?params,
    };
    return Uri.parse('${baseUrl.replaceAll(RegExp(r'/$'), '')}$path')
        .replace(queryParameters: query.isEmpty ? null : query);
  }

  Future<dynamic> get(String path, [Map<String, String>? params]) async {
    http.Response response;
    try {
      response = await client
          .get(
            url(path, params),
            headers: {
              if (token.isNotEmpty) 'Authorization': 'Bearer $token',
              'Accept-Language': 'en-US,en;q=0.9',
              if (region.isNotEmpty) 'X-Region': region,
            },
          )
          .timeout(const Duration(seconds: 15));
    } catch (e, st) {
      debugPrint('MovieApi GET $path failed: $e\n$st');
      throw ApiException(
        'Cannot connect to the scraper ($e). Check its address in Settings.',
      );
    }
    if (response.statusCode != 200) {
      String? detail;
      try {
        detail = jsonDecode(response.body)['detail']?.toString();
      } catch (_) {}
      throw ApiException(detail ?? 'Server returned ${response.statusCode}.');
    }
    try {
      return jsonDecode(response.body);
    } catch (_) {
      throw ApiException('Server returned invalid data.');
    }
  }

  Future<void> ping() async => await get('/health');
  Future<MovieHome> home() async => MovieHome.fromJson(await get('/v1/home'));
  Future<MovieHome> collection(String name) async =>
      MovieHome.fromJson(await get('/v1/collections/$name'));
  Future<MoviePage> catalog(String name, int page) async {
    final canonical = name.toLowerCase().trim();
    if (canonical == 'movies' || canonical == 'series' || canonical == 'animation' || canonical == 'anime' || canonical == 'kids') {
      try {
        return MoviePage.fromJson(
          await get('/v1/catalog/$canonical', {'page': '$page'}),
        );
      } catch (e, st) {
        debugPrint('Catalog $canonical request failed: $e\n$st');
        rethrow;
      }
    }
    return search(name, page);
  }
  Future<MoviePage> search(String query, int page) async => MoviePage.fromJson(
    await get('/v1/search', {'q': query, 'page': '$page'}),
  );
  Future<List<String>> suggestions(String query) async =>
      (await get('/v1/search/suggestions', {'q': query}) as List)
          .cast<String>();
  Future<List<String>> popular() async =>
      (await get('/v1/search/popular') as List).cast<String>();
  Future<MovieDetail> detail(String path) async => MovieDetail.fromJson(
    await get('/v1/titles/${Uri.encodeComponent(path)}'),
  );
  Future<MoviePage> recommendations(String path) async => MoviePage.fromJson(
    await get('/v1/titles/${Uri.encodeComponent(path)}/recommendations'),
  );
  Future<MoviePlayback> playback(String path, int season, int episode) async =>
      MoviePlayback.fromJson(
        await get('/v1/titles/${Uri.encodeComponent(path)}/playback', {
          'season': '$season',
          'episode': '$episode',
        }),
      );
  Future<List<MovieCaption>> captions(
    String path,
    String streamId,
    int season,
    int episode,
  ) async =>
      (await get('/v1/titles/${Uri.encodeComponent(path)}/captions', {
            'stream_id': streamId,
            'season': '$season',
            'episode': '$episode',
          }) as List)
          .map((e) => MovieCaption.fromJson(e as Map<String, dynamic>))
          .toList();

  void close() => client.close();
}
