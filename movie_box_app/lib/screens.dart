import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'library.dart';
import 'model.dart';
import 'player.dart';

void showError(BuildContext context, Object error) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
}

void openTitle(
  BuildContext context,
  MovieApi api,
  MovieLibrary library,
  MovieTitle title, {
  WatchEntry? resume,
}) {
  if (title.path.isEmpty) return;
  final matches = library.history.values.where(
    (entry) => entry.title.path == title.path,
  );
  final last = resume ?? (matches.isEmpty ? null : matches.last);
  final season = last?.season ?? (title.kind == 'movie' ? 0 : 1);
  final episode = last?.episode ?? (title.kind == 'movie' ? 0 : 1);
  final saved = library.downloads[viewingKey(title.path, season, episode)];
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => PlayerScreen(
        api: api,
        library: library,
        title: title,
        season: season,
        episode: episode,
        offline: saved != null && File(saved.path).existsSync() ? saved : null,
      ),
    ),
  );
}

String artworkUrl(String source, int width) {
  final uri = Uri.tryParse(source);
  if (uri == null || uri.host != 'pbcdnw.aoneroom.com') return source;
  return uri
      .replace(
        queryParameters: {
          ...uri.queryParameters,
          'x-oss-process': 'image/resize,w_$width',
        },
      )
      .toString();
}

class Artwork extends StatelessWidget {
  final String? url;
  final int width;
  const Artwork({super.key, this.url, this.width = 420});

  @override
  Widget build(BuildContext context) => url == null || url!.isEmpty
      ? const ColoredBox(
          color: Color(0xFF273238),
          child: Icon(Icons.movie, size: 40),
        )
      : CachedNetworkImage(
          imageUrl: artworkUrl(url!, width),
          fit: BoxFit.cover,
          memCacheWidth: width,
          maxWidthDiskCache: width,
          fadeInDuration: const Duration(milliseconds: 120),
          placeholder: (_, _) => const ColoredBox(
            color: Color(0xFF273238),
            child: Center(child: Icon(Icons.movie_outlined, size: 32)),
          ),
          errorWidget: (_, _, _) => const ColoredBox(
            color: Color(0xFF273238),
            child: Icon(Icons.movie, size: 40),
          ),
        );
}

class Poster extends StatelessWidget {
  final MovieTitle title;
  final VoidCallback onTap;
  const Poster({super.key, required this.title, required this.onTap});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 130,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: Artwork(url: title.poster),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            title.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    ),
  );
}

class TitleGrid extends StatelessWidget {
  final List<MovieTitle> items;
  final void Function(MovieTitle) onTap;
  const TitleGrid({super.key, required this.items, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final columns = (MediaQuery.sizeOf(context).width / 155).floor().clamp(
      2,
      6,
    );
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      sliver: SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 12,
          mainAxisSpacing: 16,
          childAspectRatio: 0.51,
        ),
        itemCount: items.length,
        itemBuilder: (_, index) =>
            Poster(title: items[index], onTap: () => onTap(items[index])),
      ),
    );
  }
}

class ScreenHeader extends StatelessWidget {
  final String title;
  const ScreenHeader(this.title, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 17, 12, 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(
          tooltip: 'Settings',
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => Navigator.pushNamed(context, '/settings'),
        ),
      ],
    ),
  );
}

class HomeScreen extends StatefulWidget {
  final MovieApi api;
  final MovieLibrary library;
  const HomeScreen({super.key, required this.api, required this.library});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<MovieHome> data = widget.api.home();
  @override
  void initState() {
    super.initState();
    widget.library.addListener(refreshHistory);
  }

  @override
  void dispose() {
    widget.library.removeListener(refreshHistory);
    super.dispose();
  }

  void refreshHistory() {
    if (mounted) setState(() {});
  }

