# Public publication and release checklist

This is a checklist for maintainers, not a statement that the project has already passed these checks. Adding documentation does not change repository visibility, enable GitHub settings, or publish a release.

## Publish an Android release with GitHub Actions

Open **Actions → Android release → Run workflow**, select `main`, and enter:

- **version**: a new `major.minor.patch` version without `v`, for example `1.0.3`.
- **build_number**: an Android version code higher than all previous releases and the source `pubspec.yaml` build number, for example `4` for the first release.

The version must also be newer than the source version and previous published versions. The workflow builds exactly the selected commit, overriding the APK version without editing `pubspec.yaml`. It only runs release jobs from `main`. Runs are serialized, and existing tags/releases are never overwritten.

Configure these repository Actions secrets once under **Settings → Secrets and variables → Actions**:

- `MOVIE_BOX_KEYSTORE_BASE64`: base64-encoded production keystore.
- `MOVIE_BOX_STORE_PASSWORD`: keystore password.
- `MOVIE_BOX_KEY_ALIAS`: signing key alias.
- `MOVIE_BOX_KEY_PASSWORD`: signing key password.

Keep the same key for subsequent releases and maintain a secure offline backup. See [signing](signing.md). Secrets are only exposed to the signing step; the temporary keystore is deleted, and neither it nor Gradle caches are uploaded.

The workflow checks bundled notices, release-validation tests, Flutter analysis, and Flutter tests using Flutter 3.47.1. It builds a universal release APK, verifies its signature against the supplied keystore certificate, checks the APK version and non-debuggable status, then publishes a GitHub release containing:

- `MovieBox-<version>.apk`
- `SHA256SUMS`
- `signing-certificate.txt` (public certificate details, not the private key)

The release tag points to the exact workflow commit. A draft is created with all assets before publication. If publication fails after draft creation, inspect the draft and run logs before deleting that draft and retrying; remove a tag only if it belongs to that failed, unpublished attempt. Never replace an already published APK/tag. Failed checks or builds publish nothing. Device installation, update compatibility, and the checklist below remain maintainer responsibilities.

The same workflow can be started from the terminal:

```sh
gh workflow run android-release.yml --ref main -f version=1.0.3 -f build_number=4
```

## Preparation status — September 28, 2026

