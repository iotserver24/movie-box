# Architecture

## Components

- **`movie_box_app/`** is the Flutter Android client. `api.dart` calls the scraper API, `model.dart` parses response models, `screens.dart` contains the main screens, `player.dart` handles playback, and `library.dart` stores preferences, watch history, bookmarks, and download state.
- **`scraper/app.py`** exposes FastAPI endpoints and optional bearer-token validation. `models.py` defines response schemas, and `provider.py` adapts upstream catalog and playback services to that API.
- **`movie_box_app/lib/notices.dart`** displays creator credit, the bundled project license and acknowledgments, and Flutter's dependency-license page. `scripts/sync_notices.py` synchronizes the app assets from the canonical root notices; `--check` detects drift without writing.
- **`compose.yaml` and `scraper/Dockerfile`** package the Python service. The container runs as a non-root numeric user and publishes port 8000 to the host's loopback interface by default.
- **`script.py`** is a separate experimental downloader with a hard-coded title. Neither the Flutter client nor the API imports it as part of normal startup.

## Request flow

```text
Flutter client --> scraper API --> upstream catalog / playback services
Flutter client -----------------> returned artwork, media, and subtitle URLs
```

The API returns metadata, stream URLs, and required request headers. It does not proxy or store the video. Playback and downloads contact the returned media hosts from the device. Catalog/detail responses have a short in-memory cache; playback and caption links are fetched fresh.

The API has no database or user-account system. A deployment may require a shared bearer token on `/v1/` requests. Its health and API-documentation endpoints remain unauthenticated. The client stores local state in shared preferences and downloaded files in its application documents directory.

## Boundaries and limitations

- Provider parsing and upstream compatibility belong in `provider.py`; keep app-facing response contracts stable when fixing upstream changes.
- Signed stream links can expire. Download handling refreshes a link once on an expiry-related failure; availability is not guaranteed.
- Downloads are foreground operations, not background Android jobs.
- Upstream season-level information may not describe every episode's exact quality or title.
- An available stream listing does not grant access rights or bypass provider restrictions.
- Shared bearer-token authentication is not a multi-user authorization, rate-limiting, or billing system. Treat the service as a private deployment unless additional protections are implemented and reviewed.

See [API documentation](../scraper/README.md), [privacy](privacy.md), and [security](../SECURITY.md) for operational details.
