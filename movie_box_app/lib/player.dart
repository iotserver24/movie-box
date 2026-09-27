import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

import 'api.dart';
import 'library.dart';
import 'model.dart';

class PlayerScreen extends StatefulWidget {
  final MovieApi api;
  final MovieLibrary library;
  final MovieTitle title;
  final int season, episode;
  final SavedDownload? offline;
  const PlayerScreen({
    super.key,
    required this.api,
    required this.library,
    required this.title,
    required this.season,
    required this.episode,
    this.offline,
  });
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? controller;
  MoviePlayback? playback;
  MovieStream? selected;
  List<MovieCaption> captions = [];
  String captionLabel = 'Off';
  bool loading = true;
  String? error;
  int lastSaved = -1;

  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize() async {
    try {
      if (widget.offline != null && File(widget.offline!.path).existsSync()) {
        await attach(VideoPlayerController.file(File(widget.offline!.path)));
        if (widget.offline!.subtitlePath != null &&
            File(widget.offline!.subtitlePath!).existsSync()) {
          final text = await File(widget.offline!.subtitlePath!).readAsString();
          await controller!.setClosedCaptionFile(
            Future.value(SrtCaptions(text)),
          );
          captionLabel = 'English (offline)';
        }
      } else {
        playback = await widget.api.playback(
          widget.title.path,
          widget.season,
          widget.episode,
        );
        final streams = playback!.streams
            .where((s) => s.format.toUpperCase() == 'MP4' && !s.locked)
            .toList();
        if (streams.isEmpty) {
          throw ApiException('No playable MP4 stream is available.');
        }
        streams.sort(
          (a, b) => (int.tryParse(b.resolution) ?? 0).compareTo(
            int.tryParse(a.resolution) ?? 0,
          ),
        );
        await selectStream(streams.first, resume: false);
      }
      if (mounted) {
        setState(() {
          loading = false;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = '$e';
        });
      }
    }
  }

  Future<void> attach(VideoPlayerController next, {Duration? at}) async {
    final previous = controller;
    await next.initialize();
    if (!mounted) {
      await next.dispose();
      return;
    }
    final position =
        at ??
        Duration(
          seconds:
              widget
                  .library
                  .history[viewingKey(
                    widget.title.path,
                    widget.season,
                    widget.episode,
                  )]
                  ?.positionSeconds ??
              0,
        );
    if (position > Duration.zero &&
        position < next.value.duration - const Duration(seconds: 5)) {
      await next.seekTo(position);
    }
    controller = next;
    next.addListener(onProgress);
    if (previous != null) {
      previous.removeListener(onProgress);
      await previous.dispose();
    }
    await next.play();
    if (mounted) setState(() {});
  }

  Future<void> selectStream(MovieStream stream, {bool resume = true}) async {
    final position = resume ? controller?.value.position : null;
    final next = VideoPlayerController.networkUrl(
      Uri.parse(stream.url),
      httpHeaders: stream.headers,
    );
    await attach(next, at: position);
    selected = stream;
    captions = [];
    captionLabel = 'Off';
    if (mounted) setState(() {});
  }

  void onProgress() {
    final player = controller;
    if (player == null || !player.value.isInitialized || !mounted) return;
    final seconds = player.value.position.inSeconds;
    if (seconds > 0 && (lastSaved < 0 || (seconds - lastSaved).abs() >= 5)) {
      lastSaved = seconds;
      widget.library.record(
        WatchEntry(
          widget.title,
          widget.season,
          widget.episode,
          seconds,
          player.value.duration.inSeconds,
        ),
      );
    }
    setState(() {});
  }