  void reload() => setState(() => data = widget.api.home());
  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api) reload();
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: () async {
      reload();
      await data;
    },
    child: FutureBuilder<MovieHome>(
      future: data,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return ListView(
            children: [
              const ScreenHeader('MovieBox'),
              SizedBox(
                height: 400,
                child: Center(
                  child: snapshot.hasError
                      ? ErrorPanel(error: snapshot.error!, retry: reload)
                      : const CircularProgressIndicator(),
                ),
              ),
            ],
          );
        }
        final home = snapshot.data!;
        final history = widget.library.history.values
            .toList()
            .reversed
            .toList();
        return ListView(
          children: [
            const ScreenHeader('MovieBox'),
            PopularCarousel(
              titles: home.sections
                  .where(
                    (section) =>
                        section.title.toLowerCase().contains('popular'),
                  )
                  .expand((section) => section.items)
                  .take(6)
                  .toList(),
              fallback: home.banners,
              onTap: (title) =>
                  openTitle(context, widget.api, widget.library, title),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final category in [
                    ('movies', 'Movies'),
                    ('series', 'Series'),
                    ('animation', 'Anime'),
                  ])
                    ActionChip(
                      label: Text(category.$2),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => Scaffold(
                            appBar: AppBar(title: Text(category.$2)),
                            body: CatalogScreen(
                              api: widget.api,
                              library: widget.library,
                              name: category.$1,
                              label: category.$2,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (history.isNotEmpty)
              ContinueRow(
                history,
                (entry) => openTitle(
                  context,
                  widget.api,
                  widget.library,
                  entry.title,
                  resume: entry,
                ),
              ),
            for (final section in home.sections)
              if (section.items.isNotEmpty)
                MovieRow(
                  section.title,
                  section.items,
                  (title) =>
                      openTitle(context, widget.api, widget.library, title),
                ),
          ],
        );
      },
    ),
  );
}

class PopularCarousel extends StatefulWidget {
  final List<MovieTitle> titles, fallback;
  final void Function(MovieTitle) onTap;
  const PopularCarousel({
    super.key,
    required this.titles,
    required this.fallback,
    required this.onTap,
  });
  @override
  State<PopularCarousel> createState() => _PopularCarouselState();
}

