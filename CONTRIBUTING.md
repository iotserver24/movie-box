# Contributing to Movie Box

Thanks for helping improve Movie Box by **R3AP3R Editz**. Read the [license](LICENSE) and [code of conduct](CODE_OF_CONDUCT.md) first. This is a source-available project: contributions must preserve creator credit, remain ad-free, and comply with the prohibition on selling the software or charging for access.

## Before starting

- Search existing [issues](https://github.com/iotserver24/movie-box/issues) and [pull requests](https://github.com/iotserver24/movie-box/pulls).
- Open an issue before large changes so scope and compatibility can be discussed.
- Use [SECURITY.md](SECURITY.md) for vulnerabilities, not a public exploit report.
- Contribute only code and assets you have the right to submit. Do not include downloaded media, credentials, signed stream URLs, or copied code with incompatible terms.

## Development workflow

1. Fork the repository if access allows, clone your fork, and create a focused branch.
2. Follow [setup](docs/setup.md) for the API and Android app.
3. Make a scoped change consistent with the surrounding code.
4. Add or update regression tests and documentation when behavior changes.
5. Run the relevant checks and review `git diff --check` before opening a pull request.

Python checks, from the repository root with the development environment activated:

```sh
python -m pytest scraper/tests -q
python -m unittest discover -s scripts/tests -v
python scripts/sync_notices.py --check
```

`LICENSE` and `CREDITS.md` at the repository root are the canonical notices. If you intentionally update either, run `python scripts/sync_notices.py` and include the corresponding `movie_box_app/assets/notices/` changes. The check command fails without writing when a bundled notice is missing or stale.

Flutter checks, from `movie_box_app/`:

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
```

The formatter command reports changes that would be needed without rewriting files. If existing formatting or checks fail, distinguish pre-existing failures from your change and avoid unrelated cleanup. State which checks you ran, their results, and any checks you could not run.

Tests should use small, synthetic or suitably licensed fixtures and avoid live provider calls. Never run the standalone downloader as a test or download full media merely to validate a change. Keep provider-specific parsing in `scraper/provider.py` and preserve app-facing response contracts unless a coordinated API change is intended.

## Pull requests

Explain the problem, proposed behavior, related issues, and validation. Include screenshots for visible changes, with personal information and tokens removed. Call out dependency changes, migration steps, security implications, and third-party license obligations. Separate unrelated changes into different pull requests.

New features must not introduce advertisements, paid access, license circumvention, or removal of required attribution. Modified distributions must clearly distinguish themselves from the original project.

## Contribution terms

By intentionally submitting a contribution for inclusion, you offer it under the repository's [license](LICENSE), unless separately agreed in writing. You retain copyright in your work and must have authority to contribute it. Existing third-party notices must be retained; this process does not transfer ownership of work you do not own.
