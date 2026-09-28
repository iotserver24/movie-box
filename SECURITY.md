# Security policy

## Support status

Security fixes are handled on a best-effort basis on the current `main` branch. There is no guaranteed response time, supported historical release matrix, or completed security audit. Use the latest reviewed revision and monitor upstream dependency advisories.

## Reporting a vulnerability

Use GitHub's **Report a vulnerability** option under this repository's **Security** tab if private vulnerability reporting is enabled:

https://github.com/iotserver24/movie-box/security/advisories/new

This document does not mean the repository setting has already been enabled. A read-only API check on September 28, 2026 returned HTTP 404 while this repository was private; availability remains unverified. If that option is unavailable, open an issue containing only a request for a private reporting channel. Wait for the maintainer to arrange a private channel before sharing technical details. Do not put exploit details, credentials, private data, or sensitive reproduction steps in a public issue.

In a private report, provide the affected revision, impact, prerequisites, and minimal reproduction using synthetic data. Redact credentials and avoid including third-party media or signed URLs. Coordinate disclosure with the maintainer; do not access other people's deployments or data to demonstrate an issue.

## Deployment considerations

- Keep the API on localhost or a trusted private network/VPN where possible.
- Set a unique, strong `SCRAPER_API_TOKEN` before binding beyond localhost. Rotate it if exposed.
- Use HTTPS for remote hosts. The Android app permits cleartext HTTP for local use; HTTP does not protect the token in transit.
- `/health`, `/docs`, `/redoc`, and `/openapi.json` are not protected by the token dependency. Restrict them at the network or reverse-proxy layer where appropriate.
- The current service has no multi-user access control, application rate limiter, or production security guarantee. Review additional safeguards before public deployment.
- Tokens in the app are stored in shared preferences, not a dedicated encrypted credential store. Use only a token scoped to your own scraper deployment.
- Review dependency updates and third-party media hosts. Treat upstream data and returned URLs as untrusted.
- Keep `.env`, signing material, service credentials, and personal logs out of commits, issues, and release artifacts. Review the entire Git history before changing repository visibility.

See [privacy](docs/privacy.md) and the [release checklist](docs/releasing.md) for related responsibilities.