class _PopularCarouselState extends State<PopularCarousel> {
  int index = 0;
  @override
  Widget build(BuildContext context) {
    final titles = widget.titles.isEmpty ? widget.fallback : widget.titles;
    if (titles.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        SizedBox(
          height: 265,
          child: PageView.builder(
            itemCount: titles.length,
            onPageChanged: (value) => setState(() => index = value),
            itemBuilder: (context, page) {
              final title = titles[page];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: InkWell(
                  onTap: () => widget.onTap(title),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Stack(
                      alignment: Alignment.bottomLeft,
                      children: [
                        SizedBox.expand(
                          child: Artwork(
                            url: title.backdrop ?? title.poster,
                            width: 900,
                          ),
                        ),
                        Container(
                          height: 150,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Color(0xEE101519)],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'POPULAR NOW',
                                style: TextStyle(
                                  color: Color(0xFFF2B86B),
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2,
                                ),
                              ),
                              Text(
                                title.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 25,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Text('Watch now  ›'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < titles.length; i++)
                Container(
                  width: i == index ? 18 : 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: i == index
                        ? const Color(0xFFF2B86B)
                        : Colors.white38,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class ContinueRow extends StatelessWidget {
  final List<WatchEntry> entries;
  final void Function(WatchEntry) onTap;
  const ContinueRow(this.entries, this.onTap, {super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(18, 14, 18, 12),
        child: Text(
          'Continue Watching',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
      SizedBox(
        height: 260,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          itemCount: entries.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, index) {
            final entry = entries[index];
            final progress = entry.durationSeconds <= 0
                ? 0.0
                : (entry.positionSeconds / entry.durationSeconds).clamp(
                    0.0,
                    1.0,
                  );
            return SizedBox(
              width: 155,
              child: InkWell(
                onTap: () => onTap(entry),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        height: 175,
                        width: 155,
                        child: Artwork(url: entry.title.poster),
                      ),
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor: const Color(0xFF343D41),
                      color: const Color(0xFFDF4B47),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      entry.title.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      entry.season > 0
                          ? 'S${entry.season} E${entry.episode} · ${entry.positionSeconds ~/ 60} min'
                          : '${entry.positionSeconds ~/ 60} min watched',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFBCC8C9),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ],
  );
}

class MovieRow extends StatelessWidget {
  final String heading;
  final List<MovieTitle> titles;
  final void Function(MovieTitle) onTap;
  const MovieRow(this.heading, this.titles, this.onTap, {super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
        child: Text(
          heading,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
      SizedBox(
        height: 245,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          itemCount: titles.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, index) =>
              Poster(title: titles[index], onTap: () => onTap(titles[index])),
        ),
      ),
    ],
  );
}

class ErrorPanel extends StatelessWidget {
  final Object error;
  final VoidCallback retry;
  const ErrorPanel({super.key, required this.error, required this.retry});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.wifi_off, size: 42),
        const SizedBox(height: 12),
        Text('$error', textAlign: TextAlign.center),
        TextButton(onPressed: retry, child: const Text('Try again')),
        TextButton(
          onPressed: () => Navigator.pushNamed(context, '/settings'),
          child: const Text('Server settings'),
        ),
      ],
    ),
  );
}

class CatalogScreen extends StatefulWidget {
  final MovieApi api;
  final MovieLibrary library;
  final String name, label;
  const CatalogScreen({
    super.key,
    required this.api,
    required this.library,
    required this.name,
    required this.label,
  });
  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final items = <MovieTitle>[];
  int? next = 1;
  bool loading = false;
  Object? error;
  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  @override
  void didUpdateWidget(covariant CatalogScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api) {
      items.clear();
      next = 1;
      load();
    }
  }

  Future<void> load() async {
    if (loading || next == null) return;
    final page = next!;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.api.catalog(widget.name, page);
      if (!mounted) return;
      setState(() {
        items.addAll(result.items);
        next = result.next;
      });
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: () async {
      setState(() {
        items.clear();
        next = 1;
      });
      await load();
    },
    child: CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: ScreenHeader(widget.label)),
        if (items.isNotEmpty)
          TitleGrid(
            items: items,
            onTap: (title) =>
                openTitle(context, widget.api, widget.library, title),
          ),
        if (items.isEmpty && error == null && !loading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('No titles found.')),
            ),
          ),
        if (error != null)
          SliverToBoxAdapter(
            child: SizedBox(
              height: items.isEmpty ? 320 : 100,
              child: ErrorPanel(error: error!, retry: load),
            ),
          ),
        if (loading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        if (!loading && next != null && error == null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton(
                onPressed: load,
                child: const Text('Load more'),
              ),
            ),
          ),
      ],
    ),
  );
}

class SearchScreen extends StatefulWidget {
  final MovieApi api;
  final MovieLibrary library;
  const SearchScreen({super.key, required this.api, required this.library});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final text = TextEditingController();
  final items = <MovieTitle>[];
  List<String> hints = [];
  int? next;
  bool loading = false;
  bool hasSearched = false;
  Object? error;
  Timer? debounce;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    widget.api
        .popular()
        .then((value) {
          if (mounted && text.text.isEmpty) setState(() => hints = value);
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    debounce?.cancel();
    text.dispose();
    super.dispose();
  }

  void changed(String query) {
    debounce?.cancel();
    generation++;
    final serial = generation;
    setState(() {
      items.clear();
      next = null;
      loading = false;
      hasSearched = false;
      error = null;
      hints = [];
    });
    if (query.trim().isEmpty) {
      widget.api
          .popular()
          .then((value) {
            if (mounted && serial == generation) setState(() => hints = value);
          })
          .catchError((_) {});
      return;
    }
    debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted || serial != generation) return;
      setState(() => next = 1);
      load();
    });
  }

  Future<void> submit([String? term]) async {
    if (term != null) {
      text.text = term;
      text.selection = TextSelection.collapsed(offset: term.length);
    }
    final query = text.text.trim();
    if (query.isEmpty) return;
    debounce?.cancel();
    generation++;
    setState(() {
      items.clear();
      hints = [];
      next = 1;
      loading = false;
      hasSearched = false;
      error = null;
    });
    FocusScope.of(context).unfocus();
    await load();
  }

  Future<void> load() async {
    if (loading || next == null) return;
    final page = next!;
    final serial = generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.api.search(text.text.trim(), page);
      if (!mounted || serial != generation) return;
      setState(() {
        items.addAll(result.items);
        next = result.next;
        hasSearched = true;
      });
    } catch (e) {
      if (mounted && serial == generation) setState(() => error = e);
    } finally {
      if (mounted && serial == generation) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      SliverToBoxAdapter(
        child: Column(
          children: [
            const ScreenHeader('Search'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: text,
                textInputAction: TextInputAction.search,
                onChanged: changed,
                onSubmitted: (_) => submit(),
                decoration: InputDecoration(
                  hintText: 'Find a movie or series',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: 'Search',
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: submit,
                  ),
                ),
              ),
            ),
            if (hints.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 20, 18, 4),
                child: Text(
                  'POPULAR SEARCHES',
                  style: TextStyle(
                    color: Color(0xFFF2B86B),
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              for (final hint in hints.take(10))
                ListTile(
                  title: Text(hint),
                  trailing: const Icon(Icons.north_west, size: 18),
                  onTap: () => submit(hint),
                ),
            ],
          ],
        ),
      ),
      if (items.isNotEmpty)
        TitleGrid(
          items: items,
          onTap: (title) =>
              openTitle(context, widget.api, widget.library, title),
        ),
      if (hasSearched &&
          !loading &&
          error == null &&
          text.text.isNotEmpty &&
          items.isEmpty)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(30),
            child: Center(child: Text('No results found.')),
          ),
        ),
      if (error != null)
        SliverToBoxAdapter(
          child: SizedBox(
            height: 250,
            child: ErrorPanel(error: error!, retry: load),
          ),
        ),
      if (loading)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      if (!loading && next != null && error == null)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton(
              onPressed: load,
              child: const Text('Load more'),
            ),
          ),
        ),
    ],
  );
}

