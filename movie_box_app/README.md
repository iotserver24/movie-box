# MovieBox Android app

Flutter client for the scraper API in `../scraper`. The app does not scrape MovieBox directly and contains no ads or account requirement.

## Run

Start the scraper from the parent directory:

```sh
docker compose up -d --build
```

Then run on an Android emulator or device:

```sh
cd movie_box_app
flutter pub get
flutter run
```

The default API address is `https://movie-box.n92dev.us.kg`. Settings can override it for another deployment, including `http://10.0.2.2:8000` for a locally running scraper on the standard Android emulator. If the server requires `SCRAPER_API_TOKEN`, enter the token in Settings. Keep any local HTTP deployment on a trusted network or private VPN; use HTTPS for a public hostname.

## Features

- Five bottom tabs: Home, Downloads, Search, Library (bookmarked titles), and Settings. Home includes a popular carousel, catalogs, cached artwork, and Continue Watching cards with episode, watched time, and a red progress bar. Search returns results as you type.
- Tapping a title opens the watch page and starts playback directly, resuming its most recently watched episode and position. The video sits above download, quality, subtitle, title, and episode controls. English subtitles are selected automatically when available; fullscreen controls hide during playback. Tap to show controls, double-tap the left or right side to seek ten seconds, or use Space, Left/Right arrows, F, and Escape with a keyboard.
- Download quality and subtitle-language selection, on-screen progress, and partial-file resume on retry. A signed video link is refreshed once when it expires. Downloads run **only while the app stays open**; pause or leaving the page retains the partial file for retry. The Downloads tab shows whether a subtitle was saved.
- Offline playback from Downloads with saved subtitles, automatic Continue Watching progress by title/season/episode, and delete confirmation.

Android's local HTTP access is enabled for a private scraper server. For a remote deployment, use HTTPS. MovieBox may change or restrict streams; the API's `limited`/`vip_locked` state does not bypass those restrictions.

## Checks

```sh
flutter analyze
flutter test
flutter build apk --debug
```