  Future<void> chooseCaption() async {
    final player = controller;
    if (player == null || selected == null) return;
    try {
      if (captions.isEmpty) {
        captions = await widget.api.captions(
          widget.title.path,
          selected!.id,
          widget.season,
          widget.episode,
        );
      }
      if (!mounted) return;
      final choice = await showModalBottomSheet<MovieCaption?>(
        context: context,
        builder: (_) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: const Text('Subtitles'),
                subtitle: const Text('Separate caption track'),
              ),
              ListTile(
                title: const Text('Off'),
                onTap: () => Navigator.pop(context),
              ),
              for (final caption in captions)
                ListTile(
                  title: Text(caption.label),
                  onTap: () => Navigator.pop(context, caption),
                ),
            ],
          ),
        ),
      );
      if (choice == null) {
        await player.setClosedCaptionFile(null);
        captionLabel = 'Off';
      } else {
        final response = await http.get(
          Uri.parse(choice.url),
          headers: choice.headers,
        );
        if (response.statusCode != 200 && response.statusCode != 206) {
          throw ApiException('Subtitles returned HTTP ${response.statusCode}.');
        }
        await player.setClosedCaptionFile(
          Future.value(
            SrtCaptions(utf8.decode(response.bodyBytes, allowMalformed: true)),
          ),
        );
        captionLabel = choice.label;
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> chooseQuality() async {
    final streams =
        playback?.streams
            .where((s) => s.format.toUpperCase() == 'MP4' && !s.locked)
            .toList() ??
        [];
    if (streams.isEmpty) return;
    final choice = await showModalBottomSheet<MovieStream>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Playback quality')),
            for (final stream in streams.reversed)
              ListTile(
                title: Text('${stream.resolution}p'),
                trailing: stream.id == selected?.id
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(context, stream),
              ),
          ],
        ),
      ),
    );
    if (choice == null || choice.id == selected?.id || !mounted) return;
    setState(() => loading = true);
    try {
      await selectStream(choice);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    final player = controller;
    if (player != null) {
      player.removeListener(onProgress);
      final position = player.value.position.inSeconds;
      if (position > 0) {
        widget.library.record(
          WatchEntry(
            widget.title,
            widget.season,
            widget.episode,
            position,
            player.value.duration.inSeconds,
          ),
        );
      }
      player.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = controller;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: loading && player == null
                  ? const CircularProgressIndicator()
                  : error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(error!, textAlign: TextAlign.center),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                loading = true;
                                error = null;
                              });
                              initialize();
                            },
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    )
                  : player == null || !player.value.isInitialized
                  ? const Text('No video available.')
                  : Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        AspectRatio(
                          aspectRatio: player.value.aspectRatio,
                          child: VideoPlayer(player),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                          child: ClosedCaption(
                            text: player.value.caption.text,
                            textStyle: const TextStyle(
                              fontSize: 18,
                              color: Colors.white,
                              backgroundColor: Color(0xC0000000),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          if (player != null && player.value.isInitialized) ...[
            VideoProgressIndicator(
              player,
              allowScrubbing: true,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              colors: const VideoProgressColors(playedColor: Color(0xFFF2B86B)),
            ),
            Row(
              children: [
                IconButton(
                  tooltip: player.value.isPlaying ? 'Pause' : 'Play',
                  icon: Icon(
                    player.value.isPlaying ? Icons.pause : Icons.play_arrow,
                  ),
                  onPressed: () =>
                      player.value.isPlaying ? player.pause() : player.play(),
                ),
                IconButton(
                  tooltip: 'Back 10 seconds',
                  icon: const Icon(Icons.replay_10),
                  onPressed: () => player.seekTo(
                    player.value.position - const Duration(seconds: 10),
                  ),
                ),
                IconButton(
                  tooltip: 'Forward 10 seconds',
                  icon: const Icon(Icons.forward_10),
                  onPressed: () => player.seekTo(
                    player.value.position + const Duration(seconds: 10),
                  ),
                ),
                Expanded(
                  child: Text(
                    '${formatTime(player.value.position)} / ${formatTime(player.value.duration)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                if (widget.offline == null)
                  IconButton(
                    tooltip: 'Subtitles',
                    icon: const Icon(Icons.closed_caption_outlined),
                    onPressed: chooseCaption,
                  ),
                if (widget.offline == null)
                  IconButton(
                    tooltip: 'Quality',
                    icon: const Icon(Icons.high_quality),
                    onPressed: chooseQuality,
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                '${widget.offline == null ? '${selected?.resolution ?? ''}p' : 'Offline · ${widget.offline!.resolution}p'}  ·  Subtitles: $captionLabel',
                style: const TextStyle(color: Color(0xFFBCC8C9)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String formatTime(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

class SrtCaptions extends ClosedCaptionFile {
  @override
  final List<Caption> captions;
  SrtCaptions(String source) : captions = parse(source);

  static List<Caption> parse(String source) {
    final entries = <Caption>[];
    final blocks = source
        .replaceAll('\r\n', '\n')
        .replaceFirst('\uFEFF', '')
        .split(RegExp(r'\n\s*\n'));
    final timing = RegExp(
      r'(\d{2}):(\d{2}):(\d{2})[,\.](\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})[,\.](\d{3})',
    );
    for (final block in blocks) {
      final lines = block.trim().split('\n');
      final index = lines.indexWhere((line) => timing.hasMatch(line));
      if (index < 0 || index + 1 >= lines.length) continue;
      final match = timing.firstMatch(lines[index])!;
      Duration stamp(int start) => Duration(
        hours: int.parse(match[start]!),
        minutes: int.parse(match[start + 1]!),
        seconds: int.parse(match[start + 2]!),
        milliseconds: int.parse(match[start + 3]!),
      );
      entries.add(
        Caption(
          number: entries.length + 1,
          start: stamp(1),
          end: stamp(5),
          text: lines
              .skip(index + 1)
              .join('\n')
              .replaceAll(RegExp(r'<[^>]+>'), ''),
        ),
      );
    }
    return entries;
  }
}