class DetailScreen extends StatefulWidget {
  final MovieApi api;
  final MovieLibrary library;
  final String path;
  const DetailScreen({
    super.key,
    required this.api,
    required this.library,
    required this.path,
  });
  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late Future<MovieDetail> future = widget.api.detail(widget.path);
  int season = 0, episode = 0;
  bool busy = false;
  final task = DownloadTask();
  @override
  void dispose() {
    task.dispose();
    super.dispose();
  }

  Future<void> play(MovieTitle title, {SavedDownload? offline}) async {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => PlayerScreen(
              api: widget.api,
              library: widget.library,
              title: title,
              season: season,
              episode: episode,
              offline: offline,
            ),
          ),
        )
        .then((_) {
          if (mounted) setState(() {});
        });
  }

  Future<void> download(MovieTitle title) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final playback = await widget.api.playback(title.path, season, episode);
      if (!mounted) return;
      final choices = playback.streams
          .where((s) => s.format.toUpperCase() == 'MP4' && !s.locked)
          .toList();
      if (choices.isEmpty) {
        throw ApiException('No downloadable MP4 stream is available.');
      }
      final selected = await showModalBottomSheet<MovieStream>(
        context: context,
        builder: (_) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('Download quality')),
              for (final stream in choices.reversed)
                ListTile(
                  title: Text('${stream.resolution}p'),
                  subtitle: Text(
                    stream.size == null
                        ? 'MP4'
                        : '${(stream.size! / 1048576).round()} MB · MP4',
                  ),
                  onTap: () => Navigator.pop(context, stream),
                ),
            ],
          ),
        ),
      );
      if (selected == null || !mounted) return;
      MovieCaption? caption;
      try {
        final options = await widget.api.captions(
          title.path,
          selected.id,
          season,
          episode,
        );
        for (final option in options) {
          if (option.language.toLowerCase().startsWith('en')) {
            caption = option;
            break;
          }
        }
      } catch (_) {}
      final saved = await task.start(
        widget.api,
        widget.library,
        title,
        season,
        episode,
        selected,
        caption,
      );
      if (mounted && saved != null) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved for offline viewing.')),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Title details')),
    body: FutureBuilder<MovieDetail>(
      future: future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(
            child: snapshot.hasError
                ? ErrorPanel(
                    error: snapshot.error!,
                    retry: () =>
                        setState(() => future = widget.api.detail(widget.path)),
                  )
                : const CircularProgressIndicator(),
          );
        }
        final detail = snapshot.data!;
        final title = detail.title;
        final watch =
            widget.library.history[viewingKey(title.path, season, episode)];
        final saved =
            widget.library.downloads[viewingKey(title.path, season, episode)];
        return ListView(
          children: [
            SizedBox(
              height: 230,
              child: Artwork(url: title.backdrop ?? title.poster, width: 1080),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.title,
                    style: const TextStyle(
                      fontSize: 29,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    [
                      title.kind.toUpperCase(),
                      if (title.rating != null) 'IMDb ${title.rating}',
                      ...title.genres.take(3),
                    ].join('  ·  '),
                    style: const TextStyle(color: Color(0xFFBCC8C9)),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    title.description.isEmpty
                        ? 'No synopsis available.'
                        : title.description,
                  ),
                  if (detail.seasons.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text(
                      'Episodes',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButton<int>(
                      value: detail.seasons.any((s) => s.number == season)
                          ? season
                          : detail.seasons.first.number,
                      items: [
                        for (final s in detail.seasons)
                          DropdownMenuItem(
                            value: s.number,
                            child: Text('Season ${s.number}'),
                          ),
                      ],
                      onChanged: (value) => setState(() {
                        season = value!;
                        episode = 1;
                      }),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (
                          var i = 1;
                          i <=
                              detail.seasons
                                  .firstWhere(
                                    (s) =>
                                        s.number ==
                                        (detail.seasons.any(
                                              (s) => s.number == season,
                                            )
                                            ? season
                                            : detail.seasons.first.number),
                                  )
                                  .episodes;
                          i++
                        )
                          ChoiceChip(
                            label: Text('$i'),
                            selected: episode == i,
                            onSelected: (_) => setState(() {
                              episode = i;
                              if (season == 0) {
                                season = detail.seasons.first.number;
                              }
                            }),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed:
                          title.available &&
                              (detail.seasons.isEmpty || episode > 0)
                          ? () => play(
                              title,
                              offline:
                                  saved != null && File(saved.path).existsSync()
                                  ? saved
                                  : null,
                            )
                          : null,
                      icon: const Icon(Icons.play_arrow),
                      label: Text(
                        watch == null
                            ? 'Play'
                            : 'Continue at ${Duration(seconds: watch.positionSeconds).inMinutes} min',
                      ),
                    ),
                  ),
                  if (detail.seasons.isNotEmpty && episode == 0)
                    const Text('Choose an episode to play or download.'),
                  const SizedBox(height: 7),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed:
                          busy ||
                              !title.available ||
                              (detail.seasons.isNotEmpty && episode == 0)
                          ? null
                          : () => download(title),
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Download MP4'),
                    ),
                  ),
                  if (saved != null && File(saved.path).existsSync())
                    TextButton.icon(
                      onPressed: () => play(title, offline: saved),
                      icon: const Icon(Icons.offline_pin),
                      label: Text('Play downloaded ${saved.resolution}p'),
                    ),
                  AnimatedBuilder(
                    animation: task,
                    builder: (_, _) => task.active
                        ? Column(
                            children: [
                              LinearProgressIndicator(
                                value: task.total == null
                                    ? null
                                    : task.received / task.total!,
                              ),
                              Text(
                                task.total == null
                                    ? '${(task.received / 1048576).toStringAsFixed(1)} MB'
                                    : '${(task.received / 1048576).toStringAsFixed(1)} / ${(task.total! / 1048576).toStringAsFixed(1)} MB',
                              ),
                              TextButton(
                                onPressed: task.cancel,
                                child: const Text('Pause download'),
                              ),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                  if (detail.dubs.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    const Text(
                      'Other audio versions',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    for (final dub in detail.dubs)
                      ListTile(
                        title: Text(dub.title),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () =>
                            openTitle(context, widget.api, widget.library, dub),
                      ),
                  ],
                ],
              ),
            ),
            FutureBuilder<MoviePage>(
              future: widget.api.recommendations(widget.path),
              builder: (_, result) =>
                  result.hasData && result.data!.items.isNotEmpty
                  ? MovieRow(
                      'You might also like',
                      result.data!.items,
                      (item) =>
                          openTitle(context, widget.api, widget.library, item),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        );
      },
    ),
  );
}

class LibraryScreen extends StatefulWidget {
  final MovieApi api;
  final MovieLibrary library;
  const LibraryScreen({super.key, required this.api, required this.library});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  @override
  void initState() {
    super.initState();
    widget.library.addListener(refresh);
  }

  @override
  void dispose() {
    widget.library.removeListener(refresh);
    super.dispose();
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final downloads = widget.library.downloads.values
        .toList()
        .reversed
        .toList();
    final history = widget.library.history.values.toList().reversed.toList();
    return ListView(
      children: [
        const ScreenHeader('Downloads'),
        const Padding(
          padding: EdgeInsets.fromLTRB(18, 8, 18, 4),
          child: Text(
            'Saved on this device',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        if (downloads.isEmpty)
          const ListTile(
            title: Text('No downloads yet.'),
            subtitle: Text('Saved videos stay on this device.'),
          ),
        for (final entry in downloads)
          ListTile(
            leading: const Icon(Icons.offline_pin_outlined),
            title: Text(entry.title.title),
            subtitle: Text(
              '${entry.resolution}p${entry.season > 0 ? ' · S${entry.season} E${entry.episode}' : ''} · ${entry.subtitlePath != null && File(entry.subtitlePath!).existsSync() ? 'Subtitles saved' : 'No subtitles'}',
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PlayerScreen(
                  api: widget.api,
                  library: widget.library,
                  title: entry.title,
                  season: entry.season,
                  episode: entry.episode,
                  offline: entry,
                ),
              ),
            ),
            trailing: IconButton(
              tooltip: 'Delete download',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final yes = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Delete download?'),
                    content: Text(entry.title.title),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (yes == true) await widget.library.removeDownload(entry);
              },
            ),
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(18, 24, 18, 4),
          child: Text(
            'Continue Watching',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        if (history.isEmpty)
          const ListTile(
            title: Text('Nothing in progress yet.'),
            subtitle: Text('Your place is saved as you watch.'),
          ),
        for (final entry in history)
          ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: Text(entry.title.title),
            subtitle: Text(
              '${entry.season > 0 ? 'S${entry.season} E${entry.episode} · ' : ''}${Duration(seconds: entry.positionSeconds).inMinutes} min watched',
            ),
            onTap: () {
              final saved = widget.library.downloads[entry.key];
              if (saved != null && File(saved.path).existsSync()) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PlayerScreen(
                      api: widget.api,
                      library: widget.library,
                      title: entry.title,
                      season: entry.season,
                      episode: entry.episode,
                      offline: saved,
                    ),
                  ),
                );
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PlayerScreen(
                      api: widget.api,
                      library: widget.library,
                      title: entry.title,
                      season: entry.season,
                      episode: entry.episode,
                    ),
                  ),
                );
              }
            },
          ),
      ],
    );
  }
}

