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

The default API address `http://10.0.2.2:8000` reaches the host's localhost from the standard Android emulator. On a physical phone, set `SCRAPER_BIND` in the parent's `.env` to the host's private network address, set `SCRAPER_API_TOKEN`, restart Docker Compose, and enter `http://<host-private-ip>:8000` and the token in the app's Settings. Keep the device and server on the same trusted network or private VPN; do not publish the unauthenticated service to the internet.

## Features

- Home sections, movie/series/animation catalogs, suggestions, search pagination, details, seasons and episodes.
- Playback of current MP4 streams with quality selection, seeking, and separate SRT subtitle selection. The app obtains a fresh signed URL each time playback starts.
- MP4 download into private app storage with on-screen progress and partial-file resume on retry. If a signed link expires, it is refreshed once. Downloaded English subtitles are saved when the provider supplies them. Downloads run **only while the app stays open**; pause or leaving the page retains the partial file for retry.
- Offline playback and removal from the Library tab. Local Continue Watching progress resumes by title, season, and episode and clears near the end.

Android's local HTTP access is enabled for a private scraper server. For a remote deployment, use HTTPS. MovieBox may change or restrict streams; the API's `limited`/`vip_locked` state does not bypass those restrictions.

## Checks

```sh
flutter analyze
flutter test
flutter build apk --debug
```
