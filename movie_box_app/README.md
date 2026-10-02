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

- Five tabs in this order: Home, Library (bookmarked titles), Search, Downloads, and Settings. Wide Android TV screens use a navigation rail instead of bottom tabs. Home includes a popular carousel, catalogs, cached artwork, and Continue Watching cards with episode, watched time, and a red progress bar. Search returns results as you type.
- Tapping an ordinary title opens its information page with the complete season and episode list. Continue Watching opens the most recently watched episode directly and resumes its saved position; it shows one card per series or movie. The player loads the complete episode list even when the current episode is downloaded, so another episode can be streamed or played offline if saved.
- On phones, the video sits above download, quality, subtitle, title, and episode controls. On TV-sized screens, playback opens directly into an immersive video player with an on-screen remote panel for previous/next episode, season and episode selection, quality, subtitles, and download. English subtitles are selected automatically when available. Tap to show controls, double-tap the left or right side to seek ten seconds. On a keyboard, use F for phone fullscreen and Escape to exit; when the video has focus, Space or Enter toggles playback and Left/Right seeks ten seconds. On a TV remote, use the D-pad to navigate controls, center to select, Left/Right on the video to seek, and Back to leave the player. The screen remains awake while the app is open; TV Search has remote-selectable Search and Clear buttons.
- Custom amber film-frame loading animation for Home, catalogs, search, title details, connection checks, download options, and the player. Player status distinguishes opening, buffering, episode changes, quality changes, and subtitles. Reduced-motion accessibility settings keep the status static; hidden tabs and background apps stop animating.
- Download quality and subtitle-language selection, on-screen progress, and partial-file resume on retry. A signed video link is refreshed once when it expires. Downloads run **only while the app stays open**; pause or leaving the page retains the partial file for retry. The Downloads tab shows whether a subtitle was saved and uses a frame extracted from each saved episode as its thumbnail.
- Offline playback from Downloads with saved subtitles, automatic Continue Watching progress by title/season/episode, and delete confirmation. Existing downloads receive thumbnails when the app next starts and the saved video is available.

Android's local HTTP access is enabled for a private scraper server. For a remote deployment, use HTTPS. MovieBox may change or restrict streams; the API's `limited`/`vip_locked` state does not bypass those restrictions.

## Checks

```sh
flutter analyze
flutter test
flutter build apk --debug
```
