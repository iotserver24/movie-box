# MovieBox scraper API

A personal, Dockerized API for the public MovieBox catalog. The Android client should call this service rather than parse the site's pages. The existing root `script.py` downloader is independent.

## Start

From the `movie-box` directory:

```sh
cp .env.example .env
docker compose up --build -d
curl http://127.0.0.1:8000/health
```

By default the port is bound to localhost only. For an Android device on the same trusted network, set `SCRAPER_BIND` to the host's private network address and `SCRAPER_API_TOKEN` to a strong random value in `.env`, then restart Compose. Send `Authorization: Bearer <token>` with API requests. Use a private VPN rather than exposing this service on the public internet. Interactive OpenAPI documentation is at `/docs`.

## API

- `GET /v1/home`: banner titles and editorial sections (including animation and other public sections when present).
- `GET /v1/collections/movies` and `GET /v1/collections/midnight`: editorial sections for those site tabs. Home also includes anime and TV sections.
- `GET /v1/browse?page=1&kind=movie`: paginated trending titles. `kind=movie` selects the movie tab automatically; `tab=home|movies|midnight` can select a tab explicitly. `kind` may be `movie`, `series`, `short_series`, or `other`. Kind filtering within a tab can still leave some pages sparse.
- `GET /v1/catalog/movies`, `/v1/catalog/series`, or `/v1/catalog/animation`: paginated full catalog with optional `page`, `genre`, `country`, `year`, `language`, and `sort` query parameters. `GET /v1/catalog/series/filters` and `/v1/catalog/animation/filters` expose the site's current filter choices. Movie filter choices are not published in the available page data; the same query parameters still work for movies.
- `GET /v1/rankings`: current chart names and IDs. `GET /v1/rankings/{id}?page=2` returns paginated chart titles.
- `GET /v1/search?q=masters&page=2`: paginated search using a first-party anonymous session obtained by the scraper. If that search service fails, page 1 falls back to the server-rendered page and reports `has_more=false`; later pages return an error rather than inventing results. `GET /v1/search/suggestions?q=masters` and `GET /v1/search/popular` supply autocomplete and popular terms.
- `GET /v1/titles/{detail_path}`: title, cast, available seasons, and alternative audio/dub title paths.
- `GET /v1/titles/{detail_path}/episodes?season=1`: episode numbers. The provider reports season-level counts and qualities, not reliable per-episode titles or quality availability.
- `GET /v1/titles/{detail_path}/recommendations?page=1`: related titles.
- `GET /v1/titles/{detail_path}/playback?season=1&episode=1`: current MP4/DASH/HLS variants and request headers. Movies use the default season/episode `0`. Call again when a signed link expires.
- `GET /v1/titles/{detail_path}/captions?stream_id=...&season=1&episode=1`: separate subtitle URLs for a selected playback stream. Match season/episode to the playback request.

Example:

```sh
curl 'http://127.0.0.1:8000/v1/titles/masters-of-the-universe-g6fDdvegRi9/playback'
```

Catalog and detail responses have a short in-memory cache; playback and caption links are fetched fresh and never cached. `max_resolution` reports the site's current player limit separately from listed stream variants. The scraper does not proxy or store video. Downloads and Continue Watching belong in the Android app; it should refresh links on playback/download retry and persist progress locally.

## Tests

```sh
python -m pip install -r scraper/requirements-dev.txt
python -m pytest scraper/tests -q
```

Live checks should use a small byte-range request, not download an entire movie. Site behavior can change; update the provider adapter and its fixtures without changing the app-facing API.
