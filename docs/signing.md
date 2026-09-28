# Android production signing

Release builds use a dedicated signing configuration and no longer fall back to the Android debug key. Debug builds remain available without release credentials. The `preReleaseBuild` task depends on `verifyReleaseSigning`, which checks the configuration before the normal release build proceeds.

## Supply credentials outside the repository

Use a keystore owned by the maintainer, stored outside the checkout with restricted access and a secure backup. Supply these environment variables through a trusted local environment or a CI secret store:

| Variable | Value |
| --- | --- |
| `MOVIE_BOX_KEYSTORE_PATH` | Absolute path to the existing keystore on the build machine |
| `MOVIE_BOX_STORE_PASSWORD` | Keystore password |
| `MOVIE_BOX_KEY_ALIAS` | Alias of the intended production signing key |
| `MOVIE_BOX_KEY_PASSWORD` | Password for that key |

All four values must be nonempty. The path must identify a real file. Missing configuration must fail a normal release build rather than produce a debug-signed release. Android's signing task performs the actual password, alias, and keystore validation.

No keystore is generated, password selected, or signing identity provisioned by this repository. Never paste credentials into chat, commit them, place literal passwords in commands saved to shell history, or upload environment dumps or Gradle caches. A signing key determines update compatibility; use the intended existing key for an app that has already been distributed. Do not replace that key casually.

## Build and verify

After the maintainer supplies the signing environment, from the repository root:

```sh
python3 scripts/sync_notices.py --check
cd movie_box_app
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

The standard APK path is `movie_box_app/build/app/outputs/flutter-apk/app-release.apk` relative to the repository root. For a store bundle, use `flutter build appbundle --release` after checking the store's signing and application-ID requirements.

On a machine with Android SDK Build Tools, from the repository root:

```sh
apksigner verify --verbose --print-certs movie_box_app/build/app/outputs/flutter-apk/app-release.apk
sha256sum movie_box_app/build/app/outputs/flutter-apk/app-release.apk
```

Compare the displayed signing-certificate fingerprint with the maintainer's expected production fingerprint. Do not rely on a successful build alone. Test installation and updates on a device, and keep the release key out of the published artifacts. Uploading to a store or publishing an artifact requires a separate maintainer decision.

## Required checks before distribution

- With all signing variables absent, confirm `flutter build apk --release` fails at the release-signing check.
- Confirm an incomplete configuration or nonexistent keystore path also fails.
- Confirm `flutter build apk --debug` still works without production credentials.
- With the real signing environment supplied securely, build, inspect the certificate, and test the artifact.
- Verify credits, the full custom license, and dependency notices inside the installed app.

## Validation record — September 28, 2026

Using Flutter 3.47.5, Dart 3.13.4, OpenJDK 21, Gradle 9.3.1, Android Gradle Plugin 9.1.0, Android API 36, Build Tools 36.0.0, and NDK 28.2.13676358:

- A real `flutter build apk --release --no-pub` with all production credentials absent failed at `verifyReleaseSigning` as intended.
- Real `preReleaseBuild` checks rejected incomplete configuration and a nonexistent keystore path.
- An isolated real-Gradle fixture passed 11 expected-outcome cases for the unchanged guard, including individually missing values, whitespace, relative/nonexistent/directory paths, and a debug-task control.
- A normal `flutter build apk --debug --no-pub` succeeded with the unchanged repository configuration in a fresh temporary copy, without production credentials. Android generated a disposable debug key outside the repository; it was deleted after verification.
- `apksigner verify --verbose --print-certs` passed for the debug APK (Signature Scheme v2). The certificate was `CN=Android Debug, O=Android, C=US`, matched the temporary keystore, and the manifest declared `debuggable=true`. This verifies debug signing only.
- Packaged `LICENSE` and `CREDITS.md` matched the canonical root files byte for byte. The debug artifact remained local and was not published.

The path guard does not validate keystore contents, passwords, or aliases; Android signing tools must perform that validation with the maintainer's actual signing environment. Production certificate verification and device installation/update tests remain outstanding. Build logs warn about deprecated Android Gradle Plugin legacy DSL/Kotlin settings and future Gradle 10 incompatibilities. No production signing key was generated or supplied.
