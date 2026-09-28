# Publication review record

Review date: September 28, 2026. The initial review covered base commit `e33ff2b` and the preparation changes subsequently committed as `221d703`. Scan counts below describe that pre-publication baseline. The user explicitly authorized pushing the reviewed source and making the repository public; publication does not establish legal approval or production-release readiness.

## Automated secret detection

- The checkout is not shallow. All locally reachable history was examined: **2 commits and 53 unique file blobs**.
- `detect-secrets` 1.5.0 contextual line-based detectors inspected **48 UTF-8 history blobs** and the non-ignored working-tree text files. Five binary blobs were skipped in history; five binary files were skipped in the working tree. The review used a 2 MB per-file limit; no oversized text files were skipped.
- Credential validation against remote services was disabled, and socket connections were blocked during scanning. No candidate values or account credentials were printed, stored in a report, or sent for validation.
- The contextual scan produced 165 deduplicated candidates across history and working files. Matching the candidate values to their actual structured fields classified **163 as dependency SHA-256 checksums** and **2 as Flutter SDK revisions**. **No unresolved credential candidates remained in this scan.**

This is not proof that the repository contains no secrets or personal information. The scan does not cover ignored local files, binary contents, unreachable/deleted Git objects, un-fetched remote refs, Git LFS storage, releases, Actions logs/artifacts, issues, or third-party systems. It is a heuristic code scan, not a manual ownership, privacy, or complete security audit. Re-run an approved scanner on the exact publication commit and examine all remaining material before changing visibility.

## Other findings

- The app still defaults to an external hosted API. Review the operator's policy and the choice of default before publication; see [privacy](privacy.md). Documenting an endpoint is not approval of that deployment's practices.
- The standalone `script.py` starts a hard-coded commercial-film download example when executed. It was not executed as part of validation, and no downloaded media was found in the publication inventory. Its presence grants no rights to the referenced film; review or replace the example before using it.
- Settings retains the token when changing server addresses and sends it during the connection check. Clear credentials before switching operators; automatic clearing or reconfirmation remains an application-hardening task.
- The five binary files in the working tree and reachable history are launcher PNGs showing the Flutter logo. Inspection found only an Adobe ImageReady metadata tag and no trailing payload. These are third-party branding, not verified original project artwork; provenance and branding approval remain outstanding.
- Root Git and Docker ignore rules now exclude signing files and local environment variants while keeping `.env.example` and required notices publishable.
- Private vulnerability reporting was enabled after publication. GitHub's API returned `enabled: true`, and the public Security page displayed **Report a vulnerability**. No report was submitted. Earlier checks while the repository was private returned HTTP 404.
- A preliminary dependency inventory is recorded in [dependency review](dependency-review.md). It does not cover every transitive/native dependency or container component.
- The signing fallback and missing app notice UI have been addressed in source. Official Flutter 3.47.5 stable (Dart 3.13.4) passed dependency resolution with the existing lockfile, formatting, static analysis, and all 14 tests. A normal debug APK built; its debug certificate and bundled notices verified. The automatically generated disposable debug key was kept outside the repository and deleted after verification. No production signing credentials were generated or requested.
- Real Gradle checks rejected missing/incomplete production-signing configuration and a nonexistent keystore path. A Docker image build and isolated health/auth/schema/nonroot/notice smoke checks passed. Test services were stopped and no artifacts were published. Production signing and device behavior remain unverified.

## Maintainer decisions still required

1. Confirm ownership and permission to publish every contribution, asset, and history entry, including the skipped binary files.
2. Obtain legal review of the custom license and third-party redistribution obligations.
3. Supply the intended production signing environment securely and complete the [signing checks](signing.md).
4. Repeat the passing Python, Flutter, debug-build, and container checks against the release commit, and complete Android device tests with authorized media.
5. Review the existing default API policy and token-on-host-change behavior before production deployment. A future binary release still requires separate approval.

## Publication outcome

The reviewed source was committed as `221d703` and pushed to `main`. On the user's explicit instruction, the repository was changed to **public** and private vulnerability reporting was enabled. The repository and README were verified in a signed-out browser. A final scan of the exact staged source checked 66 text files, skipped the five reviewed PNGs, and left no unresolved credential candidates after structured-checksum classification.

Only source and documentation were published. No release tag, APK, container image, production credential, or running service was published. Legal/ownership confirmation and the remaining release checks above are not claimed as complete.
