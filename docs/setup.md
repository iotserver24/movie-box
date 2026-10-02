# Setup and troubleshooting

## Requirements

- Git and access to the repository.
- Docker Engine/Desktop with the Docker Compose plugin for the container setup.
- Alternatively, Python 3.12 and virtual-environment support for local API development. The container uses Python 3.12.
- Use **Flutter 3.47.5 stable (Dart 3.13.4)** for the documented validation environment. It satisfies `^3.13.1` in `movie_box_app/pubspec.yaml`. Android builds also require Android SDK tools and an emulator or physical device for runtime checks. Run `flutter doctor` to check your environment; the SDK is not bundled with this repository.

Commands below assume a POSIX shell and start in the repository root unless stated otherwise. On Windows, use the equivalent virtual-environment activation and file-copy commands.

## Docker API

```sh
cp .env.example .env
docker compose up --build -d
curl http://127.0.0.1:8000/health
```

Copy `.env.example` only on first setup so you do not overwrite existing configuration. Compose loads `.env` automatically.

| Variable | Default | Meaning |
| --- | --- | --- |
| `SCRAPER_BIND` | `127.0.0.1` | Host interface on which Compose publishes port 8000 |
| `SCRAPER_API_TOKEN` | Empty | When set, `/v1/` requests require `Authorization: Bearer <token>` |

Generate a token locally, for example with `openssl rand -hex 32`, and store it only in your local `.env` and the client settings. Do not post its output or commit the file. Set the token before exposing the port beyond localhost.

`/health` is deliberately unauthenticated; it does not prove the upstream provider is reachable. FastAPI's schema and documentation at `/openapi.json`, `/docs`, and `/redoc` are also not covered by the `/v1/` token dependency. The container health check only checks `/health`.

After changing environment values:

```sh
docker compose up -d --force-recreate
```

Inspect startup problems and stop the service with:

```sh
docker compose logs --tail=100 scraper
docker compose down
```

Review and redact logs before sharing them. For a token-protected API, use an HTTP client configured to send the bearer token on `/v1/` calls. Swagger UI currently has an `authorization` header parameter on protected operations, rather than an OAuth login flow.

## Local Python API (without Docker)

```sh
python3.12 -m venv .venv
. .venv/bin/activate
python -m pip install -r scraper/requirements-dev.txt
python -m uvicorn scraper.app:app --host 127.0.0.1 --port 8000
```

The application reads `SCRAPER_API_TOKEN` from the process environment; it does **not** load `.env` by itself. Set that variable in your local environment or service manager when authentication is needed. `SCRAPER_BIND` is a Compose setting, not a Uvicorn setting; choose the Uvicorn `--host` explicitly for a private device connection.

Open `http://127.0.0.1:8000/docs` for the API reference. To run the fixture-based tests from another terminal with the virtual environment activated:

```sh
python -m pytest scraper/tests -q
```

## Android app

From the repository root:

```sh
cd movie_box_app
flutter doctor
flutter pub get
flutter devices
flutter run
```

If multiple devices are connected, select one with `flutter run -d DEVICE_ID`, using an ID from `flutter devices`.

Open **Settings** and set the API address before entering its token:

| Client | API address |
| --- | --- |
| Standard Android emulator on the API host | `http://10.0.2.2:8000` |
| Physical device on the same private LAN/VPN | `http://YOUR_PRIVATE_SERVER_IP:8000` |
| Remote HTTPS deployment you operate | Your deployment's `https://` address |

For a physical device, change `SCRAPER_BIND` to the server's private interface address, set a token, recreate the container, and permit only trusted devices through the firewall. `localhost` on a phone points to the phone, not your development computer. Docker networking can vary by host; if emulator access fails, inspect the host firewall and port forwarding rather than opening the service to the public internet.

Android cleartext HTTP is enabled for private local deployments. Use HTTPS for remote deployments, and prefer a private VPN rather than public exposure. The app stores the API token in ordinary shared preferences, not a dedicated encrypted credential store; use a unique, limited-purpose token. See [privacy](privacy.md).

### App checks and debug build

From `movie_box_app/`:

```sh
flutter analyze
flutter test
flutter build apk --debug
```

The normal debug APK output is `build/app/outputs/flutter-apk/app-debug.apk`. A debug APK is for testing, not a signed production release. Production signing no longer falls back to a debug key: see [signing setup](signing.md) for the required environment and failure checks. See the [release checklist](releasing.md) before distributing builds.

Before any build, run `python3 scripts/sync_notices.py --check` from the repository root. Settings includes a **Credits and licenses** page with bundled project notices, dependency licenses, and an optional donation-link copy button.

## Troubleshooting

- **Cannot connect:** Check that the API is running, the address is reachable from the device, the port is allowed on the trusted interface, and Settings points at the intended server.
- **Health succeeds but catalog fails:** `/health` does not contact the provider or test authentication. Check the token and upstream error; the provider may have changed or be unavailable.
- **Settings saves but browsing returns HTTP 401:** **Connect and save** checks only `/health`, so success does not validate the token. The client token must match `SCRAPER_API_TOKEN`. Compose must be recreated after a token change.
- **Expired playback/download URL:** Refresh playback details or retry the download. Signed links are temporary; available quality and access restrictions are controlled upstream.
- **Download stops:** Downloads are foreground-only. Keep the app open; partial files are retained for retry, but this is not an Android background-download service.
- **Dart version resolution fails:** Install a Flutter version that bundles a Dart SDK satisfying the manifest constraint. Avoid lowering the constraint without testing the code.

The standalone `script.py` is an experimental, hard-coded downloader using `requests`. It is not required by either setup and should not be used as a health check: running it starts a media download.