| Area | Current status and next step |
| --- | --- |
| Source documentation | README, component guides, community policies, and the custom source-available license were committed and pushed to `main`. |
| Ownership and license | Creator credit, no advertising, no selling, and optional donations are specified. Preliminary Python and resolved Flutter license-file checks are recorded in [dependency review](dependency-review.md); full compatibility, provenance, and legal approval remain outstanding. |
| App notices | Settings links to creator credit, bundled custom-license and acknowledgment screens, and Flutter's dependency-license page. All 14 Flutter tests passed, including notice navigation, offline license loading, and donation-link copying. Installed-device and shipped-notice completeness checks remain required. |
| Service image notices | The Docker image built successfully. Its `/app/LICENSE` and `/app/CREDITS.md` matched the root files, and isolated runtime checks passed. Complete third-party/container notice review remains required before distribution. |
| Android signing | The debug-signing fallback is removed. Real Gradle checks rejected absent/incomplete production settings and a nonexistent keystore path. A normal debug APK built and its debug signature and bundled notices verified. Production signing, production certificate verification, and device checks remain outstanding; see [signing](signing.md). |
| Secrets and history | A contextual automated scan of reachable text history and non-ignored working text files left no unresolved credential candidates after checksum/revision classification. Binary, ownership, privacy, and other manual checks remain outstanding; see [publication review](publication-review.md) for scope and exclusions. |
| Private vulnerability reports | Enabled after publication; GitHub's API confirmed the setting and the public Security page displayed the reporting link. No report was submitted. |
| Donations | The requested URL loads a XibeCode-branded support page with a public-donor notice. Confirm that branding and disclosure are appropriate; see [privacy](privacy.md#donations). |
| GitHub publication | The user explicitly authorized publication. Source commit `221d703` was pushed and the repository made public on September 28, 2026. No binary release or service deployment was published; unresolved legal and release checks remain listed below. |

### Validation performed for this preparation

- Python 3.12 suites: **9 tests passed** (six API fixture tests and three notice-synchronization tests), with one dependency deprecation warning about AnyIO's `BlockingPortal` alias. Dependencies were installed in an isolated `uv` environment; live socket connections were blocked during tests.
- Bundled notices match the canonical `LICENSE` and `CREDITS.md` byte for byte. Tree-sitter syntax parsing passed for the changed Dart source, new widget tests, and Kotlin build script; this is not type analysis or build execution.
- Separate synthetic API checks confirmed unauthenticated health/schema pages, bearer-token rejection and acceptance on `/v1/home`, and the documented header parameter across all protected routes. No provider requests or media downloads were made.
- Checks passed for 18 Markdown documents, 65 local links/anchors, 21 shell examples, and five YAML files, along with asset registration, funding URL, image-notice configuration, and `git diff --check`. The byte-identical bundled credits asset is displayed as plain text and excluded from root-relative Markdown link checking. The source and documentation are now pushed to `main`, and the public README was verified in a signed-out browser.
- The donation page was opened and its public notice reviewed; no donation, payment, or form submission was attempted.
- Using official **Flutter 3.47.5 stable / Dart 3.13.4**, dependency resolution with `--enforce-lockfile`, formatting checks, static analysis, and **all 14 Flutter tests passed** in an isolated copy. The offline license test also passed independently without a previously warmed asset cache. The repository lockfile was preserved.
- A normal Android debug APK built successfully; its debug signature, debuggable manifest, and bundled notices verified. Real release-build checks rejected missing/incomplete signing settings and a nonexistent keystore path; an isolated Gradle fixture passed 11 expected-outcome cases. See [signing](signing.md) for scope. Production signing and device installation/update behavior remain unverified.
- Docker 29.1.3 built the service image. With runtime networking disabled and no published ports, container-loopback checks confirmed health HTTP 200, missing/wrong-token HTTP 401, public docs/schema HTTP 200, 16 schema paths, UID 10001, and exact project notices. No provider requests were made. The test container and private daemon were stopped; no service was deployed.

## Before making the repository public

- [ ] Review every tracked file and the complete Git history for credentials, private endpoints, personal information, downloaded media, signing material, and code or assets you do not have permission to publish. A clean working tree is not a security audit.
- [ ] Rotate any exposed credentials; deleting a file in a new commit does not remove it from history.
- [ ] Confirm ownership and contributor permissions for the code and assets being licensed.
- [ ] Have the custom license reviewed for the intended credit, no-advertising, and no-selling conditions. Describe the project as source-available, not OSI-approved open source.
- [ ] Review direct and transitive dependency licenses, including resolved Python dependencies, Android packages, and container contents. Preserve required notices.
- [ ] Review the default server address in the app. Decide whether to retain it, document its operator policy, or replace it before publication.
- [x] Enable private vulnerability reporting on GitHub and verify the API setting and public reporting link. End-to-end report submission was not tested.
- [ ] Establish a private conduct-reporting contact and document it if one is available.
- [ ] Configure repository description, topics, issue settings, and appropriate default-branch protections.
- [ ] Configure and validate continuous integration for Python tests and Flutter formatting, analysis, and tests, using the documented Flutter 3.47.5 stable SDK. Local passing checks do not establish continuous integration.
- [ ] Confirm the donation URL in `README.md` and `.github/FUNDING.yml` is the intended destination.
- [x] Obtain explicit authorization before changing repository visibility. The user authorized the push and public visibility change; this does not certify the unresolved review items above.

## Before distributing an app or service release

- [ ] Run Python tests and Flutter checks described in `CONTRIBUTING.md`, and record results against the release commit.
- [ ] Test installation, server configuration, authentication, playback, subtitle selection, foreground download retry, offline playback, and saved progress on a supported Android device with media you are authorized to use.
- [ ] Run `python3 scripts/sync_notices.py --check`, then verify that creator credit and the full custom license are accessible through Settings in the installed app. Verify that Flutter's generated dependency notices cover the shipped packages; the new screen alone does not prove completeness.
- [ ] Confirm there are no ads, paid access, or paid feature unlocks, including in download links and hosted access pages.
- [ ] Review Android production signing and package/version configuration. Follow [signing setup](signing.md), test rejection of missing or incomplete credentials, and verify the built artifact's production certificate. Never commit signing keys or their passwords.
- [ ] Review privacy and deployment documentation against the build's actual behavior.
- [ ] Prepare release notes describing changes, known limitations, compatibility, and the exact commit used.
- [ ] Build artifacts in a controlled environment, inspect them for unintended files or credentials, and publish checksums alongside them. Verify `/app/LICENSE` and `/app/CREDITS.md` in a service image and collect required dependency notices; the credits file is not a full notice inventory.
- [ ] Obtain explicit approval before tagging, publishing artifacts, or changing repository settings.

## After release

Triage issues and security reports, review dependency advisories, and keep the documented setup current. Avoid promising support timelines that the project cannot maintain.
