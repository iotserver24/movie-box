import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'library.dart';
import 'screens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final library = MovieLibrary(await SharedPreferences.getInstance());
  runApp(MovieBoxApp(library: library));
  unawaited(library.backfillThumbnails());
}

class MovieBoxApp extends StatefulWidget {
  final MovieLibrary library;
  const MovieBoxApp({super.key, required this.library});
  @override
  State<MovieBoxApp> createState() => _MovieBoxAppState();
}

class _MovieBoxAppState extends State<MovieBoxApp> {
  late MovieApi api = MovieApi(
    baseUrl: widget.library.server,
    token: widget.library.token,
  );
  int tab = 0;

  void updated() {
    api.close();
    setState(
      () => api = MovieApi(
        baseUrl: widget.library.server,
        token: widget.library.token,
      ),
    );
  }

  @override
  void dispose() {
    api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF101519);
    const surface = Color(0xFF1D2529);
    const accent = Color(0xFFF2B86B);
    return MaterialApp(
      title: 'MovieBox',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: const ColorScheme.dark(
          primary: accent,
          secondary: accent,
          surface: surface,
          onSurface: Color(0xFFF0F1ED),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: background,
          elevation: 0,
        ),
        cardTheme: const CardThemeData(color: surface),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final pages = IndexedStack(
            index: tab,
            children: [
              TickerMode(
                enabled: tab == 0,
                child: HomeScreen(api: api, library: widget.library),
              ),
              TickerMode(
                enabled: tab == 1,
                child: BookmarksScreen(api: api, library: widget.library),
              ),
              TickerMode(
                enabled: tab == 2,
                child: SearchScreen(
                  api: api,
                  library: widget.library,
                  active: tab == 2,
                ),
              ),
              TickerMode(
                enabled: tab == 3,
                child: LibraryScreen(api: api, library: widget.library),
              ),
              TickerMode(
                enabled: tab == 4,
                child: SettingsScreen(
                  api: api,
                  library: widget.library,
                  onSaved: updated,
                ),
              ),
            ],
          );
          return Scaffold(
            body: SafeArea(
              child: wide
                  ? Row(
                      children: [
                        NavigationRail(
                          selectedIndex: tab,
                          onDestinationSelected: (index) =>
                              setState(() => tab = index),
                          extended: constraints.maxWidth >= 1200,
                          scrollable: true,
                          labelType: constraints.maxWidth >= 1200
                              ? NavigationRailLabelType.none
                              : NavigationRailLabelType.all,
                          destinations: const [
                            NavigationRailDestination(
                              icon: Icon(Icons.home_outlined),
                              selectedIcon: Icon(Icons.home),
                              label: Text('Home'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.bookmark_border),
                              selectedIcon: Icon(Icons.bookmark),
                              label: Text('Library'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.search),
                              label: Text('Search'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.download_outlined),
                              selectedIcon: Icon(Icons.download),
                              label: Text('Downloads'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.settings_outlined),
                              selectedIcon: Icon(Icons.settings),
                              label: Text('Settings'),
                            ),
                          ],
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(child: pages),
                      ],
                    )
                  : pages,
            ),
            bottomNavigationBar: wide
                ? null
                : NavigationBar(
                    selectedIndex: tab,
                    onDestinationSelected: (index) =>
                        setState(() => tab = index),
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.home_outlined),
                        selectedIcon: Icon(Icons.home),
                        label: 'Home',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.bookmark_border),
                        selectedIcon: Icon(Icons.bookmark),
                        label: 'Library',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.search),
                        label: 'Search',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.download_outlined),
                        selectedIcon: Icon(Icons.download),
                        label: 'Downloads',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.settings_outlined),
                        selectedIcon: Icon(Icons.settings),
                        label: 'Settings',
                      ),
                    ],
                  ),
          );
        },
      ),
      routes: {
        '/settings': (_) => SettingsScreen(
          api: api,
          library: widget.library,
          onSaved: updated,
          standalone: true,
        ),
      },
    );
  }
}
