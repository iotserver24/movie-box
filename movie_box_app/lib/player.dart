import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  SavedDownload? currentOffline;
  MovieDetail? detail;
  List<MovieCaption> captions = [];
  String captionLabel = 'Off';
  bool loading = true;
  bool fullscreen = false;
  bool controlsVisible = true;
  Timer? controlsTimer;
  Offset? doubleTapPosition;
  String? error;
  int lastSaved = -1;
  int lastRendered = -1;
  late int season = widget.season;
  late int episode = widget.episode;
  final downloadTask = DownloadTask();

  @override
  void initState() {
    super.initState();
    currentOffline = widget.offline;
    if (currentOffline == null) {
      widget.api
          .detail(widget.title.path)
          .then((value) {
            if (mounted) setState(() => detail = value);
          })
          .catchError((_) {});
    }
    initialize();
  }

  Future<void> initialize() async {
    try {
      if (currentOffline != null) {
        if (!await File(currentOffline!.path).exists()) {
          throw ApiException(
            'This download is missing. Delete it from Downloads and download it again.',
          );
        }
        await attach(VideoPlayerController.file(File(currentOffline!.path)));
        final path = currentOffline!.subtitlePath;
        if (path != null && await File(path).exists()) {
          final text = await File(path).readAsString();
          await controller!.setClosedCaptionFile(
            Future.value(SrtCaptions(text)),
          );
          captionLabel = 'Saved subtitles';
        }
      } else {
        playback = await widget.api.playback(
          widget.title.path,
          season,
          episode,
        );
        final streams =
            playback!.streams
                .where((s) => s.format.toUpperCase() == 'MP4' && !s.locked)
                .toList()
              ..sort(
                (a, b) => (int.tryParse(b.resolution) ?? 0).compareTo(
                  int.tryParse(a.resolution) ?? 0,
                ),
              );
        if (streams.isEmpty) {
          throw ApiException('No playable MP4 stream is available.');
        }
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
    try {
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
                    .history[viewingKey(widget.title.path, season, episode)]
                    ?.positionSeconds ??
                0,
          );
      if (position > Duration.zero &&
          position < next.value.duration - const Duration(seconds: 5)) {
        await next.seekTo(position);
      }
      final previous = controller;
      controller = next;
      next.addListener(onProgress);
      if (previous != null) {
        previous.removeListener(onProgress);
        await previous.dispose();
      }
      await next.play();
      revealControls();
      if (mounted) setState(() {});
    } catch (_) {
      await next.dispose();
      rethrow;
    }
  }

  Future<void> selectStream(MovieStream stream, {bool resume = true}) async {
    final position = resume ? controller?.value.position : null;
    await attach(
      VideoPlayerController.networkUrl(
        Uri.parse(stream.url),
        httpHeaders: stream.headers,
      ),
      at: position,
    );
    selected = stream;
    captions = [];
    captionLabel = 'Off';
    if (mounted) setState(() {});
    await loadEnglish(stream);
  }

  Future<void> loadEnglish(MovieStream stream) async {
    try {
      final tracks = await widget.api.captions(
        widget.title.path,
        stream.id,
        season,
        episode,
      );
      if (!mounted || selected != stream) return;
      captions = tracks;
      final english = tracks
          .where((item) => item.language.toLowerCase().startsWith('en'))
          .firstOrNull;
      if (english == null) return;
      final response = await http.get(
        Uri.parse(english.url),
        headers: english.headers,
      );
      if (response.statusCode != 200 && response.statusCode != 206) return;
      if (!mounted || selected != stream || controller == null) return;
      await controller!.setClosedCaptionFile(
        Future.value(
          SrtCaptions(utf8.decode(response.bodyBytes, allowMalformed: true)),
        ),
      );
      if (mounted) setState(() => captionLabel = english.label);
    } catch (_) {}
  }

  void savePosition() {
    final player = controller;
    if (player == null || !player.value.isInitialized) return;
    final position = player.value.position.inSeconds;
    if (position > 0) {
      widget.library.record(
        WatchEntry(
          widget.title,
          season,
          episode,
          position,
          player.value.duration.inSeconds,
        ),
      );
    }
  }

  void onProgress() {
    final player = controller;
    if (player == null || !player.value.isInitialized || !mounted) return;
    final seconds = player.value.position.inSeconds;
    if (seconds > 0 && (lastSaved < 0 || (seconds - lastSaved).abs() >= 5)) {
      lastSaved = seconds;
      savePosition();
    }
    if (seconds != lastRendered) {
      lastRendered = seconds;
      setState(() {});
    }
  }

  Future<void> changeEpisode(int newSeason, int newEpisode) async {
    if (loading ||
        downloadTask.active ||
        (season == newSeason && episode == newEpisode)) {
      return;
    }
    savePosition();
    final previous = controller;
    previous?.removeListener(onProgress);
    controller = null;
    await previous?.dispose();
    if (!mounted) return;
    setState(() {
      season = newSeason;
      episode = newEpisode;
      lastSaved = -1;
      lastRendered = -1;
      selected = null;
      playback = null;
      captions = [];
      captionLabel = 'Off';
      currentOffline = widget
          .library
          .downloads[viewingKey(widget.title.path, season, episode)];
      if (currentOffline != null && !File(currentOffline!.path).existsSync()) {
        currentOffline = null;
      }
      loading = true;
      error = null;
    });
    await initialize();
  }

  Future<void> chooseCaption() async {
    final player = controller;
    if (player == null || selected == null) return;
    try {
      if (captions.isEmpty) {
        captions = await widget.api.captions(
          widget.title.path,
          selected!.id,
          season,
          episode,
        );
      }
      if (!mounted) return;
      final choice = await showModalBottomSheet<Object>(
        context: context,
        builder: (_) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('Subtitles')),
              ListTile(
                title: const Text('Off'),
                onTap: () => Navigator.pop(context, false),
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
      if (choice == null || !mounted) return;
      if (choice == false) {
        await player.setClosedCaptionFile(null);
        captionLabel = 'Off';
      } else {
        final caption = choice as MovieCaption;
        final response = await http.get(
          Uri.parse(caption.url),
          headers: caption.headers,
        );
        if (response.statusCode != 200 && response.statusCode != 206) {
          throw ApiException('Subtitles returned HTTP ${response.statusCode}.');
        }
        await player.setClosedCaptionFile(
          Future.value(
            SrtCaptions(utf8.decode(response.bodyBytes, allowMalformed: true)),
          ),
        );
        captionLabel = caption.label;
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
      final fresh = await widget.api.playback(
        widget.title.path,
        season,
        episode,
      );
      playback = fresh;
      final stream = fresh.streams.firstWhere(
        (s) => s.format == choice.format && s.resolution == choice.resolution,
      );
      await selectStream(stream);
      if (mounted) setState(() => error = null);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> downloadCurrent() async {
    if (currentOffline != null || downloadTask.active) return;
    try {
      final fresh = await widget.api.playback(
        widget.title.path,
        season,
        episode,
      );
      if (!mounted) return;
      final streams = fresh.streams
          .where((s) => s.format.toUpperCase() == 'MP4' && !s.locked)
          .toList();
      if (streams.isEmpty) {
        throw ApiException('No downloadable MP4 stream is available.');
      }
      final stream = await showModalBottomSheet<MovieStream>(
        context: context,
        builder: (_) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('Download quality')),
              for (final item in streams.reversed)
                ListTile(
                  title: Text('${item.resolution}p'),
                  subtitle: Text(
                    item.size == null
                        ? 'MP4'
                        : '${(item.size! / 1048576).round()} MB · MP4',
                  ),
                  onTap: () => Navigator.pop(context, item),
                ),
            ],
          ),
        ),
      );
      if (stream == null || !mounted) return;
      List<MovieCaption> available;
      try {
        available = await widget.api.captions(
          widget.title.path,
          stream.id,
          season,
          episode,
        );
      } catch (_) {
        available = [];
      }
      if (!mounted) return;
      final option = await showModalBottomSheet<Object>(
        context: context,
        builder: (_) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('Save subtitles with the video')),
              ListTile(
                title: const Text('Video only'),
                onTap: () => Navigator.pop(context, false),
              ),
              for (final caption in available)
                ListTile(
                  title: Text(caption.label),
                  onTap: () => Navigator.pop(context, caption),
                ),
            ],
          ),
        ),
      );
      if (option == null || !mounted) return;
      final saved = await downloadTask.start(
        widget.api,
        widget.library,
        widget.title,
        season,
        episode,
        stream,
        option == false ? null : option as MovieCaption,
      );
      if (saved != null && mounted) {
        final position = controller?.value.position;
        var switched = false;
        try {
          await attach(
            VideoPlayerController.file(File(saved.path)),
            at: position,
          );
          if (saved.subtitlePath != null) {
            final text = await File(saved.subtitlePath!).readAsString();
            await controller!.setClosedCaptionFile(
              Future.value(SrtCaptions(text)),
            );
          }
          switched = true;
          if (mounted) {
            setState(() {
              currentOffline = saved;
              selected = null;
              captionLabel = saved.subtitlePath == null
                  ? 'Off'
                  : 'Saved subtitles';
            });
          }
        } catch (_) {}
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                !switched
                    ? 'Saved. Open it from Downloads to play offline.'
                    : saved.subtitlePath == null
                    ? 'Video saved for offline viewing.'
                    : 'Video and subtitles saved for offline viewing.',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  void revealControls() {
    controlsTimer?.cancel();
    if (mounted) setState(() => controlsVisible = true);
    controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && controller?.value.isPlaying == true) {
        setState(() => controlsVisible = false);
      }
    });
  }

  void toggleControls() {
    if (controlsVisible) {
      controlsTimer?.cancel();
      setState(() => controlsVisible = false);
    } else {
      revealControls();
    }
  }

  void togglePlayback() {
    final player = controller;
    if (player == null) return;
    player.value.isPlaying ? player.pause() : player.play();
    revealControls();
  }

  void seekBy(int seconds) {
    final player = controller;
    if (player == null || !player.value.isInitialized) return;
    final target = player.value.position + Duration(seconds: seconds);
    player.seekTo(
      target < Duration.zero
          ? Duration.zero
          : target > player.value.duration
          ? player.value.duration
          : target,
    );
    revealControls();
  }

  Future<void> toggleFullscreen() async {
    if (fullscreen) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    if (mounted) setState(() => fullscreen = !fullscreen);
    revealControls();
  }

  Widget videoSurface(VideoPlayerController? player) => Container(
    color: Colors.black,
    width: double.infinity,
    child: AspectRatio(
      aspectRatio: fullscreen ? MediaQuery.sizeOf(context).aspectRatio : 16 / 9,
      child: error != null && player == null
          ? Center(
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
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              alignment: Alignment.center,
              children: [
                Center(
                  child: AspectRatio(
                    aspectRatio: player.value.aspectRatio,
                    child: VideoPlayer(player),
                  ),
                ),
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: toggleControls,
                    onDoubleTapDown: (details) =>
                        doubleTapPosition = details.localPosition,
                    onDoubleTap: () {
                      final x = doubleTapPosition?.dx ?? 0;
                      final width = MediaQuery.sizeOf(context).width;
                      if (x < width / 2) {
                        seekBy(-10);
                      } else {
                        seekBy(10);
                      }
                    },
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: controlsVisible ? 54 : 10,
                  child: ClosedCaption(
                    text: player.value.caption.text,
                    textStyle: const TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                      backgroundColor: Color(0xC0000000),
                    ),
                  ),
                ),
                if (controlsVisible) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Back 10 seconds',
                        icon: const Icon(Icons.replay_10),
                        onPressed: () => seekBy(-10),
                      ),
                      const SizedBox(width: 22),
                      IconButton(
                        tooltip: player.value.isPlaying ? 'Pause' : 'Play',
                        iconSize: 48,
                        icon: Icon(
                          player.value.isPlaying
                              ? Icons.pause_circle
                              : Icons.play_circle,
                        ),
                        onPressed: togglePlayback,
                      ),
                      const SizedBox(width: 22),
                      IconButton(
                        tooltip: 'Forward 10 seconds',
                        icon: const Icon(Icons.forward_10),
                        onPressed: () => seekBy(10),
                      ),
                    ],
                  ),
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 0,
                    child: Row(
                      children: [
                        Text(
                          formatTime(player.value.position),
                          style: const TextStyle(fontSize: 12),
                        ),
                        Expanded(
                          child: VideoProgressIndicator(
                            player,
                            allowScrubbing: true,
                            padding: const EdgeInsets.all(8),
                            colors: const VideoProgressColors(
                              playedColor: Color(0xFFF2B86B),
                            ),
                          ),
                        ),
                        Text(
                          formatTime(player.value.duration),
                          style: const TextStyle(fontSize: 12),
                        ),
                        IconButton(
                          tooltip: fullscreen
                              ? 'Exit fullscreen'
                              : 'Fullscreen',
                          icon: Icon(
                            fullscreen
                                ? Icons.fullscreen_exit
                                : Icons.fullscreen,
                          ),
                          onPressed: toggleFullscreen,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    ),
  );

  @override
  void dispose() {
    controlsTimer?.cancel();
    if (fullscreen) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    savePosition();
    controller?.removeListener(onProgress);
    controller?.dispose();
    downloadTask.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = controller;
    final info = detail?.title ?? widget.title;
    final seasons = detail?.seasons ?? [];
    final savedEpisodes = widget.library.downloads.values
        .where(
          (item) => item.title.path == widget.title.path && item.season > 0,
        )
        .toList();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): togglePlayback,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => seekBy(-10),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => seekBy(10),
        const SingleActivator(LogicalKeyboardKey.keyF): () {
          toggleFullscreen();
        },
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (fullscreen) toggleFullscreen();
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: fullscreen
              ? null
              : AppBar(
                  title: Text(
                    info.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
          body: fullscreen
              ? videoSurface(player)
              : SafeArea(
                  top: false,
                  child: ListView(
                    children: [
                      videoSurface(player),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed:
                                    currentOffline != null ||
                                        downloadTask.active
                                    ? null
                                    : downloadCurrent,
                                icon: const Icon(Icons.download_outlined),
                                label: Text(
                                  currentOffline != null
                                      ? 'Downloaded'
                                      : 'Download video + subtitles',
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip:
                                  widget.library.bookmarks.containsKey(
                                    widget.title.path,
                                  )
                                  ? 'Remove bookmark'
                                  : 'Bookmark',
                              icon: Icon(
                                widget.library.bookmarks.containsKey(
                                      widget.title.path,
                                    )
                                    ? Icons.bookmark
                                    : Icons.bookmark_border,
                              ),
                              onPressed: () async {
                                await widget.library.toggleBookmark(
                                  detail?.title ?? widget.title,
                                );
                                if (mounted) setState(() {});
                              },
                            ),
                          ],
                        ),
                      ),
                      AnimatedBuilder(
                        animation: downloadTask,
                        builder: (_, _) => downloadTask.active
                            ? Padding(
                                padding: const EdgeInsets.all(18),
                                child: Column(
                                  children: [
                                    LinearProgressIndicator(
                                      value: downloadTask.total == null
                                          ? null
                                          : downloadTask.received /
                                                downloadTask.total!,
                                    ),
                                    Text(
                                      downloadTask.total == null
                                          ? '${(downloadTask.received / 1048576).toStringAsFixed(1)} MB'
                                          : '${(downloadTask.received / 1048576).toStringAsFixed(1)} / ${(downloadTask.total! / 1048576).toStringAsFixed(1)} MB',
                                    ),
                                    TextButton(
                                      onPressed: downloadTask.cancel,
                                      child: const Text('Pause download'),
                                    ),
                                  ],
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      if (currentOffline == null &&
                          player != null &&
                          player.value.isInitialized)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed: chooseQuality,
                                icon: const Icon(Icons.high_quality),
                                label: Text(
                                  'Quality ${selected?.resolution ?? ''}p',
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: chooseCaption,
                                icon: const Icon(Icons.closed_caption_outlined),
                                label: Text(captionLabel),
                              ),
                            ],
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
                        child: Text(
                          info.title,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Text(
                          '${currentOffline == null ? '${selected?.resolution ?? ''}p' : 'Offline · ${currentOffline!.resolution}p'}  ·  Subtitles: $captionLabel',
                          style: const TextStyle(color: Color(0xFFBCC8C9)),
                        ),
                      ),
                      if (season > 0)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 4, 18, 2),
                          child: Text(
                            'Season $season · Episode $episode',
                            style: const TextStyle(color: Color(0xFFF2B86B)),
                          ),
                        ),
                      if (info.description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
                          child: Text(info.description),
                        ),
                      if (seasons.isNotEmpty || savedEpisodes.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 20, 18, 8),
                          child: Text(
                            'Episodes',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        if (seasons.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            child: DropdownButton<int>(
                              value:
                                  seasons.any((item) => item.number == season)
                                  ? season
                                  : seasons.first.number,
                              items: [
                                for (final item in seasons)
                                  DropdownMenuItem(
                                    value: item.number,
                                    child: Text('Season ${item.number}'),
                                  ),
                              ],
                              onChanged: (value) {
                                if (value != null) changeEpisode(value, 1);
                              },
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (seasons.isNotEmpty)
                                for (
                                  var i = 1;
                                  i <=
                                      seasons
                                          .firstWhere(
                                            (item) =>
                                                item.number ==
                                                (seasons.any(
                                                      (s) => s.number == season,
                                                    )
                                                    ? season
                                                    : seasons.first.number),
                                          )
                                          .episodes;
                                  i++
                                )
                                  ChoiceChip(
                                    label: Text('$i'),
                                    selected: episode == i,
                                    onSelected: (_) => changeEpisode(season, i),
                                  )
                              else
                                for (final item in savedEpisodes)
                                  ChoiceChip(
                                    label: Text(
                                      'S${item.season} E${item.episode}',
                                    ),
                                    selected:
                                        season == item.season &&
                                        episode == item.episode,
                                    onSelected: (_) => changeEpisode(
                                      item.season,
                                      item.episode,
                                    ),
                                  ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                    ],
                  ),
                ),
        ),
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