class BookmarksScreen extends StatefulWidget {
  final MovieApi api;
  final MovieLibrary library;
  const BookmarksScreen({super.key, required this.api, required this.library});
  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  @override
  void initState() {
    super.initState();
    widget.library.addListener(refresh);
  }

  @override
  void dispose() {
    widget.library.removeListener(refresh);
    super.dispose();
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final titles = widget.library.bookmarks.values.toList().reversed.toList();
    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: ScreenHeader('Library')),
        if (titles.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No bookmarks yet. Save titles from the watch page to find them here.',
              ),
            ),
          ),
        if (titles.isNotEmpty)
          TitleGrid(
            items: titles,
            onTap: (title) =>
                openTitle(context, widget.api, widget.library, title),
          ),
      ],
    );
  }
}

class SettingsScreen extends StatefulWidget {
  final MovieApi api;
  final MovieLibrary library;
  final VoidCallback onSaved;
  final bool standalone;
  const SettingsScreen({
    super.key,
    required this.api,
    required this.library,
    required this.onSaved,
    this.standalone = false,
  });
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final address = TextEditingController(text: widget.library.server);
  late final token = TextEditingController(text: widget.library.token);
  bool testing = false;
  @override
  void dispose() {
    address.dispose();
    token.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final raw = address.text.trim();
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      showError(context, 'Enter a full http:// or https:// server address.');
      return;
    }
    setState(() => testing = true);
    final candidate = MovieApi(baseUrl: raw, token: token.text.trim());
    try {
      await candidate.ping();
      await widget.library.configure(raw, token.text.trim());
      widget.onSaved();
      if (mounted) {
        if (widget.standalone) {
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Server connection saved.')),
          );
        }
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      candidate.close();
      if (mounted) setState(() => testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = ListView(
      padding: const EdgeInsets.all(18),
      children: [
        if (!widget.standalone)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              'Settings',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
          ),
        const Text(
          'Connect to your scraper',
          style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text(
          'The default server is the hosted MovieBox API. You can enter another HTTPS API URL here, or 10.0.2.2 for a locally running Android emulator.',
        ),
        const SizedBox(height: 22),
        TextField(
          controller: address,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'API address',
            hintText: 'https://movie-box.n92dev.us.kg',
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: token,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'API token (if configured)',
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: testing ? null : save,
          child: Text(testing ? 'Checking connection…' : 'Connect and save'),
        ),
        const SizedBox(height: 10),
        const Text(
          'Use this app and server only on a trusted network or private VPN.',
        ),
      ],
    );
    return widget.standalone
        ? Scaffold(
            appBar: AppBar(title: const Text('Server settings')),
            body: content,
          )
        : content;
  }
}
